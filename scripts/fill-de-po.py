#!/usr/bin/env python3
"""Deprecated: use scripts/fill-po.py for all locales."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
raise SystemExit(subprocess.call([sys.executable, str(ROOT / "fill-po.py"), *sys.argv[1:]]))
