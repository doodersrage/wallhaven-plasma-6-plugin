# Control Wallhaven from Plasma

Three ways to drive the wallpaper without opening System Settings.

## Panel plasmoid

Add **Wallhaven Control** to the panel:

- Thumbnail (local cache when available) — **click** to open the Wallhaven page, **drag right/left** to like/dislike its tags
- **History** button — popup scrubber of the last dozen wallpapers, click one to bring it back
- Search field with recent-query chips and saved-search Apply/Save
- Purity toggles (SFW / Sketchy / NSFW), trip-mode banner, auth/outage warnings
- Countdown + pause state
- Previous / next / pause / reload, plus copy ID/URL, warm/prune cache, trip mode, undo
- Menu: like/dislike, similar wallpapers, wallpaper info, recent history, copy tags, block, D-Bus offline help

## Global keyboard shortcuts

Requires D-Bus service (`./dev-helper.sh dbus-install`) and a one-time build:

```bash
sudo pacman -S extra-cmake-modules   # Arch; see packaging/README.md for other distros
./dev-helper.sh install-shortcuts
```

| Shortcut | Action |
|----------|--------|
| Meta+Ctrl+Alt+Right | Next wallpaper |
| Meta+Ctrl+Alt+Left | Previous wallpaper |
| Meta+Ctrl+Alt+P | Pause / resume slideshow |
| Meta+Ctrl+Alt+R | Reload |

Log out and back in if shortcuts do not register immediately.

Before the next release these were Meta+Alt+…, which clashes with KWin's *Switch Window* and Plasma's *cycle panels*. The helper moves those old defaults to Meta+Ctrl+Alt on its next start; bindings you changed yourself are kept. Rebind any of them in **System Settings → Shortcuts → wallhaven-shortcuts**.

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
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandWithQuery applysearch "My preset" default
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandWithQuery purity "sfw,sketchy" default
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandWithQuery trip 24 default
./tools/wallhaven-ctl.sh like
./tools/wallhaven-ctl.sh history abc123
./tools/wallhaven-ctl.sh applysearch "My preset"
./tools/wallhaven-ctl.sh purity sfw,sketchy
./tools/wallhaven-ctl.sh trip 24
./tools/wallhaven-ctl.sh copyid
```

Query-bearing commands use `CommandWithQuery` (or `Search` for plain search). Simple commands use `CommandInGroup`.

MPRIS media keys work via `org.mpris.MediaPlayer2.wallhaven`. Wallhaven also *reads* any other running MPRIS player (Spotify, VLC, …) when **Music-reactive pacing** is enabled, to speed up the Ken Burns pan while music is playing.


## 3.5 commands

- `cancelwarm` — stop an in-progress cache warm
- `copysearch [query]` — push search to other monitor sync groups

## Which monitor receives a command

Each screen listens on its own sync group (its output name, e.g. `DP-1`).
Commands sent to the `default` group (the CLI, KRunner, and MPRIS without
`WALLHAVEN_SYNC_GROUP`) are routed like this:

- `next` / `prev` / `pause` / `resume` / `reload` — every monitor
- everything else (`search`, `like`, `block`, `info`, `copyid`, `purity`, …) — the **primary** screen

Target a specific monitor with `WALLHAVEN_SYNC_GROUP=DP-2 ./tools/wallhaven-ctl.sh like`.
