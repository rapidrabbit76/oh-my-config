"""What an alert is, apart from who sends it and where it goes."""

from __future__ import annotations

from dataclasses import dataclass

TITLE_MAX = 200
BODY_MAX = 1000


@dataclass(frozen=True)
class Kind:
    icon: str
    color: int  # Discord embed color
    tag: str  # ntfy tag (an emoji short code)
    priority: int  # ntfy priority, 1-5


KINDS = {
    "done": Kind("✅", 0x57F287, "white_check_mark", 3),
    "wait": Kind("⏸️", 0xFEE75C, "hourglass_flowing_sand", 4),
    "error": Kind("❌", 0xED4245, "x", 4),
    "info": Kind("🔔", 0x5865F2, "bell", 3),
}


def clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


@dataclass(frozen=True)
class Alert:
    agent: str  # an Agent's key
    kind: str  # a key of KINDS
    title: str
    body: str = ""
    meta: str = ""  # one line under the body: folder, branch, how long

    def __post_init__(self) -> None:
        object.__setattr__(self, "kind", self.kind if self.kind in KINDS else "info")
        object.__setattr__(self, "title", clip(self.title.strip(), TITLE_MAX))
        object.__setattr__(self, "body", clip(self.body.strip(), BODY_MAX))

    @property
    def style(self) -> Kind:
        return KINDS[self.kind]
