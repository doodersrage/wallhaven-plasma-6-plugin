#!/usr/bin/env python3
"""Session D-Bus control, KRunner, MPRIS, and player API for Wallhaven wallpaper."""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time

try:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop, threads_init as dbus_threads_init
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
KRUNNER_EXACT_MATCH = 100  # KRunner::QueryMatch::CategoryRelevance::Highest
PLAYER_IFACE = "org.robertsm.Wallhaven.Player"
MPRIS_IFACE = "org.mpris.MediaPlayer2"
MPRIS_PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"

CACHE = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
PLASMA_CACHE = os.path.join(CACHE, "plasmashell")
CONTROL_FILE = os.path.join(PLASMA_CACHE, "wallhaven-control.json")
STATUS_FILE = os.path.join(PLASMA_CACHE, "wallhaven-status.json")
DBUS_CONFIG_FILE = os.path.join(PLASMA_CACHE, "wallhaven-dbus-config.json")
WRITE_LOG_NAME = "wallhaven-dbus-write.log"
WRITE_LOG_MAX_BYTES = 256 * 1024
# Every command here has its own argv policy below. There is deliberately no
# shell: lock-screen sync, Variety symlinks, accent sync and KWallet access are
# purpose-built D-Bus methods, so clients never hand this service a script.
ALLOWED_COMMANDS = {
    "rm",
    "cp",
    "curl",
    "test",
    "stat",
    "systemsettings",
    "plasma-apply-colors",
}
# Only realesrgan-ncnn-vulkan is driven directly (its "-i <in> -o <out> -n <model>"
# invocation is hardcoded below); other ncnn-vulkan-family tools take different
# flags/model names and are not wired up to avoid guessing at an untested CLI shape.
UPSCALER_BINARY = "realesrgan-ncnn-vulkan"
UPSCALER_MODEL = "realesrgan-x4plus"
UPSCALE_TIMEOUT_SEC = 120
BATTERY_CAPACITY_RE = re.compile(r"^/sys/class/power_supply/BAT\d+/capacity$")
HOME_READ_BLOCKED = (".ssh", ".gnupg", ".local/share/keyrings/")
CURL_HOST_RE = re.compile(r"^https://([a-z0-9-]+\.)*wallhaven\.cc(?:/|$)", re.IGNORECASE)
CONTROL_CMD_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
MAX_CONTROL_QUERY_CHARS = 2000

KWALLET_WALLET = "kdewallet"
KWALLET_FOLDER = "org.robertsm.wallhaven"
KWALLET_ENTRY = "apikey"
# Reading may wait on the wallet-unlock dialog, so allow for a slow human.
KWALLET_TIMEOUT_SEC = 120
MAX_API_KEY_CHARS = 256

LOCK_SCREEN_PREFIX = "wallhaven-lockscreen-"
LOCK_SCREEN_CURRENT_NAME = "wallhaven-lockscreen-current.jpg"
LOCK_SCREEN_LEGACY_NAME = "wallhaven-lockscreen.jpg"
LOCK_SCREEN_FLOCK_NAME = "wallhaven-lockscreen.lock"
LOCK_SCREEN_DEST_RE = re.compile(r"^wallhaven-lockscreen-[A-Za-z0-9_-]+\.jpg$")
LOCK_SCREEN_FLOCK_TIMEOUT_SEC = 30
LOCK_SCREEN_PRUNE_AGE_SEC = 30 * 60
# A greeter Image= this fresh was just written by a sibling monitor; reuse it
# instead of stampeding new repaired-*.jpg paths.
LOCK_SCREEN_FRESH_SEC = 90
GREETER_IMAGE_GROUPS = (
    "--group", "Greeter", "--group", "Wallpaper",
    "--group", "org.kde.image", "--group", "General",
)
KCONFIG_TIMEOUT_SEC = 15

VARIETY_SYMLINK_NAME = "wallhaven-current.jpg"
KDE_ACCENT_RE = re.compile(r"^\d{1,3},\d{1,3},\d{1,3}$")
GNOME_ACCENT_RE = re.compile(r"^[a-z]{1,32}$")
SYNC_FILE_RE = re.compile(r"^wallhaven-sync-([A-Za-z0-9_-]{1,64})\.json$")
MAX_STAT_PATHS = 512
# A running wallpaper republishes its status at least every 30 s. A file this
# old belongs to a monitor that was unplugged (or a wallpaper that is gone).
STATUS_STALE_SEC = 300


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


def validate_home_path(path: str) -> str:
    """Writable/readable path under $HOME, excluding secret dirs."""
    return validate_read_path(path)


def _deny(reason: str) -> None:
    raise dbus.exceptions.DBusException(
        f"org.freedesktop.DBus.Error.AccessDenied: {reason}",
    )


def _validate_curl_argv(argv: list[str]) -> list[str]:
    # curl -fsSL --max-time N -o <cache> <https://*.wallhaven.cc/...>
    if len(argv) != 7:
        _deny("curl: unexpected argc")
    if argv[1:3] != ["-fsSL", "--max-time"]:
        _deny("curl: flags must be -fsSL --max-time")
    try:
        timeout = int(argv[3])
    except ValueError as exc:
        _deny("curl: invalid max-time")
        raise exc
    if timeout < 1 or timeout > 300:
        _deny("curl: max-time out of range")
    if argv[4] != "-o":
        _deny("curl: missing -o")
    out_path = validate_cache_path(argv[5])
    url = argv[6]
    if not CURL_HOST_RE.match(url):
        _deny("curl: URL host not allowed")
    if any(ch.isspace() for ch in url) or "'" in url or '"' in url:
        _deny("curl: URL has illegal characters")
    return ["curl", "-fsSL", "--max-time", str(timeout), "-o", out_path, url]


def _validate_rm_argv(argv: list[str]) -> list[str]:
    # rm -f <cache_path>  (single file only; never -r)
    if len(argv) != 3 or argv[1] != "-f":
        _deny("rm: only 'rm -f <cache-file>' is allowed")
    path = validate_cache_path(argv[2])
    if path.endswith(os.sep) or os.path.isdir(path):
        _deny("rm: refusing directory path")
    return ["rm", "-f", path]


def _validate_cp_argv(argv: list[str]) -> list[str]:
    # cp <cache_src> <home_or_cache_dest>
    if len(argv) != 3:
        _deny("cp: only 'cp <src> <dest>' is allowed")
    src = validate_cache_path(argv[1])
    dest = validate_home_path(argv[2])
    return ["cp", src, dest]


def _validate_test_argv(argv: list[str]) -> list[str]:
    if len(argv) != 3 or argv[1] != "-s":
        _deny("test: only 'test -s <cache-file>' is allowed")
    return ["test", "-s", validate_cache_path(argv[2])]


def _validate_stat_argv(argv: list[str]) -> list[str]:
    if len(argv) != 4 or argv[1] != "-c" or argv[2] != "%s":
        _deny("stat: only 'stat -c %s <cache-file>' is allowed")
    return ["stat", "-c", "%s", validate_cache_path(argv[3])]


def _validate_systemsettings_argv(argv: list[str]) -> list[str]:
    if argv == ["systemsettings", "kcm_wallpaper"]:
        return argv
    _deny("systemsettings: only kcm_wallpaper is allowed")


def _validate_plasma_apply_colors_argv(argv: list[str]) -> list[str]:
    if len(argv) != 3 or argv[1] != "--accent-color":
        _deny("plasma-apply-colors: unexpected argv")
    color = argv[2]
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
        _deny("plasma-apply-colors: invalid color")
    return ["plasma-apply-colors", "--accent-color", color]


def validate_run_argv(argv: list[str]) -> list[str]:
    """Return a sanitized argv or raise AccessDenied/InvalidArgs."""
    if not argv:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: empty argv")
    if len(argv) > 16:
        _deny("argv too long")
    cleaned = [str(part) for part in argv]
    for part in cleaned:
        if "\x00" in part:
            _deny("nul byte in argv")
    program = os.path.basename(cleaned[0])
    if cleaned[0] not in (program, f"/usr/bin/{program}", f"/bin/{program}"):
        # Allow plain name or absolute standard paths only.
        which = shutil.which(program) or ""
        if cleaned[0] != which:
            _deny(f"command path not allowed: {cleaned[0]}")
    if program not in ALLOWED_COMMANDS:
        _deny(f"command not allowed: {program}")
    cleaned[0] = program
    if program == "curl":
        return _validate_curl_argv(cleaned)
    if program == "rm":
        return _validate_rm_argv(cleaned)
    if program == "cp":
        return _validate_cp_argv(cleaned)
    if program == "test":
        return _validate_test_argv(cleaned)
    if program == "stat":
        return _validate_stat_argv(cleaned)
    if program == "systemsettings":
        return _validate_systemsettings_argv(cleaned)
    if program == "plasma-apply-colors":
        return _validate_plasma_apply_colors_argv(cleaned)
    _deny(f"no policy for {program}")
    return cleaned


def run_argv(argv: list[str]) -> int:
    safe = validate_run_argv(argv)
    result = subprocess.run(safe, check=False)
    return int(result.returncode or 0)


def log_rejected_write(path: str, reason: object) -> None:
    """Record a refused WriteTextFile. Successful writes are not logged: status
    is published every few seconds per monitor and used to grow this file
    without bound (hundreds of MB)."""
    log_path = os.path.join(PLASMA_CACHE, WRITE_LOG_NAME)
    try:
        if os.path.getsize(log_path) > WRITE_LOG_MAX_BYTES:
            os.remove(log_path)
    except OSError:
        pass
    try:
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(f"REJECT {path!r} err={reason}\n")
    except OSError:
        pass


def trim_write_log() -> None:
    """Drop an oversized write log left behind by older service builds."""
    log_path = os.path.join(PLASMA_CACHE, WRITE_LOG_NAME)
    try:
        if os.path.getsize(log_path) > WRITE_LOG_MAX_BYTES:
            os.remove(log_path)
    except OSError:
        pass


def sanitize_api_key(value: object) -> str:
    """A Wallhaven API token, or "" for anything that cannot be one."""
    key = str(value or "").strip()
    if not key or len(key) > MAX_API_KEY_CHARS:
        return ""
    # kwallet-query prints a sentence when the entry is missing; tokens have
    # no whitespace or control characters.
    if any(ch.isspace() or ord(ch) < 32 for ch in key):
        return ""
    return key


def _kwallet_argv(mode: str) -> list[str]:
    # kwallet-query [options] <wallet>: the wallet is positional.
    return ["kwallet-query", mode, KWALLET_ENTRY, "-f", KWALLET_FOLDER, KWALLET_WALLET]


def wallet_read_api_key() -> str:
    """API key stored in KWallet, or "" when missing/unavailable.

    The secret only ever travels over pipes: it is never written to disk and
    never appears in a process argument list.
    """
    if not shutil.which("kwallet-query"):
        return ""
    try:
        proc = subprocess.run(
            _kwallet_argv("-r"),
            capture_output=True, text=True, timeout=KWALLET_TIMEOUT_SEC, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if proc.returncode != 0:
        return ""
    return sanitize_api_key(proc.stdout)


def wallet_write_api_key(key: str) -> bool:
    clean = sanitize_api_key(key)
    if not clean or not shutil.which("kwallet-query"):
        return False
    try:
        proc = subprocess.run(
            _kwallet_argv("-w"),
            input=clean, capture_output=True, text=True,
            timeout=KWALLET_TIMEOUT_SEC, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return proc.returncode == 0


def remove_legacy_api_key_file() -> bool:
    """Delete the plaintext key copy that builds before 3.7 left in the cache."""
    path = os.path.join(PLASMA_CACHE, "kwallet-apikey.txt")
    if not os.path.lexists(path):
        return False
    _silent_remove(path)
    return True


def _nonempty_file(path: str) -> bool:
    try:
        return os.path.isfile(path) and os.path.getsize(path) > 0
    except OSError:
        return False


def _atomic_copy(src: str, dst: str) -> None:
    tmp = dst + ".tmp"
    shutil.copyfile(src, tmp)
    os.replace(tmp, dst)


def _kwriteconfig(file: str, groups: tuple[str, ...], key: str, value: str) -> None:
    subprocess.run(
        ["kwriteconfig6", "--file", file, *groups, "--key", key, value],
        check=True, timeout=KCONFIG_TIMEOUT_SEC,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def _kreadconfig(file: str, groups: tuple[str, ...], key: str) -> str:
    try:
        proc = subprocess.run(
            ["kreadconfig6", "--file", file, *groups, "--key", key],
            capture_output=True, text=True, timeout=KCONFIG_TIMEOUT_SEC, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return (proc.stdout or "").strip()


def greeter_image_path() -> str:
    """Local path kscreenlockerrc's org.kde.image wallpaper points at ("" if unset)."""
    return normalize_local_path(_kreadconfig("kscreenlockerrc", GREETER_IMAGE_GROUPS, "Image"))


def greeter_wallpaper_plugin() -> str:
    return _kreadconfig("kscreenlockerrc", ("--group", "Greeter"), "WallpaperPlugin")


def point_greeter_at(path: str) -> None:
    url = "file://" + path
    _kwriteconfig("kscreenlockerrc", ("--group", "Greeter"), "WallpaperPlugin", "org.kde.image")
    _kwriteconfig("kscreenlockerrc", GREETER_IMAGE_GROUPS, "Image", url)
    _kwriteconfig("kscreenlockerrc", GREETER_IMAGE_GROUPS, "PreviewImage", url)
    _kwriteconfig("kscreenlockerrc", GREETER_IMAGE_GROUPS, "FillMode", "2")


def is_wallhaven_lock_image(path: str) -> bool:
    """True for lock-screen copies this plugin wrote into the plasmashell cache."""
    if not path:
        return False
    full = os.path.realpath(path)
    name = os.path.basename(full)
    return (
        os.path.dirname(full) == os.path.realpath(PLASMA_CACHE)
        and (name.startswith(LOCK_SCREEN_PREFIX) or name == LOCK_SCREEN_LEGACY_NAME)
    )


@contextlib.contextmanager
def lock_screen_flock(timeout: float = LOCK_SCREEN_FLOCK_TIMEOUT_SEC):
    """Serialize multi-monitor lock-screen writers (same flock(2) the old
    `flock -w 30` shell pipeline took, so mixed versions still exclude)."""
    os.makedirs(PLASMA_CACHE, exist_ok=True)
    fd = os.open(os.path.join(PLASMA_CACHE, LOCK_SCREEN_FLOCK_NAME), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("lock-screen flock timed out") from None
                time.sleep(0.1)
        yield
    finally:
        os.close(fd)


def prune_lock_screen_copies(keep_names: set[str]) -> None:
    """Age-gated cleanup of old unique lock images; never the ones still in use."""
    cache = os.path.realpath(PLASMA_CACHE)
    cutoff = time.time() - LOCK_SCREEN_PRUNE_AGE_SEC
    try:
        names = os.listdir(cache)
    except OSError:
        return
    for name in names:
        is_copy = name == LOCK_SCREEN_LEGACY_NAME or (
            name.startswith(LOCK_SCREEN_PREFIX) and name.endswith(".jpg")
        )
        if not is_copy or name in keep_names:
            continue
        path = os.path.join(cache, name)
        try:
            if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
                os.remove(path)
        except OSError:
            continue


def lock_screen_sync(source: str, dest: str) -> str:
    """Copy `source` to the unique lock image `dest` and point the greeter at it.

    Returns "ok" or "fail:<reason>". A unique path per wallpaper makes
    kscreenlocker reload; wallhaven-lockscreen-current.jpg is the stable mirror
    that monitors without SyncLockScreen (and wake recovery) fall back to.
    """
    src = validate_read_path(source)
    dst = validate_cache_path(dest)
    name = os.path.basename(dst)
    if os.path.dirname(dst) != os.path.realpath(PLASMA_CACHE) or not LOCK_SCREEN_DEST_RE.match(name):
        _deny("lock screen: destination must be a wallhaven-lockscreen-<id>.jpg in the cache")
    current = os.path.join(os.path.realpath(PLASMA_CACHE), LOCK_SCREEN_CURRENT_NAME)
    try:
        with lock_screen_flock():
            if not os.path.isfile(src):
                return "fail:source-missing"
            if src != dst:
                _atomic_copy(src, dst)
            if not _nonempty_file(dst):
                return "fail:dest-empty"
            if dst != current:
                _atomic_copy(dst, current)
            if not _nonempty_file(current):
                return "fail:mirror-empty"
            point_greeter_at(dst)
            # Whatever kscreenlockerrc references now (repaired/stale ids) stays too.
            active = os.path.basename(greeter_image_path() or "")
            prune_lock_screen_copies({name, LOCK_SCREEN_CURRENT_NAME, active})
            if not _nonempty_file(dst) or not _nonempty_file(current):
                return "fail:vanished"
    except TimeoutError:
        return "fail:busy"
    except (OSError, subprocess.SubprocessError) as exc:
        return f"fail:{type(exc).__name__}"
    return "ok"


def newest_lock_screen_copy() -> str:
    cache = os.path.realpath(PLASMA_CACHE)
    best = ""
    best_mtime = -1.0
    try:
        names = os.listdir(cache)
    except OSError:
        return ""
    for name in names:
        if not (name.startswith(LOCK_SCREEN_PREFIX) and name.endswith(".jpg")):
            continue
        path = os.path.join(cache, name)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime > best_mtime and _nonempty_file(path):
            best, best_mtime = path, mtime
    return best


def lock_screen_ensure() -> str:
    """Repair a blank lock screen from the last image a syncing monitor published.

    Returns "ok", "skip:<why>" when the greeter is not ours to touch, or
    "fail:<reason>". Safe from monitors without SyncLockScreen: it only ever
    re-points the greeter at an image this plugin already wrote, and leaves a
    lock wallpaper the user picked themselves (or another wallpaper plugin)
    alone.
    """
    cache = os.path.realpath(PLASMA_CACHE)
    current = os.path.join(cache, LOCK_SCREEN_CURRENT_NAME)
    try:
        with lock_screen_flock():
            plugin = greeter_wallpaper_plugin()
            if plugin and plugin != "org.kde.image":
                return "skip:foreign-plugin"
            img = greeter_image_path()
            img_ok = bool(img) and _nonempty_file(img)
            if img_ok and not is_wallhaven_lock_image(img):
                return "skip:foreign-image"
            if img_ok:
                age = time.time() - os.path.getmtime(img)
                if age < LOCK_SCREEN_FRESH_SEC:
                    if os.path.realpath(img) != current:
                        _atomic_copy(img, current)
                    _kwriteconfig(
                        "kscreenlockerrc", ("--group", "Greeter"), "WallpaperPlugin", "org.kde.image",
                    )
                    return "ok"
            if img_ok:
                src = os.path.realpath(img)
            elif _nonempty_file(current):
                src = current
            else:
                src = newest_lock_screen_copy()
            if not src or not _nonempty_file(src):
                return "fail:no-source"
            # Stale or missing Image= gets a new unique path so Plasma reloads textures.
            dst = os.path.join(cache, f"{LOCK_SCREEN_PREFIX}repaired-{int(time.time())}.jpg")
            if src != dst:
                _atomic_copy(src, dst)
            _atomic_copy(dst, current)
            if not _nonempty_file(dst) or not _nonempty_file(current):
                return "fail:copy-empty"
            point_greeter_at(dst)
    except TimeoutError:
        return "fail:busy"
    except (OSError, subprocess.SubprocessError) as exc:
        return f"fail:{type(exc).__name__}"
    return "ok"


def link_variety_current(folder: str, source: str) -> str:
    """Point <folder>/wallhaven-current.jpg at the wallpaper on screen."""
    target_dir = validate_home_path(os.path.expanduser(str(folder or "").strip()))
    src = validate_read_path(source)
    link = os.path.join(target_dir, VARIETY_SYMLINK_NAME)
    try:
        os.makedirs(target_dir, exist_ok=True)
        tmp = link + ".tmp"
        with contextlib.suppress(OSError):
            os.remove(tmp)
        os.symlink(src, tmp)
        os.replace(tmp, link)
    except OSError as exc:
        return f"fail:{type(exc).__name__}"
    return "ok"


def sync_system_accent(kde_color: str, gnome_accent: str = "") -> str:
    """Write the wallpaper's accent to kdeglobals (and GNOME's enum when asked)."""
    kde = str(kde_color or "").strip()
    if not KDE_ACCENT_RE.match(kde) or any(int(part) > 255 for part in kde.split(",")):
        _deny("accent: expected 'r,g,b'")
    gnome = str(gnome_accent or "").strip()
    if gnome and not GNOME_ACCENT_RE.match(gnome):
        _deny("accent: invalid GNOME accent name")
    try:
        _kwriteconfig("kdeglobals", ("--group", "General"), "AccentColor", kde)
    except (OSError, subprocess.SubprocessError) as exc:
        return f"fail:{type(exc).__name__}"
    if gnome and shutil.which("gsettings"):
        with contextlib.suppress(OSError, subprocess.SubprocessError):
            subprocess.run(
                ["gsettings", "set", "org.gnome.desktop.interface", "accent-color", gnome],
                check=False, timeout=KCONFIG_TIMEOUT_SEC,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    return "ok"


def stat_cache_files(paths_json: str) -> str:
    """Sizes of plasmashell-cache files as a JSON {path: bytes} map (0 if missing)."""
    try:
        paths = json.loads(paths_json or "[]")
    except json.JSONDecodeError as exc:
        raise dbus.exceptions.DBusException(
            f"org.freedesktop.DBus.Error.InvalidArgs: invalid paths json: {exc}",
        ) from exc
    if not isinstance(paths, list) or len(paths) > MAX_STAT_PATHS:
        raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: paths must be a short list")
    sizes: dict[str, int] = {}
    for raw in paths:
        key = str(raw)
        try:
            sizes[key] = os.path.getsize(validate_cache_path(key))
        except (OSError, dbus.exceptions.DBusException):
            sizes[key] = 0
    return json.dumps(sizes)


class BusNotifier:
    """Turns control/sync/status writes into D-Bus signals.

    The wallpaper used to poll wallhaven-control.json every 400 ms on every
    monitor. Writers inside this service notify directly; a directory monitor
    covers external writers (wallhaven-ctl.sh fallback, scripts, tests). Both
    paths can report the same write, so identical content is emitted once.
    """

    def __init__(self) -> None:
        self.control = None  # WallhavenControl once exported
        self.mpris = None
        self._last: dict[str, str] = {}
        self._monitor = None

    def file_written(self, path: str, content: str | None = None) -> None:
        if self.control is None:
            return
        name = os.path.basename(path)
        sync = SYNC_FILE_RE.match(name)
        if name != os.path.basename(CONTROL_FILE) and not sync:
            return
        if content is None:
            try:
                with open(path, encoding="utf-8") as handle:
                    content = handle.read()
            except (OSError, UnicodeDecodeError):
                return
        # Truncate-then-write shows up as an empty read first; wait for the body.
        if not content.strip() or self._last.get(name) == content:
            return
        self._last[name] = content
        if sync:
            self.control.SyncAdvanced(sync.group(1), content)
        else:
            self.control.ControlChanged(content)

    def status_published(self, namespace: str, content: str) -> None:
        if self.control is not None:
            self.control.StatusChanged(namespace, content)
        if self.mpris is not None and not namespace:
            self.mpris.refresh_status()

    def watch_cache_dir(self) -> None:
        os.makedirs(PLASMA_CACHE, exist_ok=True)

        def on_event(_monitor, gfile, _other, event) -> None:
            if event in (Gio.FileMonitorEvent.DELETED, Gio.FileMonitorEvent.ATTRIBUTE_CHANGED):
                return
            path = gfile.get_path() if gfile is not None else ""
            if path:
                self.file_written(path)

        try:
            monitor = Gio.File.new_for_path(PLASMA_CACHE).monitor_directory(
                Gio.FileMonitorFlags.NONE, None,
            )
            # Default coalescing is 800 ms per file; control commands are interactive.
            monitor.set_rate_limit(50)
            monitor.connect("changed", on_event)
            self._monitor = monitor
        except GLib.Error as exc:
            print(f"cache dir monitor failed ({exc}); polling control file", flush=True)
            GLib.timeout_add(500, lambda: (self.file_written(CONTROL_FILE), True)[1])


NOTIFIER = BusNotifier()


def run_async(work, reply, error) -> None:
    """Run blocking `work()` off the main loop and answer the D-Bus call later.

    curl downloads, the upscaler and KWallet prompts can take minutes; run
    inline they froze every other method (and signal) of this service.
    """

    def finish(callback, value) -> bool:
        callback(value)
        return False

    def target() -> None:
        try:
            result = work()
        except dbus.exceptions.DBusException as exc:
            GLib.idle_add(finish, error, exc)
        except Exception as exc:  # noqa: BLE001 - must always answer the caller
            GLib.idle_add(
                finish, error,
                dbus.exceptions.DBusException(f"org.freedesktop.DBus.Error.Failed: {exc}"),
            )
        else:
            GLib.idle_add(finish, reply, result)

    threading.Thread(target=target, daemon=True).start()


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


def monitor_status_files() -> list[str]:
    """Names of per-monitor status files that belong to a live wallpaper.

    Status files of unplugged monitors stay behind forever; they used to show
    up as ghost entries in the plasmoid's monitor picker and as fan-out targets
    nobody listens on. If every file is old (just woke from suspend, wallpaper
    not running yet) all of them are returned rather than none.
    """
    try:
        names = sorted(
            name for name in os.listdir(PLASMA_CACHE)
            if name.startswith("wallhaven-status-") and name.endswith(".json")
        )
    except OSError:
        return []
    cutoff = time.time() - STATUS_STALE_SEC
    fresh = []
    for name in names:
        try:
            if os.path.getmtime(os.path.join(PLASMA_CACHE, name)) >= cutoff:
                fresh.append(name)
        except OSError:
            continue
    return fresh or names


def list_sync_groups() -> list[str]:
    """Unique sync groups from per-monitor status files (fallback: namespaces / default)."""
    groups: list[str] = []
    try:
        for name in monitor_status_files():
            ns = name[len("wallhaven-status-") : -len(".json")].strip()
            path = os.path.join(PLASMA_CACHE, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    data = json.load(handle)
            except (OSError, json.JSONDecodeError):
                # Unreadable status still names a live screen namespace.
                if ns and ns not in groups:
                    groups.append(ns)
                continue
            group = str(data.get("syncGroup") or data.get("cacheNamespace") or "").strip()
            if not group:
                group = ns
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


def primary_output_name() -> str:
    """Name of the primary (priority 1) KScreen output, or "" if unknown."""
    if not shutil.which("kscreen-doctor"):
        return ""
    try:
        proc = subprocess.run(
            ["kscreen-doctor", "-j"], capture_output=True, text=True, timeout=3, check=False,
        )
        outputs = json.loads(proc.stdout or "{}").get("outputs") or []
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, AttributeError):
        return ""
    enabled = [o for o in outputs if isinstance(o, dict) and o.get("enabled") and o.get("name")]
    enabled.sort(key=lambda o: o.get("priority") or 999)
    return str(enabled[0]["name"]) if enabled else ""


def primary_sync_group() -> str:
    """Sync group of the wallpaper on the primary screen (fallback: shared status)."""
    name = primary_output_name()
    if name:
        safe = re.sub(r"[^A-Za-z0-9._-]+", "_", name)[:80]
        try:
            with open(os.path.join(PLASMA_CACHE, f"wallhaven-status-{safe}.json"), encoding="utf-8") as handle:
                data = json.load(handle)
            group = str(data.get("syncGroup") or data.get("cacheNamespace") or "").strip()
            if group:
                return group
        except (OSError, json.JSONDecodeError, AttributeError):
            pass
    data = read_status()
    return str(data.get("syncGroup") or data.get("cacheNamespace") or "").strip()


def write_control_file(content: str) -> None:
    os.makedirs(os.path.dirname(CONTROL_FILE), exist_ok=True)
    with open(CONTROL_FILE, "w", encoding="utf-8") as handle:
        handle.write(content)
    NOTIFIER.file_written(CONTROL_FILE, content)


def write_command(cmd: str, group: str = "default", query: str = "") -> None:
    name = str(cmd or "").strip().lower()
    if not CONTROL_CMD_RE.match(name):
        raise ValueError(f"invalid control command: {cmd!r}")
    target = re.sub(r"[^A-Za-z0-9_.-]", "_", str(group or "default"))[:64] or "default"
    # Screens isolate onto their own sync group, so a "default" search/like/info
    # reached nobody. Nav still broadcasts; everything else goes to the primary screen.
    if target == "default" and name not in _NAV_FANOUT:
        primary = re.sub(r"[^A-Za-z0-9_.-]", "_", primary_sync_group())[:64]
        if primary:
            target = primary
    text = str(query or "")
    if len(text) > MAX_CONTROL_QUERY_CHARS:
        text = text[:MAX_CONTROL_QUERY_CHARS]
    payload: dict[str, object] = {"cmd": name, "ts": int(time.time() * 1000), "group": target}
    if text:
        payload["query"] = text
    write_control_file(json.dumps(payload))


_NAV_FANOUT = {
    "next", "prev", "pause", "resume", "reload",
    "outageoffline", "resumeonline",
}


def write_command_fanout(cmd: str, group: str = "default", query: str = "") -> None:
    """Write one control command; fan-out nav cmds when group is the shared default."""
    name = str(cmd or "").strip().lower()
    if not CONTROL_CMD_RE.match(name):
        raise ValueError(f"invalid control command: {cmd!r}")
    target = re.sub(r"[^A-Za-z0-9_.-]", "_", str(group or "default"))[:64] or "default"
    text = str(query or "")
    if len(text) > MAX_CONTROL_QUERY_CHARS:
        text = text[:MAX_CONTROL_QUERY_CHARS]
    if name in _NAV_FANOUT and target == "default":
        groups = list_sync_groups()
        base = int(time.time() * 1000)
        commands = []
        for i, g in enumerate(groups):
            safe_group = re.sub(r"[^A-Za-z0-9_.-]", "_", str(g or "default"))[:64] or "default"
            entry: dict[str, object] = {"cmd": name, "ts": base + i, "group": safe_group}
            if text:
                entry["query"] = text
            commands.append(entry)
        write_control_file(json.dumps({"commands": commands}))
        return
    write_command(name, target, text)


def read_status() -> dict:
    try:
        with open(STATUS_FILE, encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
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
        return "3.7.0"

    @dbus.service.method(INTERFACE, out_signature="s")
    def ListMonitorStatuses(self) -> str:
        """Return JSON array of per-monitor status snapshots (wallhaven-status-*.json)."""
        out: list[dict] = []
        try:
            for name in monitor_status_files():
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
        try:
            target = validate_cache_path(path)
        except dbus.exceptions.DBusException as exc:
            log_rejected_write(path, exc)
            raise
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(content)
        NOTIFIER.file_written(target, content)
        return "ok"

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="s")
    def PublishStatusJson(self, content: str) -> str:
        """Write status JSON to the plasmashell cache (no client-supplied path)."""
        text = content or "{}"
        reply = self.WriteTextFile(STATUS_FILE, text)
        NOTIFIER.status_published("", text)
        return reply

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="s")
    def PublishMonitorStatusJson(self, namespace: str, content: str) -> str:
        """Write per-monitor status JSON under the plasmashell cache."""
        safe = re.sub(r"[^A-Za-z0-9._-]+", "_", str(namespace or "default"))[:80] or "default"
        target = os.path.join(PLASMA_CACHE, f"wallhaven-status-{safe}.json")
        text = content or "{}"
        reply = self.WriteTextFile(target, text)
        NOTIFIER.status_published(safe, text)
        return reply

    # --- change notifications (replace file polling in the wallpaper/plasmoid)

    @dbus.service.signal(INTERFACE, signature="s")
    def ControlChanged(self, payload):  # noqa: N802
        """wallhaven-control.json was rewritten; payload is its JSON text."""

    @dbus.service.signal(INTERFACE, signature="ss")
    def SyncAdvanced(self, group, payload):  # noqa: N802
        """wallhaven-sync-<group>.json was rewritten."""

    @dbus.service.signal(INTERFACE, signature="ss")
    def StatusChanged(self, namespace, payload):  # noqa: N802
        """A status snapshot was published ("" namespace = shared primary status)."""

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

    @dbus.service.method(
        INTERFACE, in_signature="s", out_signature="s", async_callbacks=("reply", "error"),
    )
    def RunArgv(self, argv_json: str, reply, error) -> None:
        try:
            argv = json.loads(argv_json)
        except json.JSONDecodeError as exc:
            raise dbus.exceptions.DBusException(
                f"org.freedesktop.DBus.Error.InvalidArgs: invalid argv json: {exc}",
            ) from exc
        if not isinstance(argv, list):
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: argv must be a list")
        # Refuse on the caller's turn; only the (possibly slow) process is deferred.
        safe = validate_run_argv([str(part) for part in argv])

        def work() -> str:
            code = int(subprocess.run(safe, check=False).returncode or 0)
            return "ok" if code == 0 else f"fail:{code}"

        run_async(work, reply, error)

    @dbus.service.method(INTERFACE, in_signature="s", out_signature="s")
    def StatCacheFiles(self, paths_json: str) -> str:
        """JSON {path: size} for cache files, in one call instead of a `stat` per file."""
        return stat_cache_files(paths_json)

    @dbus.service.method(INTERFACE, out_signature="s", async_callbacks=("reply", "error"))
    def GetApiKey(self, reply, error) -> None:
        """API key from KWallet ("" when none). Never touches disk."""
        remove_legacy_api_key_file()
        run_async(wallet_read_api_key, reply, error)

    @dbus.service.method(
        INTERFACE, in_signature="s", out_signature="s", async_callbacks=("reply", "error"),
    )
    def SetApiKey(self, key: str, reply, error) -> None:
        """Store the API key in KWallet (fed on stdin, never as an argument)."""
        clean = sanitize_api_key(key)
        if not clean:
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: not an API key")
        remove_legacy_api_key_file()
        run_async(lambda: "ok" if wallet_write_api_key(clean) else "fail", reply, error)

    @dbus.service.method(
        INTERFACE, in_signature="ss", out_signature="s", async_callbacks=("reply", "error"),
    )
    def SyncLockScreen(self, source: str, dest: str, reply, error) -> None:
        """Copy a wallpaper to its unique lock-screen image and point the greeter at it."""
        validate_read_path(source)
        validate_cache_path(dest)
        run_async(lambda: lock_screen_sync(source, dest), reply, error)

    @dbus.service.method(INTERFACE, out_signature="s", async_callbacks=("reply", "error"))
    def EnsureLockScreen(self, reply, error) -> None:
        """Repair a blank lock-screen image from the last synced copy."""
        run_async(lock_screen_ensure, reply, error)

    @dbus.service.method(INTERFACE, in_signature="ss", out_signature="s")
    def LinkVarietyCurrent(self, folder: str, source: str) -> str:
        return link_variety_current(folder, source)

    @dbus.service.method(
        INTERFACE, in_signature="ss", out_signature="s", async_callbacks=("reply", "error"),
    )
    def SyncSystemAccent(self, kde_color: str, gnome_accent: str, reply, error) -> None:
        kde = str(kde_color or "").strip()
        if not KDE_ACCENT_RE.match(kde):
            raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs: expected 'r,g,b'")
        run_async(lambda: sync_system_accent(kde, gnome_accent), reply, error)

    @dbus.service.method(INTERFACE, out_signature="s")
    def UpscalerAvailable(self) -> str:
        """Resolved path of the external upscaler binary, or "" if not installed."""
        return find_upscaler()

    @dbus.service.method(
        INTERFACE, in_signature="ss", out_signature="b", async_callbacks=("reply", "error"),
    )
    def Upscale(self, input_path: str, output_path: str, reply, error) -> None:
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
        run_async(lambda: upscale_file(input_path, output_path), reply, error)


def upscale_file(input_path: str, output_path: str) -> bool:
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

    # CanPlay/CanPause are advertised, so MPRIS clients may call these directly.
    @dbus.service.method(MPRIS_PLAYER_IFACE)
    def Play(self) -> None:
        write_command("resume", self.group)

    @dbus.service.method(MPRIS_PLAYER_IFACE)
    def Pause(self) -> None:
        write_command("pause", self.group)

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
            # krunner1 wants (id, text, icon, categoryRelevance:int, relevance:double,
            # properties); a float in the int slot made every Match raise TypeError.
            matches.append((
                match_id, text, "preferences-desktop-wallpaper", KRUNNER_EXACT_MATCH, relevance,
                {"subtext": subtext},
            ))

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
    cli_cmds = {
        "next", "prev", "reload", "pause", "resume", "open", "block", "copytags", "like", "dislike",
        "pin", "unpin", "copyid", "copyurl", "warm", "prune", "endtrip", "undo", "clearkey", "testkey",
        "info", "cancelwarm", "outageoffline", "resumeonline", "copysearch",
    }
    if len(sys.argv) > 1 and sys.argv[1] in cli_cmds:
        write_command_fanout(sys.argv[1], group)
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
        "history", "applysearch", "savesearch", "purity", "trip", "warm", "copysearch",
    }:
        write_command(sys.argv[1], group, " ".join(sys.argv[2:]))
        print(f"Sent '{sys.argv[1]}' via control bus")
        return 0
    if len(sys.argv) > 1:
        print(f"Unknown command: {sys.argv[1]}", file=sys.stderr)
        print("Pass a control command, or run with no args to start the D-Bus service.", file=sys.stderr)
        return 2

    DBusGMainLoop(set_as_default=True)
    dbus_threads_init()
    bus = dbus.SessionBus()
    control = WallhavenControl(bus, group)
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
    trim_write_log()
    remove_legacy_api_key_file()
    NOTIFIER.control = control
    NOTIFIER.mpris = mpris
    NOTIFIER.watch_cache_dir()
    watch_status_file(mpris)
    watch_variety_config(group)
    print(f"D-Bus services {SERVICE}, {MPRIS_SERVICE}", flush=True)
    try:
        GLib.MainLoop().run()
    finally:
        del well_known
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
