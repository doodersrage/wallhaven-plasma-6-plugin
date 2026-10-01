#!/usr/bin/env python3
"""Minimal QML host for tests/test-qml-runtime.py.

Plays the part of plasmashell: it loads a harness QML file and hands the
wallpaper a `configuration` object. That object is a real QQmlPropertyMap, the
base class of Plasma's KConfigPropertyMap, so it behaves the same way where it
matters: capitalized keys drive bindings, but per-key `onFooChanged` handlers
on it are never called.

usage: qml-host.py <harness.qml> <import-path> <config.json>
"""

from __future__ import annotations

import json
import sys

try:
    from PyQt6.QtCore import QUrl
    from PyQt6.QtGui import QGuiApplication
    from PyQt6.QtQml import QQmlApplicationEngine, QQmlPropertyMap
except ImportError:
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine, QQmlPropertyMap


def main() -> int:
    harness, import_path, config_path = sys.argv[1:4]
    app = QGuiApplication(sys.argv[:1])
    # StandardPaths.CacheLocation follows the application name; the wallpaper
    # keeps its files in ~/.cache/plasmashell.
    app.setOrganizationName("")
    app.setOrganizationDomain("")
    app.setApplicationName("plasmashell")

    config = QQmlPropertyMap()
    with open(config_path, encoding="utf-8") as handle:
        for key, value in json.load(handle).items():
            config.insert(key, value)

    engine = QQmlApplicationEngine()
    engine.addImportPath(import_path)
    engine.rootContext().setContextProperty("wallhavenTestConfig", config)
    engine.load(QUrl.fromLocalFile(harness))
    if not engine.rootObjects():
        print("HARNESS-LOAD-ERROR (harness itself failed to load)", file=sys.stderr, flush=True)
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
