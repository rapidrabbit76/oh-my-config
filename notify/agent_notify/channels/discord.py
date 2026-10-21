"""Discord, through a channel webhook: the sender's name and avatar per message."""

from __future__ import annotations

import re

from agent_notify.alert import Alert
from agent_notify.channels import Channel, Profile, Request, Setting, channel

WEBHOOK = re.compile(r"^https://(ptb\.|canary\.)?discord(app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$")


@channel
class Discord(Channel):
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
    )

    def request(self, alert: Alert, sender: Profile) -> Request:
        embed = {"title": f"{alert.style.icon} {alert.title}", "color": alert.style.color}
        if alert.body:
            embed["description"] = alert.body
        if alert.meta:
            embed["footer"] = {"text": alert.meta}
        body = {
            "username": sender.name,
            # An @everyone in an answer pings nobody.
            "allowed_mentions": {"parse": []},
            "embeds": [embed],
        }
        if sender.avatar:
            body["avatar_url"] = sender.avatar
        return Request(self.value("DISCORD_WEBHOOK_URL"), body)

    def describe(self) -> str:
        return "webhook …" + self.value("DISCORD_WEBHOOK_URL")[-4:]
