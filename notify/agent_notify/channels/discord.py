"""Discord: alerts through a channel webhook, each under the agent's own name
and avatar; with a bot token too, answers come back (reactions and replies
on those messages, read by the bot)."""

from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

from agent_notify import interactive as ia
from agent_notify.alert import Alert
from agent_notify.channels import Channel, Inbound, Interactive, Profile, Request, Setting, channel
from agent_notify.discord_api import Discord as Api

WEBHOOK = re.compile(r"^https://(ptb\.|canary\.)?discord(app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$")
SNOWFLAKE = re.compile(r"^\d{5,25}$")
BOT_TOKEN = re.compile(r"^[A-Za-z0-9._-]{30,100}$")


@channel
class Discord(Channel, Interactive):
    key = "discord"
    label = "Discord"
    settings = (
        Setting(
            "DISCORD_WEBHOOK_URL",
            "Webhook URL",
            "channel settings → Integrations → Webhooks → New Webhook → Copy Webhook URL",
            is_secret=True,
            check=lambda v: bool(WEBHOOK.match(v)),
        ),
        Setting(
            "DISCORD_BOT_TOKEN",
            "Bot token (optional, for answering from Discord)",
            "discord.com/developers → your app → Bot → Reset Token; then run agent-notify pair",
            is_secret=True,
            is_required=False,
            check=lambda v: bool(BOT_TOKEN.match(v)),
        ),
        Setting(
            "DISCORD_OWNER_ID",
            "Your Discord user id (set by agent-notify pair)",
            is_required=False,
            check=lambda v: bool(SNOWFLAKE.match(v)),
            is_asked=False,
        ),
    )

    def __init__(self, config):
        super().__init__(config)
        self.webhook = self.value("DISCORD_WEBHOOK_URL")
        self.api = Api(self.value("DISCORD_BOT_TOKEN"))
        self._channel_id: Optional[str] = None
        self._bot_id: Optional[str] = None

    # ─── One way ─────────────────────────────────────────

    def embed(self, alert: Alert, footer: str = "") -> Dict:
        embed = {"title": f"{alert.style.icon} {alert.title}", "color": alert.style.color}
        if alert.body:
            embed["description"] = alert.body
        text = " · ".join(p for p in (alert.meta, footer) if p)
        if text:
            embed["footer"] = {"text": text}
        return embed

    def message(self, embed: Dict, sender: Profile) -> Dict:
        body = {
            "username": sender.name,
            # An @everyone in an answer pings nobody.
            "allowed_mentions": {"parse": []},
            "embeds": [embed],
        }
        if sender.avatar:
            body["avatar_url"] = sender.avatar
        return body

    def request(self, alert: Alert, sender: Profile) -> Request:
        return Request(self.webhook, self.message(self.embed(alert), sender))

    def describe(self) -> str:
        two_way = " · answers on" if self.can_listen(self.config) else ""
        return "webhook …" + self.webhook[-4:] + two_way

    # ─── Two way ─────────────────────────────────────────

    @classmethod
    def can_listen(cls, config) -> bool:
        return bool(
            WEBHOOK.match(config.get("DISCORD_WEBHOOK_URL"))
            and BOT_TOKEN.match(config.get("DISCORD_BOT_TOKEN"))
            and SNOWFLAKE.match(config.get("DISCORD_OWNER_ID"))
        )

    @property
    def owner(self) -> str:
        return self.value("DISCORD_OWNER_ID")

    @property
    def channel_id(self) -> str:
        if self._channel_id is None:
            self._channel_id = str(self.api.webhook_info(self.webhook)["channel_id"])
        return self._channel_id

    @property
    def bot_id(self) -> str:
        if self._bot_id is None:
            self._bot_id = str(self.api.me()["id"])
        return self._bot_id

    def post_alert(self, alert: Alert, sender: Profile) -> bool:
        posted = self.api.webhook_post(self.webhook, self.message(self.embed(alert), sender))
        ia.remember_sent(str(posted["id"]), alert.agent, alert.session)
        return True

    def question_alert(self, question: "ia.Question") -> Alert:
        return Alert(question.agent, "wait", question.title, "", question.meta, question.session)

    def ask(self, question: "ia.Question", sender: Profile) -> Tuple[str, str]:
        embed = self.embed(self.question_alert(question))
        embed["description"] = question.text()[:4000]
        posted = self.api.webhook_post(self.webhook, self.message(embed, sender))
        channel_id, message_id = str(posted["channel_id"]), str(posted["id"])
        ia.add_pending(message_id, channel_id, question)
        ia.remember_sent(message_id, question.agent, question.session)
        for emoji in question.emojis():
            self.api.react(channel_id, message_id, emoji)
        return channel_id, message_id

    def _owner_reacted(self, channel_id: str, message_id: str, emoji: str) -> bool:
        return self.owner in self.api.reactors(channel_id, message_id, emoji)

    def poll_answer(self, channel_id: str, message_id: str, question: "ia.Question") -> Optional["ia.Answer"]:
        if question.kind == "approve":
            if self._owner_reacted(channel_id, message_id, ia.YES):
                return ia.Answer("allow")
            if self._owner_reacted(channel_id, message_id, ia.NO):
                return ia.Answer("deny")
            return None
        marks = list(zip(ia.NUMBERS, question.options))
        if question.multi:
            if not self._owner_reacted(channel_id, message_id, ia.YES):
                return None
            picked = [label for mark, label in marks if self._owner_reacted(channel_id, message_id, mark)]
            return ia.Answer("choice", values=picked) if picked else None
        for mark, label in marks:
            if self._owner_reacted(channel_id, message_id, mark):
                return ia.Answer("choice", values=[label])
        return None

    def start_cursor(self) -> str:
        return self.api.latest_message_id(self.channel_id) or "0"

    def poll_messages(self, cursor: str) -> Tuple[List[Inbound], str]:
        found = self.api.messages_after(self.channel_id, cursor)
        messages = []
        for m in found:
            author = m.get("author") or {}
            if m.get("webhook_id") or author.get("bot") or str(author.get("id")) != self.owner:
                continue
            ref = (m.get("message_reference") or {}).get("message_id")
            text = (m.get("content") or "").strip()
            if text:
                messages.append(Inbound(str(m["id"]), text, str(ref) if ref else None))
        return messages, (str(found[-1]["id"]) if found else cursor)

    def close(self, message_id: str, question: "ia.Question", sender: Profile, outcome: str, answered: bool) -> None:
        alert = Alert(question.agent, "done" if answered else "info", question.title, "", question.meta)
        embed = self.embed(alert, outcome)
        embed["description"] = question.text()[:4000]
        self.api.webhook_edit(self.webhook, message_id, {"embeds": [embed], "allowed_mentions": {"parse": []}})

    def ack(self, message: Inbound, delivered: bool) -> None:
        self.api.react(self.channel_id, message.id, ia.DELIVERED if delivered else ia.UNDELIVERED)

