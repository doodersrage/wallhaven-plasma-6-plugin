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


class ListImageFilesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def test_list_respects_depth_and_exclude(self) -> None:
        import tempfile
        from pathlib import Path

        home = Path.home()
        with tempfile.TemporaryDirectory(dir=home) as tmp:
            root = Path(tmp)
            (root / "keep.jpg").write_bytes(b"x")
            nested = root / "deep" / "nested"
            nested.mkdir(parents=True)
            (nested / "skip.jpg").write_bytes(b"x")
            thumbs = root / "thumbs"
            thumbs.mkdir()
            (thumbs / "no.jpg").write_bytes(b"x")
            shallow = self.mod.list_image_files_under(
                str(root),
                '{"maxDepth": 0, "exclude": "thumbs"}',
            )
            paths = __import__("json").loads(shallow)
            self.assertEqual(len(paths), 1)
            self.assertTrue(paths[0].endswith("keep.jpg"))
            deep = self.mod.list_image_files_under(
                str(root),
                '{"maxDepth": 3, "exclude": "thumbs"}',
            )
            deep_paths = __import__("json").loads(deep)
            self.assertEqual(len(deep_paths), 2)


if __name__ == "__main__":
    unittest.main()
