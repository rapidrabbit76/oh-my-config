"""The few Discord REST calls two-way alerts need, with the bot token.

Alerts still go out through the channel's webhook (so each agent keeps its
own name and avatar); the bot only reads what you answer: reactions on an
alert and replies to it. Polling REST needs no gateway connection, no
public URL and nothing beyond the standard library.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

from agent_notify import __version__

API = "https://discord.com/api/v10"
TIMEOUT_S = 10
# Discord asks bots for this exact User-Agent shape.
USER_AGENT = f"DiscordBot (https://github.com/rapidrabbit76/oh-my-config, {__version__})"


class DiscordError(Exception):
    """A call that failed; ``status`` is the HTTP status (0: no answer)."""

    def __init__(self, status: int, what: str):
        super().__init__(f"{what} (http {status})")
        self.status = status


def emoji_path(emoji: str) -> str:
    return urllib.parse.quote(emoji, safe="")


class Discord:
    def __init__(self, token: str = "", api: str = API):
        self.token = token
        self.api = api

    def _call(self, method: str, url: str, body: Optional[Dict] = None, bot: bool = True, retries: int = 2) -> Any:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"User-Agent": USER_AGENT}
        if data is not None:
            headers["Content-Type"] = "application/json"
        if bot:
            headers["Authorization"] = f"Bot {self.token}"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
                text = response.read().decode("utf-8")
                return json.loads(text) if text else None
        except urllib.error.HTTPError as e:
            payload = e.read().decode("utf-8", "replace")
            e.close()
            if e.code == 429 and retries > 0:
                try:
                    wait = float(json.loads(payload).get("retry_after", 1))
                except ValueError:
                    wait = 1.0
                time.sleep(min(wait, 5.0))
                return self._call(method, url, body, bot, retries - 1)
            raise DiscordError(e.code, f"{method} {url.split('?')[0].rsplit('/', 2)[-2]}") from None
        except (urllib.error.URLError, OSError) as e:
            raise DiscordError(0, type(e).__name__) from None

    # ─── Webhook (no bot token) ──────────────────────────

    def webhook_post(self, webhook: str, body: Dict) -> Dict:
        """Posts and returns the message (``?wait=true``): its ``id`` and ``channel_id``."""
        return self._call("POST", f"{webhook}?wait=true", body, bot=False)

    def webhook_edit(self, webhook: str, message_id: str, body: Dict) -> None:
        self._call("PATCH", f"{webhook}/messages/{message_id}", body, bot=False)

    def webhook_info(self, webhook: str) -> Dict:
        return self._call("GET", webhook, bot=False)

    # ─── Bot ─────────────────────────────────────────────

    def me(self) -> Dict:
        return self._call("GET", f"{self.api}/users/@me")

    def react(self, channel_id: str, message_id: str, emoji: str) -> None:
        self._call("PUT", f"{self.api}/channels/{channel_id}/messages/{message_id}/reactions/{emoji_path(emoji)}/@me")

    def reactors(self, channel_id: str, message_id: str, emoji: str) -> List[str]:
        users = self._call(
            "GET", f"{self.api}/channels/{channel_id}/messages/{message_id}/reactions/{emoji_path(emoji)}?limit=100"
        )
        return [u["id"] for u in users or []]

    def messages_after(self, channel_id: str, after: str, limit: int = 50) -> List[Dict]:
        """Messages newer than ``after``, oldest first."""
        found = self._call("GET", f"{self.api}/channels/{channel_id}/messages?after={after}&limit={limit}") or []
        return sorted(found, key=lambda m: int(m["id"]))

    def latest_message_id(self, channel_id: str) -> Optional[str]:
        found = self._call("GET", f"{self.api}/channels/{channel_id}/messages?limit=1") or []
        return found[0]["id"] if found else None
