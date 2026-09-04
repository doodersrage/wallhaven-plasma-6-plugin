#!/usr/bin/env python3
"""Session D-Bus control, KRunner, MPRIS, and player API for Wallhaven wallpaper."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time

try:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import Gio, GLib
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
# Only realesrgan-ncnn-vulkan is driven directly (its "-i <in> -o <out> -n <model>"
# invocation is hardcoded below); other ncnn-vulkan-family tools take different
# flags/model names and are not wired up to avoid guessing at an untested CLI shape.
UPSCALER_BINARY = "realesrgan-ncnn-vulkan"
UPSCALER_MODEL = "realesrgan-x4plus"
UPSCALE_TIMEOUT_SEC = 120
BATTERY_CAPACITY_RE = re.compile(r"^/sys/class/power_supply/BAT\d+/capacity$")
HOME_READ_BLOCKED = (".ssh", ".gnupg", ".local/share/keyrings/")


def config_home() -> str:
    return os.path.realpath(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")))


VARIETY_CONFIG = os.path.join(config_home(), "variety", "variety.conf")


def normalize_local_path(path: str) -> str:
    """Accept plain paths or file:// URLs from QML StandardPaths / Image.source."""
    text = str(path or "").strip()
    if text.startswith("file://"):
        text = text[7:]
        # file:///home/... → /home/... ; keep leading slash
        if text.startswith("//"):
            text = text[1:]
    return text


def validate_cache_path(path: str) -> str:
    if not path:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: empty path")
    base = os.path.realpath(PLASMA_CACHE)
    full = os.path.realpath(normalize_local_path(path))
    if full == base or full.startswith(base + os.sep):
        return full
    raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: path outside cache")


def validate_read_path(path: str) -> str:
    if not path:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: empty path")
    full = os.path.realpath(normalize_local_path(path))
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


def find_upscaler() -> str:
    """Resolved path of the upscaler binary if it's installed, else ""."""
    return shutil.which(UPSCALER_BINARY) or ""


def _silent_remove(path: str) -> None:
    try:
        os.remove(path)
    except OSError:
        pass


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
        try:
            gfile = Gio.File.new_for_path(path)
            monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
            monitor.connect("changed", lambda *_a: on_change())
            # Keep a reference so the monitor is not GC'd.
            attach_config._monitors = getattr(attach_config, "_monitors", []) + [monitor]
        except GLib.Error:
            GLib.timeout_add_seconds(5, on_change)

    def attach_dbus_config(path: str) -> None:
        if not os.path.isfile(path):
            return

        def on_config_change(*_args) -> None:
            on_change()

        try:
            gfile = Gio.File.new_for_path(path)
            monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
            monitor.connect("changed", lambda *_a: on_config_change())
            attach_dbus_config._monitors = getattr(attach_dbus_config, "_monitors", []) + [monitor]
        except GLib.Error:
            GLib.timeout_add_seconds(5, on_config_change)

    attach_config(VARIETY_CONFIG)
    attach_dbus_config(DBUS_CONFIG_FILE)
    on_change()


def list_sync_groups() -> list[str]:
    """Unique sync groups from per-monitor status files (fallback: default)."""
    groups: list[str] = []
    try:
        for name in os.listdir(PLASMA_CACHE):
            if not name.startswith("wallhaven-status-") or not name.endswith(".json"):
                continue
            path = os.path.join(PLASMA_CACHE, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    data = json.load(handle)
            except (OSError, json.JSONDecodeError):
                continue
            group = str(data.get("syncGroup") or data.get("cacheNamespace") or "").strip()
            if group and group not in groups:
                groups.append(group)
    except OSError:
        pass
    if not groups:
        try:
            data = read_status()
            group = str(data.get("syncGroup") or data.get("cacheNamespace") or "").strip()
            if group:
                groups.append(group)
        except Exception:
            pass
    return groups or ["default"]


def write_command(cmd: str, group: str = "default", query: str = "") -> None:
    os.makedirs(os.path.dirname(CONTROL_FILE), exist_ok=True)
    payload: dict[str, object] = {"cmd": cmd, "ts": int(time.time() * 1000), "group": group}
    if query:
        payload["query"] = query
    with open(CONTROL_FILE, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


_NAV_FANOUT = {
    "next", "prev", "pause", "resume", "reload",
    "outageoffline", "resumeonline",
}


def write_command_fanout(cmd: str, group: str = "default", query: str = "") -> None:
    """Write one control command; fan-out nav cmds when group is the shared default."""
    target = group or "default"
    if cmd in _NAV_FANOUT and target == "default":
        groups = list_sync_groups()
        base = int(time.time() * 1000)
        commands = []
        for i, g in enumerate(groups):
            entry: dict[str, object] = {"cmd": cmd, "ts": base + i, "group": g}
            if query:
                entry["query"] = query
            commands.append(entry)
        os.makedirs(os.path.dirname(CONTROL_FILE), exist_ok=True)
        with open(CONTROL_FILE, "w", encoding="utf-8") as handle:
            json.dump({"commands": commands}, handle)
        return
    write_command(cmd, target, query)


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


def metadata_from(status: dict) -> dbus.Dictionary:
    wall_id = re.sub(r"[^A-Za-z0-9_]", "_", str(status.get("id") or "current")) or "current"
    return dbus.Dictionary(
        {
            "mpris:trackid": dbus.ObjectPath(f"/org/mpris/MediaPlayer2/wallhaven/track/{wall_id}"),
            "xesam:title": dbus.String(f"Wallhaven #{wall_id}"),
            "xesam:url": dbus.String(str(status.get("pageUrl") or "")),
            "mpris:artUrl": dbus.String(str(status.get("thumbUrl") or "")),
        },
        signature="sv",
    )


def list_image_files_under(folder: str, options_json: str = "") -> str:
    """List image files under a home-relative folder. Returns JSON array of paths."""
    raw = os.path.expanduser(str(folder or "").strip())
    if not raw:
        return "[]"
    home = os.path.expanduser("~")
    target = os.path.realpath(raw)
    if not (target == home or target.startswith(home + os.sep)):
        raise dbus.exceptions.DBusException(
            "org.freedesktop.DBus.Error.InvalidArgs: folder must be under home",
        )
    if not os.path.isdir(target):
        return "[]"
    max_depth = 3
    excludes: list[str] = []
    try:
        opts = json.loads(options_json or "{}") if options_json else {}
        if isinstance(opts, dict):
            if opts.get("maxDepth") is not None:
                max_depth = max(0, min(8, int(opts["maxDepth"])))
            raw_ex = opts.get("exclude", "")
            if isinstance(raw_ex, list):
                excludes = [str(x).strip().lower() for x in raw_ex if str(x).strip()]
            else:
                excludes = [
                    part.strip().lower()
                    for part in str(raw_ex).replace(";", ",").split(",")
                    if part.strip()
                ]
    except (TypeError, ValueError, json.JSONDecodeError):
        max_depth = 3
        excludes = []
    exts = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
    found: list[str] = []
    for root, dirs, files in os.walk(target):
        rel = os.path.relpath(root, target)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        if depth > max_depth:
            dirs[:] = []
            continue
        # Do not descend past max_depth.
        if depth >= max_depth:
            dirs[:] = []
        for name in files:
            path = os.path.join(root, name)
            lower = path.lower()
            if any(token in lower for token in excludes):
                continue
            ext = os.path.splitext(name)[1].lower()
            if ext in exts:
                found.append(path)
                if len(found) >= 400:
                    return json.dumps(found)
    return json.dumps(found)


class WallhavenControl(dbus.service.Object):
    def __init__(self, bus, group: str) -> None:
        self.group = group
        super().__init__(bus, OBJECT_PATH)

    @dbus.service.method(INTERFACE, out_signature="s")
    def Ping(self) -> str:
        return "ok"

    @dbus.service.method(INTERFACE, out_signature="s")
    def GetStatus(self) -> str:
        """Return wallhaven-status.json contents (typed status bus helper for 3.0)."""
        try:
            with open(STATUS_FILE, encoding="utf-8") as handle:
                return handle.read()
        except OSError:
            return "{}"

    @dbus.service.method(INTERFACE, out_signature="s")
    def GetPluginVersion(self) -> str:
        return "3.4.1"

    @dbus.service.method(INTERFACE, out_signature="s")
    def ListMonitorStatuses(self) -> str:
        """Return JSON array of per-monitor status snapshots (wallhaven-status-*.json)."""
        out: list[dict] = []
        try:
            for name in sorted(os.listdir(PLASMA_CACHE)):
                if not (name.startswith("wallhaven-status-") and name.endswith(".json")):
                    continue
                if name == "wallhaven-status.json":
                    continue
                path = os.path.join(PLASMA_CACHE, name)
                try:
                    with open(path, encoding="utf-8") as handle:
                        data = json.loads(handle.read() or "{}")
                    if isinstance(data, dict):
                        data["_statusFile"] = name
                        out.append(data)
                except (OSError, json.JSONDecodeError):
                    continue
        except OSError:
            return "[]"
        return json.dumps(out)

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="s")
    def ListImageFiles(self, folder: str, options_json: str = "") -> str:
        """List image files under a user folder (JSON array of absolute paths).

        options_json may include maxDepth (int) and exclude (comma-separated substrings).
        """
        return list_image_files_under(folder, options_json)

    @dbus.service.method(INTERFACE, in_signature="s")
    def Command(self, cmd: str) -> None:
        write_command_fanout(cmd, self.group)

    @dbus.service.method(INTERFACE, in_signature="ss")
    def CommandInGroup(self, cmd: str, group: str) -> None:
        write_command_fanout(cmd, group or self.group)

    @dbus.service.method(INTERFACE, in_signature="ss")
    def Search(self, query: str, group: str = "") -> None:
        # Never fan-out searches — that overwrote every monitor's query.
        write_command("search", group or self.group, query)

    @dbus.service.method(INTERFACE, in_signature="sss")
    def CommandWithQuery(self, cmd: str, query: str, group: str = "") -> None:
        if cmd in _NAV_FANOUT:
            write_command_fanout(cmd, group or self.group, query)
        else:
            write_command(cmd, group or self.group, query)

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="s")
    def WriteTextFile(self, path: str, content: str) -> str:
        log_path = os.path.join(PLASMA_CACHE, "wallhaven-dbus-write.log")
        try:
            target = validate_cache_path(path)
        except dbus.exceptions.DBusException as exc:
            try:
                with open(log_path, "a", encoding="utf-8") as handle:
                    handle.write(f"REJECT {path!r} err={exc}\n")
            except OSError:
                pass
            raise
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(content)
        try:
            with open(log_path, "a", encoding="utf-8") as handle:
                handle.write(f"OK {target} bytes={len(content or '')}\n")
        except OSError:
            pass
        return "ok"

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="s")
    def PublishStatusJson(self, content: str) -> str:
        """Write status JSON to the plasmashell cache (no client-supplied path)."""
        return self.WriteTextFile(STATUS_FILE, content or "{}")

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="s")
    def PublishMonitorStatusJson(self, namespace: str, content: str) -> str:
        """Write per-monitor status JSON under the plasmashell cache."""
        safe = re.sub(r"[^A-Za-z0-9._-]+", "_", str(namespace or "default"))[:80] or "default"
        target = os.path.join(PLASMA_CACHE, f"wallhaven-status-{safe}.json")
        return self.WriteTextFile(target, content or "{}")

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="s")
    def ReadTextFile(self, path: str) -> str:
        target = validate_read_path(path)
        try:
            with open(target, encoding="utf-8") as handle:
                return handle.read()
        except OSError:
            return ""

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="s")
    def AppendTextFile(self, path: str, line: str) -> str:
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
        return "ok"

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="s")
    def RunArgv(self, argv_json: str) -> str:
        try:
            argv = json.loads(argv_json)
        except json.JSONDecodeError as exc:
            raise dbus.exceptions.DBusException(
                f"org.freedesktop.DBus.Error.InvalidArgs: invalid argv json: {exc}",
            ) from exc
        if not isinstance(argv, list):
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: argv must be a list")
        run_argv([str(part) for part in argv])
        return "ok"

    @dbus.service.method(INTERFACE, out_signature="s")
    def UpscalerAvailable(self) -> str:
        """Resolved path of the external upscaler binary, or "" if not installed."""
        return find_upscaler()

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="b")
    def Upscale(self, input_path: str, output_path: str) -> bool:
        """Run the external upscaler on input_path, writing to output_path.

        input_path and output_path may be the same file: the upscaled result
        is written to a sibling temp file first and only swapped into place
        with os.replace() on success, so a same-path in-place "upscale this
        cached wallpaper" call never truncates the source before it's read
        and never leaves a half-written file behind on failure.

        Both paths must live under the plasmashell cache dir (same rule as
        WriteTextFile/AppendTextFile). Returns False -- never raises -- when
        the tool isn't installed, times out, or fails, so QML callers can
        treat any falsy result as "fall back to plain scaling".
        """
        binary = find_upscaler()
        if not binary:
            return False
        try:
            src = validate_cache_path(input_path)
            dst = validate_cache_path(output_path)
        except dbus.exceptions.DBusException:
            return False
        if not os.path.isfile(src):
            return False
        tmp_dst = dst + ".upscale.tmp"
        try:
            result = subprocess.run(
                [binary, "-i", src, "-o", tmp_dst, "-n", UPSCALER_MODEL],
                check=False,
                capture_output=True,
                timeout=UPSCALE_TIMEOUT_SEC,
            )
        except (OSError, subprocess.TimeoutExpired, subprocess.SubprocessError):
            _silent_remove(tmp_dst)
            return False
        if result.returncode != 0 or not os.path.isfile(tmp_dst):
            _silent_remove(tmp_dst)
            return False
        try:
            os.replace(tmp_dst, dst)
        except OSError:
            _silent_remove(tmp_dst)
            return False
        return True


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

    def _root_props(self) -> dict[str, object]:
        return {
            "CanQuit": False,
            "CanRaise": False,
            "HasTrackList": False,
            "Identity": "Wallhaven",
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        }

    def _player_props(self) -> dict[str, object]:
        status = self._status
        return {
            "PlaybackStatus": playback_status_from(status),
            "Metadata": metadata_from(status),
            "CanGoNext": True,
            "CanGoPrevious": True,
            "CanPlay": True,
            "CanPause": True,
            "CanSeek": False,
            "CanControl": True,
        }

    def _props_for(self, interface_name: str) -> dict[str, object]:
        if interface_name == MPRIS_IFACE:
            return self._root_props()
        if interface_name == MPRIS_PLAYER_IFACE:
            return self._player_props()
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownInterface")

    @dbus.service.method(PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface_name: str, property_name: str):  # noqa: N802
        props = self._props_for(interface_name)
        if property_name not in props:
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.UnknownProperty")
        return props[property_name]

    @dbus.service.method(PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name: str):  # noqa: N802
        return dbus.Dictionary(self._props_for(interface_name), signature="sv")

    def refresh_status(self, force: bool = False) -> None:
        status = read_status()
        key = status_signature(status)
        if not force and key == self._status_key:
            return
        self._status = status
        self._status_key = key
        self.PropertiesChanged(
            MPRIS_PLAYER_IFACE,
            dbus.Dictionary(
                {
                    "Metadata": metadata_from(status),
                    "PlaybackStatus": playback_status_from(status),
                },
                signature="sv",
            ),
            dbus.Array([], signature="s"),
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
    """Watch wallhaven-status.json and refresh MPRIS metadata when it changes."""
    monitors: list = []

    def emit_if_changed(*_args) -> None:
        mpris.refresh_status()

    def attach(path: str) -> bool:
        if not os.path.isfile(path):
            return False
        try:
            gfile = Gio.File.new_for_path(path)
            monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
            monitor.connect("changed", lambda *_a: emit_if_changed())
            monitors.append(monitor)
            mpris.refresh_status(force=True)
            return True
        except GLib.Error as exc:
            print(f"status file monitor failed for {path}: {exc}", flush=True)
            # Fall back to polling so MPRIS still updates.
            GLib.timeout_add_seconds(2, lambda: (mpris.refresh_status(), True)[1])
            mpris.refresh_status(force=True)
            return True

    if attach(STATUS_FILE):
        return

    def wait_for_file() -> bool:
        return not attach(STATUS_FILE)

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
        "pin", "unpin", "copyid", "copyurl", "warm", "prune", "endtrip", "undo", "clearkey", "testkey",
        "info",
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
    if len(sys.argv) > 2 and sys.argv[1] in {
        "history", "applysearch", "savesearch", "purity", "trip", "warm",
    }:
        write_command(sys.argv[1], group, " ".join(sys.argv[2:]))
        print(f"Sent '{sys.argv[1]}' via control bus")
        return 0

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    WallhavenControl(bus, group)
    WallhavenRunner(bus, group)
    WallhavenPlayer(bus, group)
    mpris = MprisMediaPlayer2(bus, group)
    # BusName releases the well-known name when the object is unreferenced.
    # Constructing them as temporaries dropped org.robertsm.Wallhaven while
    # systemd still reported the unit active. Export objects first so clients
    # that race the name claim do not hit a half-ready service.
    well_known = [
        dbus.service.BusName(SERVICE, bus, do_not_queue=True),
        dbus.service.BusName(MPRIS_SERVICE, bus, do_not_queue=True),
    ]
    if not bus.name_has_owner(SERVICE):
        print(f"Failed to claim {SERVICE} on the session bus", file=sys.stderr)
        return 1
    watch_status_file(mpris)
    watch_variety_config(group)
    GLib.timeout_add_seconds(2, lambda: mpris.refresh_status() or True)
    print(f"D-Bus services {SERVICE}, {MPRIS_SERVICE}", flush=True)
    try:
        GLib.MainLoop().run()
    finally:
        del well_known
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
