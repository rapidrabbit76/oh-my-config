"""Small things agents share."""

from __future__ import annotations

import os
import subprocess


def branch_of(folder: str) -> str:
    try:
        ran = subprocess.run(
            ["git", "-C", folder, "--no-optional-locks", "symbolic-ref", "--short", "-q", "HEAD"],
            capture_output=True,
            text=True,
            timeout=3,
        )
        return ran.stdout.strip() if ran.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def where(folder: str) -> str:
    """``folder · branch``, for an alert's meta line."""
    if not folder:
        return ""
    name = os.path.basename(folder.rstrip("/")) or folder
    branch = branch_of(folder)
    return f"{name} · {branch}" if branch else name


def took(seconds: float) -> str:
    s = max(0, int(seconds))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m {s % 60}s"
    return f"{s // 3600}h {s % 3600 // 60}m"


def meta(*parts: str) -> str:
    return " · ".join(p for p in parts if p)
