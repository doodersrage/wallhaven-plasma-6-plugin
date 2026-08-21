#!/usr/bin/env python3
"""Unit tests for Variety parsing helpers in wallhaven-dbus.py."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

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


class UpscalerAvailabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_find_upscaler_missing(self) -> None:
        original = self.mod.shutil.which
        self.mod.shutil.which = lambda _name: None
        try:
            self.assertEqual(self.mod.find_upscaler(), "")
        finally:
            self.mod.shutil.which = original

    def test_find_upscaler_present(self) -> None:
        original = self.mod.shutil.which
        self.mod.shutil.which = lambda name: (
            "/usr/bin/realesrgan-ncnn-vulkan" if name == self.mod.UPSCALER_BINARY else None
        )
        try:
            self.assertEqual(self.mod.find_upscaler(), "/usr/bin/realesrgan-ncnn-vulkan")
        finally:
            self.mod.shutil.which = original


class VarietyParseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_parse_preferences_search(self) -> None:
        ini = "[preferences]\nimage_fetch_search = nature landscape\n"
        self.assertEqual(self.mod.parse_variety_search(ini), "nature landscape")

    def test_parse_empty(self) -> None:
        self.assertEqual(self.mod.parse_variety_search(""), "")

    def test_parse_ignores_other_sections(self) -> None:
        ini = "[other]\nimage_fetch_search = ignored\n[preferences]\nimage_fetch_search = anime\n"
        self.assertEqual(self.mod.parse_variety_search(ini), "anime")


if __name__ == "__main__":
    unittest.main()
