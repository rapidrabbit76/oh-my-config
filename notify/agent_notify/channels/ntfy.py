"""ntfy (ntfy.sh or your own server): the sender's name in the title, its avatar as the icon."""

from __future__ import annotations

import re
from urllib.parse import urlsplit

from agent_notify.alert import Alert
from agent_notify.channels import Channel, Profile, Request, Setting, channel

TOPIC_URL = re.compile(r"^https?://[^/\s\"]+(/[^\s\"]*)?/[A-Za-z0-9_-]{1,64}$")
TOKEN = re.compile(r"^[A-Za-z0-9._-]+$")


@channel
class Ntfy(Channel):
    key = "ntfy"
    label = "ntfy"
    settings = (
        Setting(
            "NTFY_URL",
            "Topic URL",
            "https://ntfy.sh/<a long random topic>, or a topic on your own server",
            check=lambda v: bool(TOPIC_URL.match(v)),
        ),
        Setting(
            "NTFY_TOKEN",
            "Access token (optional)",
            "only for a server that needs one",
            is_secret=True,
            is_required=False,
            check=lambda v: bool(TOKEN.match(v)),
        ),
    )

    def request(self, alert: Alert, sender: Profile) -> Request:
        # JSON publishing goes to the server root and names the topic.
        server, _, topic = self.value("NTFY_URL").rpartition("/")
        message = "\n".join(part for part in (alert.body, alert.meta) if part) or alert.title
        body = {
            "topic": topic,
            "title": f"{sender.name} · {alert.title}",
            "message": message,
            "tags": [alert.style.tag],
            "priority": alert.style.priority,
        }
        if sender.avatar:
            body["icon"] = sender.avatar
        token = self.value("NTFY_TOKEN")
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return Request(server, body, headers)

    def describe(self) -> str:
        url = urlsplit(self.value("NTFY_URL"))
        return f"{url.scheme}://{url.netloc}/…" + (" with token" if self.value("NTFY_TOKEN") else "")
