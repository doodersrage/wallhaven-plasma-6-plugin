#!/usr/bin/env python3
"""Session D-Bus control, KRunner, MPRIS, and player API for Wallhaven wallpaper."""

from __future__ import annotations

import json
import os
import re
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
MPRIS_SERVICE = "org.mpris.MediaPlayer2.wallhaven"
OBJECT_PATH = "/Wallhaven"
RUNNER_PATH = "/runner"
PLAYER_PATH = "/Player"
MPRIS_PATH = "/org/mpris/MediaPlayer2"
INTERFACE = "org.robertsm.Wallhaven"
RUNNER_IFACE = "org.kde.krunner1"
PLAYER_IFACE = "org.robertsm.Wallhaven.Player"
MPRIS_IFACE = "org.mpris.MediaPlayer2"
MPRIS_PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"

CACHE = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
PLASMA_CACHE = os.path.join(CACHE, "plasmashell")
CONTROL_FILE = os.path.join(PLASMA_CACHE, "wallhaven-control.json")
STATUS_FILE = os.path.join(PLASMA_CACHE, "wallhaven-status.json")


def write_command(cmd: str, group: str = "default", query: str = "") -> None:
    os.makedirs(os.path.dirname(CONTROL_FILE), exist_ok=True)
    payload: dict[str, object] = {"cmd": cmd, "ts": int(time.time() * 1000), "group": group}
    if query:
        payload["query"] = query
    with open(CONTROL_FILE, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


def read_status() -> dict:
    try:
        with open(STATUS_FILE, encoding="utf-8") as handle:
            return json.load(handle)
    except OSError:
        return {}


def status_signature(status: dict) -> str:
    return json.dumps(
        {
            "id": status.get("id"),
            "paused": status.get("paused"),
            "slideshowActive": status.get("slideshowActive"),
            "pageUrl": status.get("pageUrl"),
            "thumbUrl": status.get("thumbUrl"),
        },
        sort_keys=True,
    )


def playback_status_from(status: dict) -> str:
    if status.get("paused"):
        return "Paused"
    if status.get("slideshowActive"):
        return "Playing"
    return "Stopped"


def metadata_from(status: dict) -> dict[str, dbus.Object]:
    wall_id = str(status.get("id") or "current")
    return {
        "mpris:trackid": dbus.ObjectPath(f"/org/mpris/MediaPlayer2/wallhaven/track/{wall_id}"),
        "xesam:title": dbus.String(f"Wallhaven #{wall_id}"),
        "xesam:url": dbus.String(str(status.get("pageUrl") or "")),
        "mpris:artUrl": dbus.String(str(status.get("thumbUrl") or "")),
    }


class WallhavenControl(dbus.service.Object):
    def __init__(self, bus, group: str) -> None:
        self.group = group
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method(INTERFACE, in_signature="s")
    def Command(self, cmd: str) -> None:
        write_command(cmd, self.group)

    @dbus.service.method(INTERFACE, in_signature="ss")
    def CommandInGroup(self, cmd: str, group: str) -> None:
        write_command(cmd, group or self.group)

    @dbus.service.method(INTERFACE, in_signature="ss")
    def Search(self, query: str, group: str = "") -> None:
        write_command("search", group or self.group, query)


class WallhavenPlayer(dbus.service.Object):
    def __init__(self, bus, group: str) -> None:
        self.group = group
        super().__init__(bus, PLAYER_PATH)

    @dbus.service.method(PLAYER_IFACE)
    def Next(self) -> None:
        write_command("next", self.group)

    @dbus.service.method(PLAYER_IFACE)
    def Previous(self) -> None:
        write_command("prev", self.group)

    @dbus.service.method(PLAYER_IFACE)
    def PlayPause(self) -> None:
        status = read_status()
        cmd = "resume" if status.get("paused") else "pause"
        write_command(cmd, self.group)

    @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="s")
    def Metadata(self) -> str:
        return json.dumps(read_status())

    @dbus.service.method(PLAYER_IFACE, in_signature="", out_signature="s")
    def PlaybackStatus(self) -> str:
        status = read_status()
        if status.get("paused"):
            return "Paused"
        if status.get("slideshowActive"):
            return "Playing"
        return "Stopped"


class MprisMediaPlayer2(dbus.service.Object):
    def __init__(self, bus, group: str) -> None:
        self.group = group
        self._status: dict = read_status()
        self._status_key = status_signature(self._status)
        super().__init__(bus, MPRIS_PATH)

    def refresh_status(self, force: bool = False) -> None:
        status = read_status()
        key = status_signature(status)
        if not force and key == self._status_key:
            return
        self._status = status
        self._status_key = key
        self.PropertiesChanged(
            MPRIS_IFACE,
            {
                "Metadata": metadata_from(status),
                "PlaybackStatus": playback_status_from(status),
            },
            [],
        )

    @dbus.service.signal(PROPERTIES_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):  # noqa: N802
        pass

    @dbus.service.method(MPRIS_IFACE, in_signature="", out_signature="")
    def Raise(self) -> None:
        pass

    @dbus.service.method(MPRIS_IFACE, in_signature="", out_signature="")
    def Quit(self) -> None:
        pass

    @dbus.service.property(MPRIS_IFACE, "b")
    def CanQuit(self) -> bool:
        return False

    @dbus.service.property(MPRIS_IFACE, "b")
    def CanRaise(self) -> bool:
        return False

    @dbus.service.property(MPRIS_IFACE, "b")
    def HasTrackList(self) -> bool:
        return False

    @dbus.service.property(MPRIS_IFACE, "s")
    def Identity(self) -> str:
        return "Wallhaven"

    @dbus.service.property(MPRIS_IFACE, "s", emit_change_signal=True)
    def PlaybackStatus(self) -> str:
        return playback_status_from(self._status)

    @dbus.service.property(MPRIS_IFACE, "a{sv}", emit_change_signal=True)
    def Metadata(self) -> dict[str, dbus.Object]:
        return metadata_from(self._status)

    @dbus.service.method(MPRIS_PLAYER_IFACE)
    def Next(self) -> None:
        write_command("next", self.group)

    @dbus.service.method(MPRIS_PLAYER_IFACE)
    def Previous(self) -> None:
        write_command("prev", self.group)

    @dbus.service.method(MPRIS_PLAYER_IFACE)
    def PlayPause(self) -> None:
        status = read_status()
        write_command("resume" if status.get("paused") else "pause", self.group)

    @dbus.service.method(MPRIS_PLAYER_IFACE)
    def Stop(self) -> None:
        write_command("pause", self.group)


def watch_status_file(mpris: MprisMediaPlayer2) -> None:
    def emit_if_changed(*_args) -> bool:
        mpris.refresh_status()
        return True

    def attach(path: str) -> None:
        if not os.path.isfile(path):
            return
        GLib.io_add_watch(path, GLib.IOCondition.IN_MODIFY, emit_if_changed)
        mpris.refresh_status(force=True)

    if os.path.isfile(STATUS_FILE):
        attach(STATUS_FILE)
        return

    def wait_for_file() -> bool:
        if os.path.isfile(STATUS_FILE):
            attach(STATUS_FILE)
            return False
        return True

    GLib.timeout_add_seconds(1, wait_for_file)


class WallhavenRunner(dbus.service.Object):
    def __init__(self, bus, group: str) -> None:
        self.group = group
        super().__init__(bus, RUNNER_PATH)

    @dbus.service.method(RUNNER_IFACE, in_signature="s", out_signature="a(sssida{sv})")
    def Match(self, query: str) -> list[tuple[str, str, str, float, str, dict]]:
        query = query.strip()
        lowered = query.lower()
        matches: list[tuple[str, str, str, float, str, dict]] = []

        def add(match_id: str, text: str, subtext: str, relevance: float) -> None:
            matches.append((match_id, text, "preferences-desktop-wallpaper", relevance, subtext, {}))

        if re.match(r"^(wh|wallhaven)\s*(next)?$", lowered):
            add("wh-next", "Next Wallhaven wallpaper", "Advance slideshow", 1.0)
        if re.match(r"^(wh|wallhaven)\s*(prev|previous)$", lowered):
            add("wh-prev", "Previous Wallhaven wallpaper", "Go back in history", 1.0)
        if re.match(r"^(wh|wallhaven)\s*(pause|resume|toggle)$", lowered):
            add("wh-pause", "Pause/resume Wallhaven slideshow", "Toggle pause state", 0.95)
        if re.match(r"^(wh|wallhaven)\s*(reload|refresh)$", lowered):
            add("wh-reload", "Reload Wallhaven wallpaper", "Reset slideshow", 0.95)
        if re.match(r"^(wh|wallhaven)\s*(open|browser)$", lowered):
            add("wh-open", "Open current wallpaper in browser", "Wallhaven page", 0.9)
        if re.match(r"^(wh|wallhaven)\s*block$", lowered):
            add("wh-block", "Block current wallpaper", "Skip in future searches", 0.9)
        if re.match(r"^(wh|wallhaven)\s*(tags|copy tags)$", lowered):
            add("wh-copytags", "Copy current wallpaper tags", "Clipboard", 0.88)
        search = re.match(r"^(?:wh|wallhaven)\s+search\s+(.+)$", lowered)
        if search:
            term = query.split(None, 2)[-1] if len(query.split()) >= 3 else search.group(1)
            add(f"wh-search:{term}", f"Search Wallhaven: {term}", "Apply search query", 0.9)
        return matches

    @dbus.service.method(RUNNER_IFACE, in_signature="ss")
    def Run(self, match_id: str, _action_id: str) -> None:
        if match_id == "wh-next":
            write_command("next", self.group)
        elif match_id == "wh-prev":
            write_command("prev", self.group)
        elif match_id == "wh-pause":
            status = read_status()
            write_command("resume" if status.get("paused") else "pause", self.group)
        elif match_id == "wh-reload":
            write_command("reload", self.group)
        elif match_id == "wh-open":
            write_command("open", self.group)
        elif match_id == "wh-block":
            write_command("block", self.group)
        elif match_id == "wh-copytags":
            write_command("copytags", self.group)
        elif match_id.startswith("wh-search:"):
            term = match_id.split(":", 1)[1]
            write_command("search", self.group, term)


def main() -> int:
    group = os.environ.get("WALLHAVEN_SYNC_GROUP", "default")
    if len(sys.argv) > 1 and sys.argv[1] in {"next", "prev", "reload", "pause", "resume", "open", "block", "copytags"}:
        write_command(sys.argv[1], group)
        print(f"Sent '{sys.argv[1]}' via control bus")
        return 0
    if len(sys.argv) > 2 and sys.argv[1] == "search":
        write_command("search", group, " ".join(sys.argv[2:]))
        print("Sent search via control bus")
        return 0

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    dbus.service.BusName(SERVICE, bus)
    dbus.service.BusName(MPRIS_SERVICE, bus)
    WallhavenControl(bus, group)
    WallhavenRunner(bus, group)
    WallhavenPlayer(bus, group)
    mpris = MprisMediaPlayer2(bus, group)
    watch_status_file(mpris)
    GLib.timeout_add_seconds(2, lambda: mpris.refresh_status() or True)
    print(f"D-Bus services {SERVICE}, {MPRIS_SERVICE}")
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
