#!/usr/bin/env python3
"""Live tests for wallhaven-dbus.py on a private session bus.

The service runs against a throwaway HOME/cache with fake kwallet-query,
kwriteconfig6, kreadconfig6 and curl on PATH, so nothing here touches the real
wallet, kscreenlockerrc, network, or the user's running wallpaper.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import warnings
from pathlib import Path

# PyGObject's asyncio glue is noisy on new Pythons; not ours to fix.
warnings.filterwarnings("ignore", category=DeprecationWarning)

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "tools" / "wallhaven-dbus.py"
BUS_NAME = "org.robertsm.Wallhaven"
IFACE = "org.robertsm.Wallhaven"
API_KEY = "Zx9TestKeyNeverReal0123456789abcd"

if os.environ.get("WALLHAVEN_TEST_PRIVATE_BUS") != "1":
    # Re-exec under a private bus so the real session service is never involved.
    if not shutil.which("dbus-run-session"):
        print("SKIP: dbus-run-session not installed")
        sys.exit(0)
    env = dict(os.environ, WALLHAVEN_TEST_PRIVATE_BUS="1")
    sys.exit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__, *sys.argv[1:]], env=env))

import dbus  # noqa: E402
from dbus.mainloop.glib import DBusGMainLoop  # noqa: E402
from gi.repository import GLib  # noqa: E402

FAKE_KWALLET = """#!/usr/bin/env bash
# args: -r|-w <entry> -f <folder> <wallet>
echo "$*" >> "$FAKE_BIN_LOG"
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

# curl -fsSL --max-time N -o <out> <url>
FAKE_CURL = """#!/usr/bin/env bash
sleep 2
printf 'image' > "$5"
"""

GREETER_IMAGE_DIR = "kscreenlockerrc/Greeter/Wallpaper/org.kde.image/General"


class ServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        DBusGMainLoop(set_as_default=True)
        cls.tmp = Path(tempfile.mkdtemp(prefix="wallhaven-dbus-test-"))
        cls.home = cls.tmp / "home"
        cls.cache = cls.home / ".cache" / "plasmashell"
        cls.state = cls.tmp / "state"
        cls.bin = cls.tmp / "bin"
        cls.bin_log = cls.tmp / "bin.log"
        for d in (cls.cache, cls.state, cls.bin):
            d.mkdir(parents=True)
        for name, body in (
            ("kwallet-query", FAKE_KWALLET),
            ("kwriteconfig6", FAKE_KWRITECONFIG),
            ("kreadconfig6", FAKE_KREADCONFIG),
            ("curl", FAKE_CURL),
        ):
            path = cls.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
        # Plaintext copy written by builds before 3.7; the service must remove it.
        (cls.cache / "kwallet-apikey.txt").write_text("leaked-key", encoding="utf-8")
        (cls.cache / "wallhaven-dbus-write.log").write_bytes(b"x" * (2 * 1024 * 1024))

        env = dict(
            os.environ,
            HOME=str(cls.home),
            XDG_CACHE_HOME=str(cls.home / ".cache"),
            XDG_CONFIG_HOME=str(cls.home / ".config"),
            PATH=f"{cls.bin}:{os.environ.get('PATH', '')}",
            FAKE_STATE=str(cls.state),
            FAKE_BIN_LOG=str(cls.bin_log),
        )
        cls.proc = subprocess.Popen(
            [sys.executable, str(SERVICE)], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        cls.bus = dbus.SessionBus()
        deadline = time.time() + 10
        while time.time() < deadline and not cls.bus.name_has_owner(BUS_NAME):
            if cls.proc.poll() is not None:
                raise RuntimeError("service exited early:\n" + (cls.proc.stdout.read() or ""))
            time.sleep(0.05)
        if not cls.bus.name_has_owner(BUS_NAME):
            raise RuntimeError("service did not claim its bus name")
        cls.obj = cls.bus.get_object(BUS_NAME, "/Wallhaven")
        cls.iface = dbus.Interface(cls.obj, IFACE)
        cls.signals: list[tuple[str, tuple]] = []
        for name in ("ControlChanged", "SyncAdvanced", "StatusChanged"):
            cls.bus.add_signal_receiver(
                lambda *args, _name=name: cls.signals.append((_name, tuple(str(a) for a in args))),
                signal_name=name, dbus_interface=IFACE, bus_name=BUS_NAME,
            )
        # Let the service's directory monitor settle before the first write.
        cls.pump(0.3)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.proc.terminate()
        try:
            cls.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.proc.kill()
        if cls.proc.stdout is not None:
            cls.proc.stdout.close()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @staticmethod
    def pump(seconds: float) -> None:
        ctx = GLib.MainContext.default()
        end = time.time() + seconds
        while time.time() < end:
            while ctx.pending():
                ctx.iteration(False)
            time.sleep(0.01)

    def wait_for(self, predicate, timeout: float = 5.0) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.05)
            if predicate():
                return True
        return False

    def signals_named(self, name: str) -> list[tuple]:
        return [args for sig, args in self.signals if sig == name]

    def setUp(self) -> None:
        self.pump(0.15)
        self.signals.clear()

    # --- startup housekeeping

    def test_startup_removes_plaintext_key_and_oversized_log(self) -> None:
        self.assertFalse((self.cache / "kwallet-apikey.txt").exists())
        self.assertFalse((self.cache / "wallhaven-dbus-write.log").exists())

    def test_successful_writes_are_not_logged(self) -> None:
        for i in range(20):
            self.iface.WriteTextFile(str(self.cache / "wallhaven-panel-tint.json"), f"{{\"n\":{i}}}")
        self.assertFalse((self.cache / "wallhaven-dbus-write.log").exists())
        with self.assertRaises(dbus.exceptions.DBusException):
            self.iface.WriteTextFile("/etc/wallhaven-nope", "x")
        self.assertIn("REJECT", (self.cache / "wallhaven-dbus-write.log").read_text())

    # --- KWallet

    def test_api_key_round_trip_never_touches_disk_or_argv(self) -> None:
        self.assertEqual(str(self.iface.GetApiKey()), "")
        self.assertEqual(str(self.iface.SetApiKey(API_KEY)), "ok")
        self.assertEqual(str(self.iface.GetApiKey()), API_KEY)
        log = self.bin_log.read_text(encoding="utf-8")
        self.assertIn("-w apikey -f org.robertsm.wallhaven kdewallet", log)
        self.assertNotIn(API_KEY, log, "key must be piped on stdin, not passed as an argument")
        for path in self.home.rglob("*"):
            if path.is_file():
                self.assertNotIn(
                    API_KEY.encode(), path.read_bytes(), f"key leaked to {path}",
                )

    def test_set_api_key_rejects_junk(self) -> None:
        for junk in ("", "two words", "line\nbreak"):
            with self.assertRaises(dbus.exceptions.DBusException):
                self.iface.SetApiKey(junk)

    # --- shell is gone

    def test_run_argv_has_no_shell(self) -> None:
        for argv in (
            ["bash", "-lc", "true"],
            ["sh", "-c", "true"],
            ["kwallet-query", "-r", "apikey", "-f", "org.robertsm.wallhaven", "kdewallet"],
            ["kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key", "X", "1"],
        ):
            with self.assertRaises(dbus.exceptions.DBusException, msg=str(argv)):
                self.iface.RunArgv(json.dumps(argv))

    def test_slow_command_does_not_block_the_service(self) -> None:
        out = self.cache / "wallhaven-cache-slow.jpg"
        argv = ["curl", "-fsSL", "--max-time", "30", "-o", str(out), "https://w.wallhaven.cc/full/ab/x.jpg"]
        done: list[str] = []
        self.iface.RunArgv(
            json.dumps(argv),
            reply_handler=lambda r: done.append(str(r)),
            error_handler=lambda e: done.append(f"error:{e}"),
        )
        started = time.time()
        self.assertEqual(str(self.iface.Ping()), "ok")
        self.assertLess(time.time() - started, 1.0, "Ping waited for the slow download")
        self.assertEqual(done, [], "download should still be running")
        self.assertTrue(self.wait_for(lambda: bool(done), timeout=8))
        self.assertEqual(done, ["ok"])
        self.assertEqual(out.read_text(), "image")

    def test_stat_cache_files(self) -> None:
        a = self.cache / "wallhaven-cache-a.jpg"
        a.write_bytes(b"12345")
        missing = self.cache / "wallhaven-cache-missing.jpg"
        sizes = json.loads(str(self.iface.StatCacheFiles(json.dumps([str(a), str(missing), "/etc/passwd"]))))
        self.assertEqual(sizes[str(a)], 5)
        self.assertEqual(sizes[str(missing)], 0)
        self.assertEqual(sizes["/etc/passwd"], 0)

    # --- signals

    def test_command_emits_control_changed_once(self) -> None:
        self.iface.CommandInGroup("next", "DP-9")
        self.assertTrue(self.wait_for(lambda: bool(self.signals_named("ControlChanged"))))
        self.pump(0.6)  # directory monitor reports the same write; must not re-emit
        events = self.signals_named("ControlChanged")
        self.assertEqual(len(events), 1, events)
        payload = json.loads(events[0][0])
        self.assertEqual((payload["cmd"], payload["group"]), ("next", "DP-9"))

    def test_external_control_write_emits_signal(self) -> None:
        payload = json.dumps({"cmd": "pause", "ts": int(time.time() * 1000), "group": "DP-9"})
        (self.cache / "wallhaven-control.json").write_text(payload, encoding="utf-8")
        self.assertTrue(
            self.wait_for(lambda: bool(self.signals_named("ControlChanged"))),
            "a file written by wallhaven-ctl.sh must still reach the wallpaper",
        )
        self.pump(0.6)
        events = self.signals_named("ControlChanged")
        self.assertEqual(len(events), 1, events)
        self.assertEqual(json.loads(events[0][0])["cmd"], "pause")

    def test_sync_file_write_emits_sync_advanced(self) -> None:
        body = json.dumps({"advanceAt": int(time.time() * 1000), "issuer": "abc"})
        self.iface.WriteTextFile(str(self.cache / "wallhaven-sync-living-room.json"), body)
        self.assertTrue(self.wait_for(lambda: bool(self.signals_named("SyncAdvanced"))))
        self.pump(0.6)
        events = self.signals_named("SyncAdvanced")
        self.assertEqual(events, [("living-room", body)])

    def test_status_publish_emits_status_changed(self) -> None:
        self.iface.PublishMonitorStatusJson("DP-9", '{"id":"abc"}')
        self.iface.PublishStatusJson('{"id":"abc"}')
        self.assertTrue(self.wait_for(lambda: len(self.signals_named("StatusChanged")) >= 2))
        self.assertEqual(
            self.signals_named("StatusChanged"), [("DP-9", '{"id":"abc"}'), ("", '{"id":"abc"}')],
        )
        self.assertEqual(json.loads(str(self.iface.GetStatus()))["id"], "abc")

    # --- lock screen

    def greeter_value(self, key: str) -> str:
        path = self.state / "kconfig" / GREETER_IMAGE_DIR / key
        return path.read_text() if path.exists() else ""

    def reset_lock_state(self) -> None:
        shutil.rmtree(self.state / "kconfig", ignore_errors=True)
        for path in self.cache.glob("wallhaven-lockscreen*"):
            path.unlink()

    def test_lock_screen_sync_and_ensure(self) -> None:
        self.reset_lock_state()
        src = self.cache / "wallhaven-cache-07.jpg"
        src.write_bytes(b"wallpaper-bytes")
        dest = self.cache / "wallhaven-lockscreen-abc123.jpg"
        stale = self.cache / "wallhaven-lockscreen-old999.jpg"
        stale.write_bytes(b"old")
        old = time.time() - 3600
        os.utime(stale, (old, old))

        self.assertEqual(str(self.iface.SyncLockScreen(str(src), str(dest))), "ok")
        self.assertEqual(dest.read_bytes(), b"wallpaper-bytes")
        current = self.cache / "wallhaven-lockscreen-current.jpg"
        self.assertEqual(current.read_bytes(), b"wallpaper-bytes")
        self.assertEqual(self.greeter_value("Image"), f"file://{dest}")
        self.assertEqual(self.greeter_value("PreviewImage"), f"file://{dest}")
        self.assertEqual(self.greeter_value("FillMode"), "2")
        self.assertEqual(
            (self.state / "kconfig/kscreenlockerrc/Greeter/WallpaperPlugin").read_text(), "org.kde.image",
        )
        self.assertFalse(stale.exists(), "copies older than 30 min are pruned")

        # Fresh greeter image: ensure only refreshes the mirror.
        self.assertEqual(str(self.iface.EnsureLockScreen()), "ok")
        self.assertEqual(self.greeter_value("Image"), f"file://{dest}")

        # Greeter points at a file that vanished: repair from the mirror.
        dest.unlink()
        self.assertEqual(str(self.iface.EnsureLockScreen()), "ok")
        repaired = normalize(self.greeter_value("Image"))
        self.assertRegex(os.path.basename(repaired), r"^wallhaven-lockscreen-repaired-\d+\.jpg$")
        self.assertEqual(Path(repaired).read_bytes(), b"wallpaper-bytes")

    def test_lock_screen_sync_rejects_bad_paths(self) -> None:
        src = self.cache / "wallhaven-cache-07.jpg"
        src.write_bytes(b"x")
        for dest in (
            str(self.home / "elsewhere.jpg"),
            str(self.cache / "wallhaven-cache-00.jpg"),
            str(self.cache / "wallhaven-lockscreen-a b.jpg"),
        ):
            with self.assertRaises(dbus.exceptions.DBusException, msg=dest):
                self.iface.SyncLockScreen(str(src), dest)
        with self.assertRaises(dbus.exceptions.DBusException):
            self.iface.SyncLockScreen("/etc/passwd", str(self.cache / "wallhaven-lockscreen-x.jpg"))

    def test_ensure_leaves_users_own_lock_wallpaper_alone(self) -> None:
        self.reset_lock_state()
        (self.cache / "wallhaven-lockscreen-current.jpg").write_bytes(b"mirror")
        own = self.home / "Pictures" / "my-lock.jpg"
        own.parent.mkdir(parents=True, exist_ok=True)
        own.write_bytes(b"mine")
        old = time.time() - 3600
        os.utime(own, (old, old))
        image_dir = self.state / "kconfig" / GREETER_IMAGE_DIR
        image_dir.mkdir(parents=True)
        (image_dir / "Image").write_text(f"file://{own}")
        self.assertEqual(str(self.iface.EnsureLockScreen()), "skip:foreign-image")
        self.assertEqual(self.greeter_value("Image"), f"file://{own}")

        # Another lock-screen wallpaper plugin: not ours to switch back to an image.
        (image_dir / "Image").unlink()
        plugin = self.state / "kconfig/kscreenlockerrc/Greeter/WallpaperPlugin"
        plugin.write_text("org.kde.potd")
        self.assertEqual(str(self.iface.EnsureLockScreen()), "skip:foreign-plugin")
        self.assertEqual(plugin.read_text(), "org.kde.potd")

    def test_ensure_without_any_copy_fails_quietly(self) -> None:
        self.reset_lock_state()
        self.assertEqual(str(self.iface.EnsureLockScreen()), "fail:no-source")
        self.assertEqual(self.greeter_value("Image"), "")

    # --- variety / accent

    def test_link_variety_current(self) -> None:
        src = self.cache / "wallhaven-cache-07.jpg"
        src.write_bytes(b"x")
        folder = self.home / "Pictures" / "variety o'clock"
        self.assertEqual(str(self.iface.LinkVarietyCurrent(str(folder), str(src))), "ok")
        link = folder / "wallhaven-current.jpg"
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), str(src))
        with self.assertRaises(dbus.exceptions.DBusException):
            self.iface.LinkVarietyCurrent("/etc/wallhaven", str(src))

    def test_sync_system_accent(self) -> None:
        self.assertEqual(str(self.iface.SyncSystemAccent("12,34,56", "")), "ok")
        self.assertEqual(
            (self.state / "kconfig/kdeglobals/General/AccentColor").read_text(), "12,34,56",
        )
        for bad in ("12,34", "1,2,3; rm -rf ~", "999,0,0"):
            with self.assertRaises(dbus.exceptions.DBusException, msg=bad):
                self.iface.SyncSystemAccent(bad, "")


def normalize(url: str) -> str:
    return url[len("file://"):] if url.startswith("file://") else url


if __name__ == "__main__":
    unittest.main(warnings="ignore")
