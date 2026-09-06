#!/usr/bin/env python3
"""Regression tests for multi-monitor control-bus fan-out isolation."""

from __future__ import annotations

import importlib.util
import json
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


if __name__ == "__main__":
    unittest.main()
