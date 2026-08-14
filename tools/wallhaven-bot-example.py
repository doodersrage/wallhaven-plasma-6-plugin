#!/usr/bin/env python3
"""Example automation hook for Wallhaven wallpaper control.

Polls the status JSON and posts to a webhook when the wallpaper changes.
Configure WEBHOOK_URL to enable; otherwise prints status lines locally.
"""

from __future__ import annotations

import json
import os
import time
import urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "plasmashell")
STATUS_FILE = os.path.join(CACHE, "wallhaven-status.json")
WEBHOOK_URL = os.environ.get("WALLHAVEN_WEBHOOK_URL", "")


def read_status() -> dict:
    try:
        with open(STATUS_FILE, encoding="utf-8") as handle:
            return json.load(handle)
    except OSError:
        return {}


def notify(payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    if WEBHOOK_URL:
        req = urllib.request.Request(
            WEBHOOK_URL,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10):
            pass
    else:
        print(json.dumps(payload))


def main() -> int:
    last_id = ""
    while True:
        status = read_status()
        current_id = str(status.get("id", ""))
        if current_id and current_id != last_id:
            notify({
                "event": "wallpaper_changed",
                "id": current_id,
                "thumbUrl": status.get("thumbUrl", ""),
                "attribution": status.get("attribution", ""),
            })
            last_id = current_id
        time.sleep(5)


if __name__ == "__main__":
    raise SystemExit(main())
