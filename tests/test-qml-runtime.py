#!/usr/bin/env python3
"""Headless runtime test: load the real wallpaper and plasmoid QML.

Static checks cannot tell whether the QML actually loads (the Control plasmoid
was dead for many releases behind one stray brace). This test runs both
main.qml files in a small Qt host (tests/qml-host.py) on the offscreen platform,
against the real wallhaven-dbus.py on a private session bus, and drives them
the way the CLI/plasmoid do.

Hermetic by construction: throwaway HOME and cache, fake kwallet-query /
kwriteconfig6 / kreadconfig6 on PATH, a fake org.freedesktop.ScreenSaver, the
slideshow in offline (cache-only) mode and HTTP(S) pointed at a dead proxy.
Only the Plasma host types that plasmashell alone can create are stubbed
(tests/qml-stubs); everything else is the real module, and the wallpaper's
configuration is a real QQmlPropertyMap like Plasma's.

Skips (exit 0) when PyQt6/PySide6 or the Plasma QML modules are not installed;
set WALLHAVEN_REQUIRE_QML_RUNTIME=1 to make that a failure instead.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import warnings
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning)

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "tools" / "wallhaven-dbus.py"
STUBS = ROOT / "tests" / "qml-stubs"
BUS_NAME = "org.robertsm.Wallhaven"
IFACE = "org.robertsm.Wallhaven"
API_KEY = "Zx9TestKeyNeverReal0123456789abcd"
CACHE_IDS = ["aaa111", "bbb222", "ccc333", "ddd444"]
NAMESPACE = "testscreen"
KCFG_NS = "{http://www.kde.org/standards/kcfg/1.0}"

# Anything matching this in the QML log is a broken reference or failed load.
QML_ERROR_RE = re.compile(
    r"ReferenceError|TypeError|SyntaxError|is not a function|is not defined|is not a type"
    r"|Unable to assign|Cannot assign|Cannot read property|Cannot call method"
    r"|module \".*\" is not installed|failed to load component|Binding loop"
    r"|non-existent property|Invalid alias|is not available|HARNESS-LOAD-ERROR",
)
# Expected noise that is not a defect of the plugin under test.
QML_IGNORE_RE = re.compile(
    r"BusSignals-unavailable-on-purpose"
    r"|QStandardPaths: wrong permissions"
    r"|kf\.notifications|KNotification|org\.freedesktop\.Notifications"
    r"|Could not find the Plasmoid for|QFont::|qt\.qpa\.|libEGL|MESA|kf\.kirigami"
    r"|Wallhaven D-Bus call failed: (Upscale|RunArgv)",
)


def find_host_python() -> str:
    """A Python that can host QML (PyQt6 or PySide6): this one, else the system one."""
    for cand in (sys.executable, "/usr/bin/python3"):
        if not cand or not os.path.exists(cand):
            continue
        probe = "import importlib.util as u, sys; sys.exit(0 if (u.find_spec('PyQt6') or u.find_spec('PySide6')) else 1)"
        if subprocess.call([cand, "-c", probe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            return cand
    return ""


def find_qml_module(name: str) -> bool:
    rel = name.replace(".", "/")
    for base in (
        "/usr/lib/qt6/qml", "/usr/lib64/qt6/qml", "/usr/lib/x86_64-linux-gnu/qt6/qml",
        "/usr/lib/aarch64-linux-gnu/qt6/qml",
    ):
        if os.path.isdir(os.path.join(base, rel)):
            return True
    return False


QML_HOST = ROOT / "tests" / "qml-host.py"
QML_HOST_PYTHON = find_host_python()
REQUIRED_MODULES = ("org.kde.plasma.workspace.dbus", "org.kde.kirigami", "org.kde.notification", "org.kde.plasma.core")

if os.environ.get("WALLHAVEN_TEST_PRIVATE_BUS") != "1":
    missing = [m for m in REQUIRED_MODULES if not find_qml_module(m)]
    if not QML_HOST_PYTHON or missing or not shutil.which("dbus-run-session"):
        why = ("PyQt6/PySide6" if not QML_HOST_PYTHON
               else "QML modules: " + ", ".join(missing) if missing else "dbus-run-session")
        if os.environ.get("WALLHAVEN_REQUIRE_QML_RUNTIME") == "1":
            print(f"FAIL: QML runtime test cannot run (missing {why})", file=sys.stderr)
            sys.exit(1)
        print(f"SKIP: QML runtime test (missing {why})")
        sys.exit(0)
    env = dict(os.environ, WALLHAVEN_TEST_PRIVATE_BUS="1")
    sys.exit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__, *sys.argv[1:]], env=env))

import dbus  # noqa: E402
import dbus.service  # noqa: E402
from dbus.mainloop.glib import DBusGMainLoop  # noqa: E402
from gi.repository import GLib  # noqa: E402

FAKE_KWALLET = """#!/usr/bin/env bash
echo "kwallet-query $*" >> "$FAKE_BIN_LOG"
store="$FAKE_STATE/wallet-$2"
if [[ "$1" == "-w" ]]; then
    cat > "$store"
elif [[ -f "$store" ]]; then
    cat "$store"
else
    echo "Failed to read entry $2 value from the $6 wallet."
    exit 1
fi
"""
FAKE_KWRITECONFIG = """#!/usr/bin/env bash
echo "kwriteconfig6 $*" >> "$FAKE_BIN_LOG"
key=""; groups=""; file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file) file="$2"; shift 2 ;;
        --group) groups="$groups/$2"; shift 2 ;;
        --key) key="$2"; shift 2 ;;
        *) value="$1"; shift ;;
    esac
done
mkdir -p "$FAKE_STATE/kconfig/$file$groups"
printf '%s' "$value" > "$FAKE_STATE/kconfig/$file$groups/$key"
"""
FAKE_KREADCONFIG = """#!/usr/bin/env bash
key=""; groups=""; file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file) file="$2"; shift 2 ;;
        --group) groups="$groups/$2"; shift 2 ;;
        --key) key="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cat "$FAKE_STATE/kconfig/$file$groups/$key" 2>/dev/null || true
"""
# Anything else the plugin might launch must not reach the real desktop.
FAKE_NOOP = """#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$FAKE_BIN_LOG"
"""


def png_bytes(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """A tiny solid-colour PNG (Qt sniffs the format, so a .jpg name is fine)."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    row = b"\x00" + bytes(rgb) * width
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(row * height))
        + chunk(b"IEND", b"")
    )


def kcfg_defaults(kcfg: Path) -> dict:
    """{key: typed default} for every entry of a kcfg file."""
    out: dict = {}
    for entry in ET.parse(kcfg).getroot().iter(f"{KCFG_NS}entry"):
        default = entry.find(f"{KCFG_NS}default")
        raw = (default.text if default is not None else "") or ""
        kind = entry.attrib.get("type", "String").lower()
        if kind == "bool":
            out[entry.attrib["name"]] = raw.strip().lower() == "true"
        elif kind in ("int", "uint"):
            out[entry.attrib["name"]] = int(raw or 0)
        elif kind == "double":
            out[entry.attrib["name"]] = float(raw or 0)
        else:
            out[entry.attrib["name"]] = raw
    return out


WALLPAPER_HARNESS = """import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    width: 1280
    height: 720

    Loader {
        id: loader
        anchors.fill: parent
        source: "%(main_url)s"
        onStatusChanged: {
            if (status === Loader.Error)
                console.log("HARNESS-LOAD-ERROR");
            else if (status === Loader.Ready)
                console.log("HARNESS-READY");
        }
    }

    property double lastCallTs: 0

    // Test hook: run `fn(args...)` on the wallpaper root when the call file changes.
    function pollCalls() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "%(call_url)s");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || !xhr.responseText)
                return;
            var call = null;
            try { call = JSON.parse(xhr.responseText); } catch (e) { return; }
            if (!call || !(call.ts > win.lastCallTs))
                return;
            win.lastCallTs = call.ts;
            var w = loader.item;
            var result = null;
            try {
                var args = call.args || [];
                if (call.fn === "__config") {
                    // Write settings the way the settings dialog's Apply does.
                    for (var key in args[0])
                        w.configuration[key] = args[0][key];
                    console.log("HARNESS-CALL " + call.ts + " null");
                    return;
                }
                if (call.fn === "__set") {
                    w[args[0]] = args[1];
                    console.log("HARNESS-CALL " + call.ts + " null");
                    return;
                }
                if (call.withCallback)
                    args = args.concat([function(v) { console.log("HARNESS-CALLBACK " + call.ts + " " + JSON.stringify(v === undefined ? null : v)); }]);
                result = w[call.fn].apply(w, args);
                console.log("HARNESS-CALL " + call.ts + " " + JSON.stringify(result === undefined ? null : result));
            } catch (err) {
                console.log("HARNESS-CALL-ERROR " + call.ts + " " + err);
            }
        };
        xhr.send();
    }

    Timer {
        interval: 200
        running: loader.status === Loader.Ready
        repeat: true
        onTriggered: {
            win.pollCalls();
            var w = loader.item;
            console.log("HARNESS-STATE " + JSON.stringify({
                configApiKey: w.configuration.ApiKey,
                effectiveApiKey: w.effectiveApiKey,
                walletStatus: w.walletStatus,
                useKWallet: w.configuration.UseKWalletForApiKey,
                syncProfiles: w.configuration.SyncProfilesJson,
                busSignalsActive: w.busSignalsActive,
                dbusServiceAvailable: w.dbusServiceAvailable,
                screenLocked: w._screenLocked,
                currentWallpaperId: w.currentWallpaperId,
                currentUrl: w.currentUrl,
                visible: w.wallpaperIsVisible(),
                paused: w.configuration.SlideshowPaused,
                searchText: w.configuration.SearchText,
                statusMessage: w.statusMessage,
                tagFavorites: w.configuration.TagFavoritesJson,
            }));
        }
    }
}
"""

# The settings dialog next to a running wallpaper, the way the wallpaper KCM
# shows it: wallpaperConfiguration is the config map, liveWallpaper the item.
SETTINGS_HARNESS = """import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid

Window {
    id: win
    visible: true
    width: 1100
    height: 900

    // KLocalizedContext provides this in Plasma; config.qml finds it here.
    function i18n(text) {
        var out = String(text);
        for (var i = 1; i < arguments.length; i++)
            out = out.split("%%" + i).join(String(arguments[i]));
        return out;
    }

    Loader {
        id: wallpaperLoader
        width: 640
        height: 360
        source: "%(main_url)s"
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("HARNESS-LOAD-ERROR wallpaper");
            } else if (status === Loader.Ready) {
                Plasmoid.wallpaperGraphicsObject = item;
                dialogLoader.active = true;
            }
        }
    }

    Loader {
        id: dialogLoader
        anchors.fill: parent
        active: false
        source: "%(config_url)s"
        onStatusChanged: {
            if (status === Loader.Error) {
                console.log("HARNESS-LOAD-ERROR settings dialog");
            } else if (status === Loader.Ready) {
                item.wallpaperConfiguration = wallhavenTestConfig;
                console.log("HARNESS-READY");
            }
        }
    }

    property double lastCallTs: 0

    function pollCalls() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "%(call_url)s");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || !xhr.responseText)
                return;
            var call = null;
            try { call = JSON.parse(xhr.responseText); } catch (e) { return; }
            if (!call || !(call.ts > win.lastCallTs))
                return;
            win.lastCallTs = call.ts;
            try {
                if (call.fn === "__setDialog")
                    dialogLoader.item[call.args[0]] = call.args[1];
                console.log("HARNESS-CALL " + call.ts + " null");
            } catch (err) {
                console.log("HARNESS-CALL-ERROR " + call.ts + " " + err);
            }
        };
        xhr.send();
    }

    Timer {
        interval: 200
        running: dialogLoader.status === Loader.Ready
        repeat: true
        onTriggered: {
            win.pollCalls();
            var d = dialogLoader.item;
            var w = wallpaperLoader.item;
            console.log("HARNESS-STATE " + JSON.stringify({
                hasLiveWallpaper: d.liveWallpaper === w,
                dialogEffectiveKey: d.effectiveApiKey,
                dialogApiKeyField: d.cfg_ApiKey,
                wallpaperEffectiveKey: w.effectiveApiKey,
                previewWallpaperId: d.previewWallpaperId,
                useKWalletChecked: d.cfg_UseKWalletForApiKey,
                dialogServiceOnline: d.dbusServiceOnline,
                dialogPollCompleted: d.dbusPollCompleted,
            }));
        }
    }
}
"""

PLASMOID_HARNESS = """import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    width: 480
    height: 640

    Loader {
        id: loader
        source: "%(main_url)s"
        onStatusChanged: {
            if (status === Loader.Error)
                console.log("HARNESS-LOAD-ERROR");
            else if (status === Loader.Ready)
                console.log("HARNESS-READY");
        }
    }

    // plasmashell instantiates the representations; do the same here.
    Loader {
        anchors.fill: parent
        active: loader.status === Loader.Ready
        sourceComponent: loader.item ? loader.item.fullRepresentation : null
        onStatusChanged: if (status === Loader.Ready) console.log("HARNESS-FULL-READY")
    }

    Loader {
        active: loader.status === Loader.Ready
        sourceComponent: loader.item ? loader.item.compactRepresentation : null
        onStatusChanged: if (status === Loader.Ready) console.log("HARNESS-COMPACT-READY")
    }

    Timer {
        interval: 200
        running: loader.status === Loader.Ready
        repeat: true
        onTriggered: {
            var p = loader.item;
            console.log("HARNESS-STATE " + JSON.stringify({
                id: p.statusData.id,
                paused: p.statusData.paused,
                dbusOffline: p.dbusOffline,
                signalsActive: p.statusSignalsActive,
                monitors: p.monitorStatuses.length,
            }));
        }
    }
}
"""


class QmlProcess:
    """A running `qml` instance whose log lines are collected as they arrive."""

    def __init__(self, argv: list[str], env: dict) -> None:
        self.lines: list[str] = []
        self.proc = subprocess.Popen(
            argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        self._thread = threading.Thread(target=self._read, daemon=True)
        self._thread.start()

    def _read(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            self.lines.append(line.rstrip("\n"))

    def state(self) -> dict:
        for line in reversed(self.lines):
            idx = line.find("HARNESS-STATE ")
            if idx != -1:
                try:
                    return json.loads(line[idx + len("HARNESS-STATE "):])
                except json.JSONDecodeError:
                    continue
        return {}

    def tail(self, count: int = 30) -> str:
        return "\n".join([line for line in self.lines if "HARNESS-STATE" not in line][-count:])

    def has(self, needle: str) -> bool:
        return any(needle in line for line in self.lines)

    def errors(self) -> list[str]:
        return [
            line for line in self.lines
            if QML_ERROR_RE.search(line) and not QML_IGNORE_RE.search(line) and "HARNESS-STATE" not in line
        ]

    def stop(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self._thread.join(timeout=2)
        if self.proc.stdout is not None:
            self.proc.stdout.close()


class FakeScreenSaver(dbus.service.Object):
    """org.freedesktop.ScreenSaver on both paths kscreenlocker exports."""

    def __init__(self, bus, path: str) -> None:
        self.active = False
        super().__init__(bus, path)

    @dbus.service.method("org.freedesktop.ScreenSaver", out_signature="b")
    def GetActive(self):  # noqa: N802
        return self.active

    @dbus.service.method("org.freedesktop.ScreenSaver", out_signature="u")
    def GetSessionIdleTime(self):  # noqa: N802
        return dbus.UInt32(0)

    @dbus.service.signal("org.freedesktop.ScreenSaver", signature="b")
    def ActiveChanged(self, active):  # noqa: N802
        pass


class RuntimeBase(unittest.TestCase):
    """Shared sandbox: private bus, fake tools, the real D-Bus service."""

    wallet_key = ""
    config_overrides: dict = {}

    @classmethod
    def setUpClass(cls) -> None:
        DBusGMainLoop(set_as_default=True)
        cls.tmp = Path(tempfile.mkdtemp(prefix="wallhaven-qml-test-"))
        cls.home = cls.tmp / "home"
        cls.cache = cls.home / ".cache" / "plasmashell"
        cls.state_dir = cls.tmp / "state"
        cls.bin = cls.tmp / "bin"
        cls.bin_log = cls.tmp / "bin.log"
        cls.stubs = cls.tmp / "stubs"
        for d in (cls.cache, cls.state_dir, cls.bin, cls.home / ".config"):
            d.mkdir(parents=True)
        for name, body in (
            ("kwallet-query", FAKE_KWALLET), ("kwriteconfig6", FAKE_KWRITECONFIG),
            ("kreadconfig6", FAKE_KREADCONFIG), ("xdg-open", FAKE_NOOP), ("curl", FAKE_NOOP),
            ("plasma-apply-colors", FAKE_NOOP), ("systemsettings", FAKE_NOOP), ("gsettings", FAKE_NOOP),
            ("kscreen-doctor", FAKE_NOOP),
        ):
            path = cls.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
        if cls.wallet_key:
            (cls.state_dir / "wallet-apikey").write_text(cls.wallet_key, encoding="utf-8")

        cls.env = dict(
            os.environ,
            HOME=str(cls.home),
            XDG_CACHE_HOME=str(cls.home / ".cache"),
            XDG_CONFIG_HOME=str(cls.home / ".config"),
            XDG_DATA_HOME=str(cls.home / ".local" / "share"),
            PATH=f"{cls.bin}:{os.environ.get('PATH', '')}",
            FAKE_STATE=str(cls.state_dir),
            FAKE_BIN_LOG=str(cls.bin_log),
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            QT_FORCE_STDERR_LOGGING="1",
            QML_XHR_ALLOW_FILE_READ="1",
            # Nothing in this test may reach the network.
            http_proxy="http://127.0.0.1:9", https_proxy="http://127.0.0.1:9",
            HTTP_PROXY="http://127.0.0.1:9", HTTPS_PROXY="http://127.0.0.1:9",
            no_proxy="", NO_PROXY="",
        )
        cls.env.pop("QT_QPA_PLATFORMTHEME", None)
        cls.env.pop("WAYLAND_DISPLAY", None)
        cls.env.pop("DISPLAY", None)

        cls.service = subprocess.Popen(
            [sys.executable, str(SERVICE)], env=cls.env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        cls.bus = dbus.SessionBus()
        deadline = time.time() + 10
        while time.time() < deadline and not cls.bus.name_has_owner(BUS_NAME):
            if cls.service.poll() is not None:
                raise RuntimeError("service exited early:\n" + (cls.service.stdout.read() or ""))
            time.sleep(0.05)
        cls.iface = dbus.Interface(cls.bus.get_object(BUS_NAME, "/Wallhaven"), IFACE)
        cls._screensaver_name = dbus.service.BusName("org.freedesktop.ScreenSaver", cls.bus)
        cls.screensaver = FakeScreenSaver(cls.bus, "/org/freedesktop/ScreenSaver")
        cls.screensaver_legacy = FakeScreenSaver(cls.bus, "/ScreenSaver")
        cls.qml: QmlProcess | None = None

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.qml is not None:
            cls.qml.stop()
        for saver in (cls.screensaver, cls.screensaver_legacy):
            saver.remove_from_connection()
        del cls._screensaver_name
        cls.service.terminate()
        try:
            cls.service.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.service.kill()
        if cls.service.stdout is not None:
            cls.service.stdout.close()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    # --- helpers

    @classmethod
    def prepare_stubs(cls) -> None:
        if cls.stubs.exists():
            shutil.rmtree(cls.stubs)
        shutil.copytree(STUBS, cls.stubs)
        config = kcfg_defaults(ROOT / "contents" / "config" / "main.xml")
        unknown = set(cls.config_overrides) - set(config)
        assert not unknown, f"config overrides not in main.xml: {unknown}"
        config.update(cls.config_overrides)
        cls.config_file = cls.tmp / "wallpaper-config.json"
        cls.config_file.write_text(json.dumps(config), encoding="utf-8")

    @classmethod
    def seed_cache(cls) -> None:
        """Four cached wallpapers so the offline slideshow has something to show."""
        colors = [(200, 60, 60), (60, 200, 60), (60, 60, 200), (200, 200, 60)]
        for slot, rgb in enumerate(colors):
            (cls.cache / f"wallhaven-cache-{NAMESPACE}-{slot:02d}.jpg").write_bytes(png_bytes(64, 36, rgb))

    @classmethod
    def cache_index_json(cls) -> str:
        return json.dumps({"ids": CACHE_IDS, "next": 0, "categories": {}, "purities": {}, "dimensions": {}})

    @classmethod
    def start_wallpaper(cls, ui_dir: Path | None = None) -> QmlProcess:
        ui = ui_dir or (ROOT / "contents" / "ui")
        harness = cls.tmp / "wallpaper-harness.qml"
        cls.call_file = cls.tmp / "harness-call.json"
        cls.call_file.write_text("", encoding="utf-8")
        harness.write_text(WALLPAPER_HARNESS % {
            "main_url": (ui / "main.qml").as_uri(),
            "call_url": cls.call_file.as_uri(),
        }, encoding="utf-8")
        cls.qml = QmlProcess(
            [QML_HOST_PYTHON, str(QML_HOST), str(harness), str(cls.stubs), str(cls.config_file)], cls.env,
        )
        return cls.qml

    @staticmethod
    def pump(seconds: float) -> None:
        ctx = GLib.MainContext.default()
        end = time.time() + seconds
        while time.time() < end:
            while ctx.pending():
                ctx.iteration(False)
            time.sleep(0.01)

    def wait_for(self, predicate, timeout: float = 10.0) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.05)
            try:
                if predicate():
                    return True
            except (KeyError, TypeError, json.JSONDecodeError, OSError):
                pass
        return False

    def status(self) -> dict:
        try:
            return json.loads((self.cache / f"wallhaven-status-{NAMESPACE}.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

    def call(self, fn: str, *args, with_callback: bool = False, timeout: float = 5.0):
        """Invoke a function on the wallpaper root; returns its JSON-able result."""
        assert self.qml is not None
        ts = int(time.time() * 1000)
        self.call_file.write_text(
            json.dumps({"ts": ts, "fn": fn, "args": list(args), "withCallback": with_callback}), encoding="utf-8",
        )
        marker = f"HARNESS-CALL {ts} "
        self.assertTrue(
            self.wait_for(lambda: self.qml.has(marker) or self.qml.has(f"HARNESS-CALL-ERROR {ts}"), timeout),
            f"wallpaper never ran {fn}()",
        )
        errors = [line for line in self.qml.lines if f"HARNESS-CALL-ERROR {ts}" in line]
        self.assertFalse(errors, f"{fn}() threw: {errors}")
        line = next(line for line in self.qml.lines if marker in line)
        return json.loads(line[line.index(marker) + len(marker):])

    def send(self, cmd: str, query: str = "") -> None:
        if query:
            self.iface.CommandWithQuery(cmd, query, NAMESPACE)
        else:
            self.iface.CommandInGroup(cmd, NAMESPACE)

    def assert_no_qml_errors(self) -> None:
        assert self.qml is not None
        errors = self.qml.errors()
        self.assertFalse(errors, "QML reported errors:\n" + "\n".join(errors[:40]))


class WallpaperRuntimeTests(RuntimeBase):
    wallet_key = API_KEY
    config_overrides = {
        # Cache-only slideshow: exercises the engine without the network.
        "OfflineOnlyMode": True,
        "DiskCacheEnabled": True,
        "CacheNamespace": NAMESPACE,
        "SyncAdvanceGroup": NAMESPACE,
        "SyncAdvanceEnabled": True,
        "SyncProfilesEnabled": True,
        "ConfigSchemaVersion": 3,
        "SetupWizardCompleted": True,
        "DebugLogEnabled": True,
        "SyncLockScreen": True,
        "UseKWalletForApiKey": True,
        "ShowAttribution": False,
        "SmartOfflineEnabled": False,
        "LocalSortings": "date_added",
        "CrossfadeMs": 0,
        "RandomInterval": 0,
        "PauseWhenInactive": True,
        "NotifyOnError": False,
        "NotifyOnRefresh": False,
        "AchievementsEnabled": False,
        # A plain-text copy of the wallet key, as builds before 3.7 left behind.
        "ApiKey": API_KEY,
        "DiskCacheIndexJson": json.dumps(
            {"ids": CACHE_IDS, "next": 0, "categories": {}, "purities": {}, "dimensions": {}},
        ),
    }

    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        cls.seed_cache()
        cls.prepare_stubs()
        cls.start_wallpaper()

    def test_01_loads_and_shows_a_cached_wallpaper(self) -> None:
        self.assertTrue(self.wait_for(lambda: self.qml.has("HARNESS-READY"), 20), self.qml.tail())
        self.assertTrue(
            self.wait_for(lambda: self.qml.state().get("visible") is True, 15),
            f"no wallpaper on screen: {self.qml.state()}\n" + self.qml.tail(),
        )
        state = self.qml.state()
        self.assertIn(state["currentWallpaperId"], CACHE_IDS)
        self.assertTrue(state["currentUrl"].startswith("file://"), state)
        self.assertTrue(self.wait_for(lambda: self.status().get("id") in CACHE_IDS))
        self.assertEqual(self.status()["cacheNamespace"], NAMESPACE)
        self.assert_no_qml_errors()

    def test_02_uses_bus_signals_not_polling(self) -> None:
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("busSignalsActive") is True))
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("dbusServiceAvailable") is True))
        # No D-Bus read of the control file may happen while idle: the fallback
        # poll is 30 s with signals, where it used to be every 400 ms.
        log = self.cache / "wallhaven-debug.log"
        self.pump(1.0)
        started = time.time()
        self.send("pause")
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is True, 5), "pause never applied")
        self.assertLess(time.time() - started, 2.0, "pause took as long as a fallback poll would")
        self.send("resume")
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is False, 5))
        self.assertTrue(log.exists())
        self.assert_no_qml_errors()

    def test_03_external_control_file_write_is_seen(self) -> None:
        # wallhaven-ctl.sh falls back to writing the file when qdbus6 is missing.
        payload = {"cmd": "pause", "ts": int(time.time() * 1000), "group": NAMESPACE}
        (self.cache / "wallhaven-control.json").write_text(json.dumps(payload), encoding="utf-8")
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is True, 5))
        self.send("resume")
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is False, 5))

    def test_04_next_and_prev_walk_the_cache(self) -> None:
        first = self.status()["id"]
        self.send("next")
        self.assertTrue(self.wait_for(lambda: self.status().get("id") not in ("", first), 8), self.status().get("id"))
        second = self.status()["id"]
        self.assertIn(second, CACHE_IDS)
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("visible") is True, 8))
        self.send("prev")
        self.assertTrue(self.wait_for(lambda: self.status().get("id") == first, 8))
        self.assert_no_qml_errors()

    def test_05_a_stale_or_foreign_command_is_ignored(self) -> None:
        before = self.status()["id"]
        stale = {"cmd": "next", "ts": int(time.time() * 1000) - 600000, "group": NAMESPACE}
        (self.cache / "wallhaven-control.json").write_text(json.dumps(stale), encoding="utf-8")
        self.pump(1.5)
        self.assertEqual(self.status()["id"], before, "a 10-minute-old next must not run")
        self.iface.CommandWithQuery("search", "should-not-apply", "some-other-screen")
        self.pump(1.5)
        self.assertNotEqual(self.qml.state().get("searchText"), "should-not-apply")

    def test_06_sync_advance_from_a_peer_monitor(self) -> None:
        before = self.status()["id"]
        tick = json.dumps({"advanceAt": int(time.time() * 1000), "issuer": "peer-monitor"})
        self.iface.WriteTextFile(str(self.cache / f"wallhaven-sync-{NAMESPACE}.json"), tick)
        self.assertTrue(self.wait_for(lambda: self.status().get("id") not in ("", before), 8), "peer tick not followed")
        followed = self.status()["id"]
        # The follower must not rebroadcast, and replaying the tick is a no-op.
        self.pump(2.0)
        self.assertEqual(self.status()["id"], followed, "sync tick echoed into another advance")
        self.assertEqual(
            json.loads((self.cache / f"wallhaven-sync-{NAMESPACE}.json").read_text())["issuer"], "peer-monitor",
        )

    def test_07_wallet_key_stays_in_memory(self) -> None:
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("walletStatus") == "loaded", 10), self.qml.state())
        state = self.qml.state()
        self.assertEqual(state["effectiveApiKey"], API_KEY)
        self.assertEqual(state["configApiKey"], "", "plain-text config copy of the wallet key must be scrubbed")
        self.assertTrue(self.wait_for(lambda: (self.status().get("apiHealth") or {}).get("apiKeyPresent") is True))
        self.assertEqual(self.status()["apiHealth"]["apiKeyLastFour"], API_KEY[-4:])
        # The key is in the wallet (fake) and nowhere on disk under HOME.
        for path in self.home.rglob("*"):
            if path.is_file():
                self.assertNotIn(API_KEY.encode(), path.read_bytes(), f"key leaked to {path}")
        self.assertNotIn(API_KEY, self.bin_log.read_text(encoding="utf-8"), "key leaked into a process argv")
        self.assertFalse((self.cache / "kwallet-apikey.txt").exists())

    def test_08_saving_a_typed_key_moves_it_to_the_wallet(self) -> None:
        new_key = "NewKeyTypedInSettings987654321xyz"
        self.call("saveApiKeyToKWallet", new_key, with_callback=True)
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("effectiveApiKey") == new_key, 8))
        self.assertEqual((self.state_dir / "wallet-apikey").read_text(), new_key)
        self.assertEqual(self.qml.state()["configApiKey"], "")
        self.assertTrue(self.qml.state()["useKWallet"])
        # Sync profiles are stored in the config and must not carry the key.
        self.call("saveSyncProfileForCurrentGroup")
        self.assertTrue(self.wait_for(lambda: NAMESPACE in (self.qml.state().get("syncProfiles") or "")))
        self.assertNotIn(new_key, self.qml.state()["syncProfiles"])
        self.assert_no_qml_errors()

    def test_09_lock_screen_follows_the_wallpaper(self) -> None:
        image_file = self.state_dir / "kconfig/kscreenlockerrc/Greeter/Wallpaper/org.kde.image/General/Image"
        self.send("next")
        self.assertTrue(self.wait_for(lambda: self.status().get("lockScreenSyncOk") is True, 10), self.status())
        wallpaper_id = self.status()["id"]
        self.assertTrue(
            self.wait_for(lambda: image_file.read_text().endswith(f"wallhaven-lockscreen-{wallpaper_id}.jpg"), 10),
            image_file.read_text() if image_file.exists() else "greeter Image never written",
        )
        self.assertTrue((self.cache / "wallhaven-lockscreen-current.jpg").stat().st_size > 0)
        self.assertNotIn("bash", self.bin_log.read_text(encoding="utf-8"))

    def test_10_unlock_triggers_wake_recovery(self) -> None:
        log = self.cache / "wallhaven-debug.log"
        # Let startup publishes settle so the assertions below see this change.
        self.pump(float(os.environ.get("WALLHAVEN_TEST_SETTLE", "0")))
        for saver in (self.screensaver, self.screensaver_legacy):
            saver.active = True
            saver.ActiveChanged(True)
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("screenLocked") is True, 5), "lock signal not seen")
        self.assertTrue(
            self.wait_for(lambda: self.status().get("paused") is True, 5),
            f"PauseWhenInactive ignored: {self.qml.state()}\n{self.qml.tail()}\n"
            + "\n".join(log.read_text(encoding="utf-8").splitlines()[-15:]),
        )
        before = log.read_text(encoding="utf-8").count("recoverAfterWake: unlock")
        for saver in (self.screensaver, self.screensaver_legacy):
            saver.active = False
            saver.ActiveChanged(False)
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("screenLocked") is False, 5))
        self.assertTrue(
            self.wait_for(lambda: log.read_text(encoding="utf-8").count("recoverAfterWake: unlock") > before, 5),
            "unlock did not run wake recovery",
        )
        self.pump(0.5)
        # Both object paths signalled; recovery must have run exactly once.
        self.assertEqual(log.read_text(encoding="utf-8").count("recoverAfterWake: unlock"), before + 1)
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is False, 5), "did not resume after unlock")
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("visible") is True, 10), "blank after unlock")

    def cached_shows(self) -> int:
        log = self.cache / "wallhaven-debug.log"
        return log.read_text(encoding="utf-8").count("Offline mode — showing cached wallpaper.")

    def test_10a_applied_settings_refetch_once(self) -> None:
        # Regression: per-key handlers (onSearchTextChanged, …) never fire for
        # KConfig's capitalized keys, so settings applied in the dialog used to
        # change nothing until the next manual reload.
        self.pump(1.0)
        before = self.cached_shows()
        self.call("__config", {"SearchText": "applied-in-dialog", "Sortings": "toplist", "PuritySketchy": False})
        self.assertTrue(self.wait_for(lambda: self.cached_shows() > before, 5), "applied settings did not refetch")
        self.pump(1.5)
        self.assertEqual(self.cached_shows(), before + 1, "three changed keys must coalesce into one refetch")
        # A setting that does not affect the search must not refetch at all.
        self.call("__config", {"CrossfadeMs": 0, "ShowStatusBanner": True, "AttributionCorner": "top-left"})
        self.pump(1.5)
        self.assertEqual(self.cached_shows(), before + 1)
        self.assert_no_qml_errors()

    def test_10b_liking_a_wallpaper_keeps_it_on_screen(self) -> None:
        self.pump(0.5)
        before = self.cached_shows()
        shown = self.qml.state()["currentWallpaperId"]
        self.call("__set", "_currentTags", "nebula, stars")
        self.call("rateCurrentWallpaper", True)
        self.assertTrue(self.wait_for(lambda: "nebula" in (self.qml.state().get("tagFavorites") or ""), 5))
        self.pump(1.5)
        self.assertEqual(self.cached_shows(), before, "liking must not trigger a refetch")
        self.assertEqual(self.qml.state()["currentWallpaperId"], shown)

    def test_10c_interval_change_applies_immediately(self) -> None:
        self.assertFalse(self.status().get("slideshowActive"))
        self.call("__config", {"RandomInterval": 5})
        self.assertTrue(
            self.wait_for(lambda: self.status().get("slideshowActive") is True
                          and 0 < self.status().get("nextChangeMs", 0) <= 5 * 60 * 1000, 5),
            f"interval change not applied: {self.status().get('nextChangeMs')}",
        )
        self.call("__config", {"RandomInterval": 0})
        self.assertTrue(self.wait_for(lambda: self.status().get("slideshowActive") is False, 5))

    def test_10d_offline_mode_uses_cached_tags(self) -> None:
        # Cache-only modes must not look tags up online; the ones stored with
        # the cached file are used instead.
        for wallpaper_id in CACHE_IDS:
            self.call("setCacheEntryTags", wallpaper_id, f"tags-of-{wallpaper_id}")
        self.send("next")
        self.assertTrue(
            self.wait_for(lambda: self.status().get("tags") == f"tags-of-{self.status().get('id')}", 8),
            f"id={self.status().get('id')} tags={self.status().get('tags')!r}",
        )

    def test_11_every_control_command_runs_without_errors(self) -> None:
        # Commands that would open a browser or hit the network are left out
        # (open, like/dislike, testkey, importpreset, warm, trip).
        for cmd, query in (
            ("pin", ""), ("unpin", ""), ("copyid", ""), ("copyurl", ""), ("copytags", ""), ("info", ""),
            ("prune", ""), ("cancelwarm", ""), ("savesearch", "runtime-test"), ("applysearch", "runtime-test"),
            ("purity", "110"), ("undo", ""), ("history", CACHE_IDS[0]), ("outageoffline", ""),
            ("resumeonline", ""), ("endtrip", ""), ("copysearch", "nebula"), ("search", "mountains"),
            ("reload", ""), ("pause", ""), ("resume", ""), ("block", ""), ("clearkey", ""),
        ):
            self.send(cmd, query)
            self.pump(0.35)
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("searchText") == "mountains", 5))
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("effectiveApiKey") == "", 5), "clearkey ignored")
        self.assert_no_qml_errors()

    def test_12_settings_dialog_entry_points(self) -> None:
        entries = self.call("getCacheEntries")
        self.assertTrue(entries, "cache entries visible to the settings dialog")
        self.call("pinCacheId", CACHE_IDS[1])
        self.assertTrue(any(e.get("pinned") for e in self.call("getCacheEntries")))
        self.call("unpinCacheId", CACHE_IDS[1])
        self.call("setCacheEntryTags", CACHE_IDS[1], "sky, clouds")
        self.call("refreshMonitorTrustMap")
        self.call("copyDebugInfo")
        self.call("showDebugLogTail")
        self.call("applyLaptopMode")
        self.call("applyDesktopMode")
        self.call("clearSeenHistory")
        self.call("clearWallpaperHistory")
        self.call("exportSettingsToFile", str(self.home / "export.json"))
        self.assertTrue(self.wait_for(lambda: (self.home / "export.json").exists(), 5), "settings export not written")
        self.assertNotIn(API_KEY, (self.home / "export.json").read_text())
        self.call("evictCacheId", CACHE_IDS[3])
        self.assertTrue(self.wait_for(
            lambda: not (self.cache / f"wallhaven-cache-{NAMESPACE}-03.jpg").exists(), 5), "evicted file not removed")
        self.call("clearDiskCache")
        self.assertTrue(self.wait_for(lambda: not list(self.cache.glob("wallhaven-cache-*.jpg")), 8))
        self.pump(0.5)
        self.assert_no_qml_errors()

    def test_13_log_is_clean_at_the_end(self) -> None:
        self.pump(1.0)
        self.assert_no_qml_errors()
        self.assertIsNone(self.qml.proc.poll(), "qml runtime exited unexpectedly")


class PollingFallbackTests(RuntimeBase):
    """Plasma without SignalWatcher: BusSignals.qml fails to load, polling takes over."""

    config_overrides = dict(WallpaperRuntimeTests.config_overrides, ApiKey="", UseKWalletForApiKey=False)

    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        cls.seed_cache()
        cls.prepare_stubs()
        ui = cls.tmp / "contents" / "ui"
        shutil.copytree(ROOT / "contents", cls.tmp / "contents")
        (ui / "BusSignals.qml").write_text(
            "import QtQuick\nimport BusSignals.unavailable.on.purpose\nItem {}\n", encoding="utf-8",
        )
        cls.start_wallpaper(ui)

    def test_wallpaper_still_obeys_commands(self) -> None:
        self.assertTrue(self.wait_for(lambda: self.qml.has("HARNESS-READY"), 20), self.qml.tail())
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("visible") is True, 15), self.qml.state())
        self.assertIs(self.qml.state()["busSignalsActive"], False)
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("dbusServiceAvailable") is True, 10))
        self.send("pause")
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is True, 5), "poll fallback missed pause")
        self.send("resume")
        self.assertTrue(self.wait_for(lambda: self.status().get("paused") is False, 5))
        errors = [e for e in self.qml.errors() if "BusSignals" not in e and "unavailable.on.purpose" not in e]
        self.assertFalse(errors, "\n".join(errors[:40]))


class SettingsDialogRuntimeTests(RuntimeBase):
    """config.qml loads next to a running wallpaper and sees the wallet-held key."""

    wallet_key = API_KEY
    config_overrides = dict(WallpaperRuntimeTests.config_overrides, ApiKey="")

    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        cls.seed_cache()
        cls.prepare_stubs()
        harness = cls.tmp / "settings-harness.qml"
        cls.call_file = cls.tmp / "harness-call.json"
        cls.call_file.write_text("", encoding="utf-8")
        ui = ROOT / "contents" / "ui"
        harness.write_text(SETTINGS_HARNESS % {
            "main_url": (ui / "main.qml").as_uri(),
            "config_url": (ui / "config.qml").as_uri(),
            "call_url": cls.call_file.as_uri(),
        }, encoding="utf-8")
        cls.qml = QmlProcess(
            [QML_HOST_PYTHON, str(QML_HOST), str(harness), str(cls.stubs), str(cls.config_file)], cls.env,
        )

    def test_dialog_loads_and_uses_the_wallet_key(self) -> None:
        self.assertTrue(self.wait_for(lambda: self.qml.has("HARNESS-READY"), 30), self.qml.tail())
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("hasLiveWallpaper") is True, 10), self.qml.state())
        # The key lives in the wallet: the field is empty, yet "Test API key",
        # collection loading and test searches still have a key to use.
        self.assertTrue(
            self.wait_for(lambda: self.qml.state().get("dialogEffectiveKey") == API_KEY, 10), self.qml.state(),
        )
        self.assertEqual(self.qml.state()["dialogApiKeyField"], "")
        # Helper availability comes from the running wallpaper, without pinging.
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("dialogPollCompleted") is True, 5))
        self.assertIs(self.qml.state()["dialogServiceOnline"], True)
        # A key typed into the field wins over the wallet copy.
        self.call("__setDialog", "cfg_ApiKey", "TypedKeyInTheDialog0123456789")
        self.assertTrue(
            self.wait_for(lambda: self.qml.state().get("dialogEffectiveKey") == "TypedKeyInTheDialog0123456789", 5),
        )
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("previewWallpaperId") in CACHE_IDS, 10))
        self.pump(1.0)
        if os.environ.get("WALLHAVEN_TEST_DUMP_LOG") == "1":
            print(self.qml.tail(200))
        self.assert_no_qml_errors()


class PlasmoidRuntimeTests(RuntimeBase):
    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        cls.prepare_stubs()
        cls.iface.PublishMonitorStatusJson(NAMESPACE, json.dumps({
            "id": "aaa111", "paused": False, "slideshowActive": True, "nextChangeMs": 60000,
            "syncGroup": NAMESPACE, "cacheNamespace": NAMESPACE, "screenName": NAMESPACE,
            "statusUpdatedAtMs": int(time.time() * 1000),
        }))
        harness = cls.tmp / "plasmoid-harness.qml"
        harness.write_text(PLASMOID_HARNESS % {
            "main_url": (ROOT / "plasmoid" / "contents" / "ui" / "main.qml").as_uri(),
        }, encoding="utf-8")
        cls.qml = QmlProcess(
            [QML_HOST_PYTHON, str(QML_HOST), str(harness), str(cls.stubs), str(cls.config_file)], cls.env,
        )

    def test_plasmoid_loads_and_follows_status_signals(self) -> None:
        self.assertTrue(self.wait_for(lambda: self.qml.has("HARNESS-READY"), 20), self.qml.tail())
        self.assertTrue(self.wait_for(lambda: self.qml.has("HARNESS-FULL-READY"), 10), self.qml.tail())
        self.assertTrue(self.wait_for(lambda: self.qml.has("HARNESS-COMPACT-READY"), 10))
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("id") == "aaa111", 8), self.qml.state())
        self.assertIs(self.qml.state()["signalsActive"], True)
        self.assertIs(self.qml.state()["dbusOffline"], False)
        started = time.time()
        self.iface.PublishMonitorStatusJson(NAMESPACE, json.dumps({
            "id": "bbb222", "paused": True, "slideshowActive": True, "nextChangeMs": 0,
            "syncGroup": NAMESPACE, "cacheNamespace": NAMESPACE, "screenName": NAMESPACE,
            "statusUpdatedAtMs": int(time.time() * 1000),
        }))
        self.assertTrue(self.wait_for(lambda: self.qml.state().get("id") == "bbb222", 5), self.qml.state())
        self.assertLess(time.time() - started, 2.0)
        self.assertIs(self.qml.state()["paused"], True)
        self.assertEqual(self.qml.errors(), [])


if __name__ == "__main__":
    unittest.main(warnings="ignore", failfast=False)
