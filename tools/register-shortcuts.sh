#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Wallhaven global shortcuts
==========================

Recommended: bind keys to tools/wallhaven-ctl.sh (uses the control bus file).

  Meta+Alt+Right  →  wallhaven-ctl.sh next
  Meta+Alt+Left   →  wallhaven-ctl.sh prev
  Meta+Alt+P      →  wallhaven-ctl.sh pause
  Meta+Alt+R      →  wallhaven-ctl.sh reload

System Settings → Shortcuts → Custom Shortcuts → Edit → New → Command
  Command: /full/path/to/wallhaven-plasma-6-plugin/tools/wallhaven-ctl.sh next

Optional D-Bus service (session bus):
  python3 tools/wallhaven-dbus.py &
  qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Command next

Desktop actions (no global key needed):
  Right-click desktop → Wallpaper Actions

Panel widget:
  Add "Wallhaven Control" to panel for thumb + countdown + buttons.
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTL="${SCRIPT_DIR}/wallhaven-ctl.sh"

if [[ ! -x "${CTL}" ]]; then
    chmod +x "${CTL}" 2>/dev/null || true
fi

if command -v kwriteconfig6 >/dev/null 2>&1; then
    echo ""
    echo "Example custom shortcut entries (adjust paths):"
    echo "  ${CTL} next"
    echo "  ${CTL} prev"
fi
