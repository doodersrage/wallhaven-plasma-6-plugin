# Control Wallhaven from Plasma

Three ways to drive the wallpaper without opening System Settings.

## Panel plasmoid

Add **Wallhaven Control** to the panel:

- Thumbnail (local cache when available) — **click** to open the Wallhaven page
- Countdown + pause state
- Previous / next / pause / reload buttons
- Menu: similar wallpapers, copy tags, block, D-Bus offline help

## Global keyboard shortcuts

Requires D-Bus service (`./dev-helper.sh dbus-install`) and a one-time build:

```bash
sudo pacman -S extra-cmake-modules   # Arch; see packaging/README.md for other distros
./dev-helper.sh install-shortcuts
```

| Shortcut | Action |
|----------|--------|
| Meta+Alt+Right | Next wallpaper |
| Meta+Alt+Left | Previous wallpaper |
| Meta+Alt+P | Pause / resume slideshow |
| Meta+Alt+R | Reload |

Log out and back in if shortcuts do not register immediately.

Fallback without building: **System Settings → Shortcuts → Custom Shortcuts** using `wallhaven-ctl.sh` (see `examples/plasma-shortcuts.md`).

## KRunner

Enable **Wallhaven** in System Settings → Search → Plasma Search.

Examples:

- `wh next` — next wallpaper
- `wallhaven search anime city` — apply search
- `wallhaven block` — block current wallpaper

## D-Bus (automation)

With `wallhaven-dbus.service` running:

```bash
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup next default
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Search "nature" default
```

MPRIS media keys work via `org.mpris.MediaPlayer2.wallhaven`.
