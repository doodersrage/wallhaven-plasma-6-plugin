# Control Wallhaven from Plasma

Three ways to drive the wallpaper without opening System Settings.

## Panel plasmoid

Add **Wallhaven Control** to the panel:

- Thumbnail (local cache when available) — **click** to open the Wallhaven page, **drag right/left** to like/dislike its tags
- **History** button — popup scrubber of the last dozen wallpapers, click one to bring it back
- Countdown + pause state
- Previous / next / pause / reload buttons
- Menu: like/dislike, similar wallpapers, copy tags, block, D-Bus offline help

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
- `wh like` / `wh dislike` — boost or mute the current wallpaper's tags

## D-Bus (automation)

With `wallhaven-dbus.service` running:

```bash
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup next default
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Search "nature" default
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandWithQuery history abc123 default
./tools/wallhaven-ctl.sh like
./tools/wallhaven-ctl.sh history abc123
```

MPRIS media keys work via `org.mpris.MediaPlayer2.wallhaven`. Wallhaven also *reads* any other running MPRIS player (Spotify, VLC, …) when **Music-reactive pacing** is enabled, to speed up the Ken Burns pan while music is playing.
