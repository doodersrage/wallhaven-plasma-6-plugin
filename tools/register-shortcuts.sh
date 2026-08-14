#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Wallhaven desktop actions are available from:
  Right-click desktop → Wallpaper Actions

Plasma does not expose global shortcuts for QML wallpapers directly.
To bind keys manually, create Custom Shortcuts that run:

  Next wallpaper:
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
      'var allDesktops = desktops();for (var i = 0; i < allDesktops.length; i++) {d = allDesktops[i];d.wallpaperPlugin = "org.robertsm.wallhaven"}'

For reliable global shortcuts, use System Settings → Shortcuts → Custom Shortcuts
and trigger the same Wallpaper Actions menu items if your Plasma version supports it.

Recommended keys (configure manually):
  Next wallpaper      → Meta+Alt+Right
  Previous wallpaper  → Meta+Alt+Left
  Pause slideshow     → Meta+Alt+P
EOF
