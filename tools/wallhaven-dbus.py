#!/usr/bin/env python3
"""Session D-Bus control, KRunner, MPRIS, and player API for Wallhaven wallpaper."""

from __future__ import annotations

import json
import os
import re
import subprocess
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
DBUS_CONFIG_FILE = os.path.join(PLASMA_CACHE, "wallhaven-dbus-config.json")
ALLOWED_COMMANDS = {
    "python3",
    "bash",
    "rm",
    "cp",
    "kwallet-query",
    "plasma-apply-colors",
    "kwriteconfig6",
}
BATTERY_CAPACITY_RE = re.compile(r"^/sys/class/power_supply/BAT\d+/capacity$")
HOME_READ_BLOCKED = (".ssh", ".gnupg", ".local/share/keyrings/")


def config_home() -> str:
    return os.path.realpath(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))


VARIETY_CONFIG = os.path.join(config_home(), "variety", "variety.conf")


def validate_cache_path(path: str) -> str:
    if not path:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: empty path")
    base = os.path.realpath(PLASMA_CACHE)
    full = os.path.realpath(path)
    if full == base or full.startswith(base + os.sep):
        return full
    raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: path outside cache")


def validate_read_path(path: str) -> str:
    if not path:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: empty path")
    full = os.path.realpath(path)
    cache_base = os.path.realpath(PLASMA_CACHE)
    if full == cache_base or full.startswith(cache_base + os.sep):
        return full
    if BATTERY_CAPACITY_RE.match(full):
        return full
    cfg_base = config_home()
    if full.startswith(cfg_base + os.sep):
        return full
    home = os.path.realpath(os.path.expanduser("~"))
    if full == home or full.startswith(home + os.sep):
        rel = os.path.relpath(full, home)
        if rel != ".." and not rel.startswith(".." + os.sep):
            for blocked in HOME_READ_BLOCKED:
                if rel == blocked.rstrip("/") or rel.startswith(blocked):
                    raise dbus.exceptions.DBusException(
                        "org.freedesktop.DBus.Error.AccessDenied: path not readable",
                    )
            return full
    raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: path not readable")


def append_debug_log_line(existing: str, line: str, max_lines: int = 200) -> str:
    lines = [entry for entry in str(existing or "").split("\n") if entry]
    lines.append(str(line or ""))
    if len(lines) > max_lines:
        lines = lines[-max_lines:]
    return "\n".join(lines) + "\n"


def run_argv(argv: list[str]) -> None:
    if not argv:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: empty argv")
    program = os.path.basename(str(argv[0]))
    if program not in ALLOWED_COMMANDS:
        raise dbus.exceptions.DBusException(
            f"org.freedesktop.DBus.Error.AccessDenied: command not allowed: {program}",
        )
    subprocess.run(argv, check=False)


def parse_variety_search(ini_text: str) -> str:
    if not ini_text:
        return ""
    in_prefs = False
    for line in str(ini_text).split("\n"):
        stripped = line.strip()
        if stripped == "[preferences]":
            in_prefs = True
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            in_prefs = False
            continue
        if in_prefs and stripped.startswith("image_fetch_search"):
            parts = stripped.split("=", 1)
            if len(parts) > 1:
                return parts[1].strip()
    return ""


def read_dbus_config() -> dict:
    try:
        with open(DBUS_CONFIG_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
            return data if isinstance(data, dict) else {}
    except OSError:
        return {}


def variety_watch_enabled() -> bool:
    return bool(read_dbus_config().get("varietyWatchEnabled"))


def variety_watch_group() -> str:
    group = read_dbus_config().get("syncGroup")
    return str(group) if group else "default"


def apply_variety_search() -> None:
    if not variety_watch_enabled():
        return
    try:
        with open(VARIETY_CONFIG, encoding="utf-8") as handle:
            search = parse_variety_search(handle.read())
    except OSError:
        return
    if search:
        write_command("search", variety_watch_group(), search)


def watch_variety_config(group: str) -> None:
    last_search = {"value": ""}

    def on_change(*_args) -> bool:
        if not variety_watch_enabled():
            return True
        try:
            with open(VARIETY_CONFIG, encoding="utf-8") as handle:
                search = parse_variety_search(handle.read())
        except OSError:
            return True
        if search and search != last_search["value"]:
            last_search["value"] = search
            write_command("search", variety_watch_group() or group, search)
        return True

    def attach_config(path: str) -> None:
        if not os.path.isfile(path):
            return
        GLib.io_add_watch(path, GLib.IOCondition.IN_MODIFY, on_change)

    def attach_dbus_config(path: str) -> None:
        if not os.path.isfile(path):
            return

        def on_config_change(*_args) -> bool:
            on_change()
            return True

        GLib.io_add_watch(path, GLib.IOCondition.IN_MODIFY, on_config_change)

    attach_config(VARIETY_CONFIG)
    attach_dbus_config(DBUS_CONFIG_FILE)
    on_change()


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

    @dbus.service.method(INTERFACE, in_signature="sss")
    def CommandWithQuery(self, cmd: str, query: str, group: str = "") -> None:
        write_command(cmd, group or self.group, query)

    @dbus.service.method(INTERFACE, in_signature="ss")
    def WriteTextFile(self, path: str, content: str) -> None:
        target = validate_cache_path(path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(content)

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="s")
    def ReadTextFile(self, path: str) -> str:
        target = validate_read_path(path)
        try:
            with open(target, encoding="utf-8") as handle:
                return handle.read()
        except OSError:
            return ""

    @dbus.service.method(INTERFACE, in_signature="ss")
    def AppendTextFile(self, path: str, line: str) -> None:
        target = validate_cache_path(path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        existing = ""
        try:
            with open(target, encoding="utf-8") as handle:
                existing = handle.read()
        except OSError:
            pass
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(append_debug_log_line(existing, line))

    @dbus.service.method(INTERFACE, in_signature="s")
    def RunArgv(self, argv_json: str) -> None:
        try:
            argv = json.loads(argv_json)
        except json.JSONDecodeError as exc:
            raise dbus.exceptions.DBusException(
                f"org.freedesktop.DBus.Error.InvalidArgs: invalid argv json: {exc}",
            ) from exc
        if not isinstance(argv, list):
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: argv must be a list")
        run_argv([str(part) for part in argv])


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

    def _mpris_props(self) -> dict[str, object]:
        status = self._status
        return {
            "CanQuit": False,
            "CanRaise": False,
            "HasTrackList": False,
            "Identity": "Wallhaven",
            "PlaybackStatus": playback_status_from(status),
            "Metadata": metadata_from(status),
        }

    @dbus.service.method(PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface_name: str, property_name: str):  # noqa: N802
        if interface_name != MPRIS_IFACE:
            raise dbus.exceptions.DBusException(
                f"org.freedesktop.DBus.Error.UnknownInterface: {interface_name}",
            )
        props = self._mpris_props()
        if property_name not in props:
            raise dbus.exceptions.DBusException(
                f"org.freedesktop.DBus.Error.UnknownProperty: {property_name}",
            )
        return props[property_name]

    @dbus.service.method(PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name: str):  # noqa: N802
        if interface_name != MPRIS_IFACE:
            raise dbus.exceptions.DBusException(
                f"org.freedesktop.DBus.Error.UnknownInterface: {interface_name}",
            )
        return self._mpris_props()

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
        if re.match(r"^(wh|wallhaven)\s*like$", lowered):
            add("wh-like", "Like current wallpaper", "Boost its tags", 0.88)
        if re.match(r"^(wh|wallhaven)\s*dislike$", lowered):
            add("wh-dislike", "Dislike current wallpaper", "Mute its tags", 0.88)
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
        elif match_id == "wh-like":
            write_command("like", self.group)
        elif match_id == "wh-dislike":
            write_command("dislike", self.group)
        elif match_id == "wh-copytags":
            write_command("copytags", self.group)
        elif match_id.startswith("wh-search:"):
            term = match_id.split(":", 1)[1]
            write_command("search", self.group, term)


def main() -> int:
    group = os.environ.get("WALLHAVEN_SYNC_GROUP", "default")
    if len(sys.argv) > 1 and sys.argv[1] in {
        "next", "prev", "reload", "pause", "resume", "open", "block", "copytags", "like", "dislike",
    }:
        write_command(sys.argv[1], group)
        print(f"Sent '{sys.argv[1]}' via control bus")
        return 0
    if len(sys.argv) > 2 and sys.argv[1] == "search":
        write_command("search", group, " ".join(sys.argv[2:]))
        print("Sent search via control bus")
        return 0
    if len(sys.argv) > 2 and sys.argv[1] == "importpreset":
        write_command("importpreset", group, sys.argv[2])
        print("Sent preset import via control bus")
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
    watch_variety_config(group)
    GLib.timeout_add_seconds(2, lambda: mpris.refresh_status() or True)
    print(f"D-Bus services {SERVICE}, {MPRIS_SERVICE}")
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
