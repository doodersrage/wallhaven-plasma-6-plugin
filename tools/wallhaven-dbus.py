#!/usr/bin/env python3
"""Session D-Bus control for Wallhaven wallpaper plugin."""

from __future__ import annotations

import json
import os
import sys
import time

try:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
except ImportError as exc:  # pragma: no cover
    print("Requires python3-dbus and python3-gi:", exc, file=sys.stderr)
    sys.exit(1)

SERVICE = "org.robertsm.Wallhaven"
OBJECT_PATH = "/Wallhaven"
INTERFACE = "org.robertsm.Wallhaven"

CACHE = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
CONTROL_FILE = os.path.join(CACHE, "plasmashell", "wallhaven-control.json")


def write_command(cmd: str, group: str = "default") -> None:
    os.makedirs(os.path.dirname(CONTROL_FILE), exist_ok=True)
    payload = {"cmd": cmd, "ts": int(time.time() * 1000), "group": group}
    with open(CONTROL_FILE, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


class WallhavenService(dbus.service.Object):
    def __init__(self, bus, group: str) -> None:
        self.group = group
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method(INTERFACE, in_signature="s")
    def Command(self, cmd: str) -> None:
        write_command(cmd, self.group)

    @dbus.service.method(INTERFACE, in_signature="ss")
    def CommandInGroup(self, cmd: str, group: str) -> None:
        write_command(cmd, group or self.group)


def main() -> int:
    group = os.environ.get("WALLHAVEN_SYNC_GROUP", "default")
    if len(sys.argv) > 1 and sys.argv[1] in {"next", "prev", "reload", "pause", "resume"}:
        write_command(sys.argv[1], group)
        print(f"Sent '{sys.argv[1]}' via control bus")
        return 0

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(SERVICE, bus)
    WallhavenService(bus, group)
    print(f"D-Bus service {SERVICE} on {OBJECT_PATH} (group={group})")
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
