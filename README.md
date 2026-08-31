# Wallhaven — KDE Plasma 6 Wallpaper

Fetch and cycle wallpapers from [wallhaven.cc](https://wallhaven.cc) on KDE Plasma 6: search, collections, favorites, slideshow effects, offline cache, presets, and full control from the panel, keyboard, KRunner, or D-Bus.

**Current version:** 3.1.0  
**KDE Store / OpenDesktop:** [Wallhaven Extended (p/2368647)](https://www.opendesktop.org/p/2368647/)  
**Releases:** [GitHub Releases](https://github.com/doodersrage/wallhaven-plasma-6-plugin/releases)

---

## Features

| Area | What you get |
|------|----------------|
| **Browse** | Search, more-like-current (`like:id`), collections (URL paste + name filter), favorites, offline playlist, **local folder** |
| **Filters** | Categories, purity, resolution, ratio, color, file type, tag blocklist / favorites, prefer sharper matches |
| **Slideshow** | Interval + jitter, day/night and weekday/weekend searches, time capsules, pause on lock / idle / low battery |
| **Effects** | Crossfade and other transitions, Ken Burns (optional music-reactive pacing), parallax, image enhance, panel tint / accent, **reduced motion** |
| **Cache** | Rolling LRU disk cache, per-monitor namespaces, pin/evict, optional original download, AI upscaler hook, **smart offline** picks |
| **Control** | Panel plasmoid (per-monitor picker), Meta+Alt shortcuts, KRunner, D-Bus / CLI, multi-monitor sync groups + search profiles |
| **Extras** | Simple/Advanced settings UI, curated/community presets, HTTPS preset import, Variety bridge, lock-screen image sync, KWallet API key, secret-scrubbing exports, DE/FR/ES/IT UI |

Almost everything beyond basic search is **opt-in** and off by default.

---

## Install

### KDE Store (recommended for most users)

1. Open [opendesktop.org/p/2368647](https://www.opendesktop.org/p/2368647/) or Discover → search **Wallhaven**.
2. Install the wallpaper package (and the **Wallhaven Control** plasmoid if offered separately).
3. System Settings → Appearance → Wallpaper → **Wallhaven**.

### From this repository (developers / latest main)

```bash
git clone https://github.com/doodersrage/wallhaven-plasma-6-plugin.git
cd wallhaven-plasma-6-plugin
./dev-helper.sh deploy
```

That validates, installs under `~/.local`, enables the user D-Bus service, registers KRunner, and restarts plasmashell.

### Packaging

| Distro | Notes |
|--------|--------|
| **Arch** | `packaging/PKGBUILD` (git) or `packaging/PKGBUILD.release` (tarball). AUR automation is ready when AUR signup is available again — see [packaging/README.md](packaging/README.md). |
| **Fedora / RPM** | `packaging/wallhaven-plasma.spec` |
| **Flatpak** | Manifest + notes in [docs/FLATHUB.md](docs/FLATHUB.md) |

After a system package install, enable the helper if needed:

```bash
systemctl --user enable --now wallhaven-dbus.service
```

---

## Quick start

1. **Wallpaper** — System Settings → Appearance → Wallpaper → **Wallhaven**. Enter a search (e.g. `nature`, `landscape`) or pick a browse mode.
2. **API key (optional)** — Required for NSFW and favorites. Prefer KWallet: paste the key, then **Save current API key to KWallet**. Details: [docs/KWALLET.md](docs/KWALLET.md).
3. **Panel control** — Add **Wallhaven Control** to a panel for next/prev, pause, history, like/dislike, and wallpaper info.
4. **KRunner** — System Settings → Search → Plasma Search → enable **Wallhaven**. Try `wh next` or `wallhaven search anime`.
5. **Shortcuts (optional)** — Arch: `sudo pacman -S extra-cmake-modules` then `./dev-helper.sh install-shortcuts` (Meta+Alt arrows / P / R).

First-run setup wizard in settings checks D-Bus, upscaler, and shortcuts status.

---

## Control without opening settings

| Surface | Examples |
|---------|----------|
| **Plasmoid** | Thumbnail swipe like/dislike, history scrubber, details popup, menu actions |
| **Desktop** | Right-click → Wallpaper Actions (next, similar, info, block, save…) |
| **CLI** | `./tools/wallhaven-ctl.sh next` · `search nature` · `info` · `importpreset https://…/preset.json` |
| **D-Bus** | `org.robertsm.Wallhaven` — see [docs/CONTROL.md](docs/CONTROL.md) |
| **KRunner** | `wh next`, `wallhaven search …`, open / block / copy tags |

Full guide: [docs/CONTROL.md](docs/CONTROL.md).

---

## Requirements

- **KDE Plasma 6** (`X-Plasma-API-Minimum-Version` 6.0)
- Network access to `wallhaven.cc` (unless using offline playlist / cached-only modes)
- Optional: `realesrgan-ncnn-vulkan` on `PATH` for the upscaler hook
- Optional: `kwallet-query` for API key storage
- Optional: Extra CMake Modules to build global shortcuts

---

## Documentation

| Doc | Topic |
|-----|--------|
| [docs/CONTROL.md](docs/CONTROL.md) | Plasmoid, shortcuts, KRunner, D-Bus, CLI |
| [docs/KWALLET.md](docs/KWALLET.md) | API key + KWallet |
| [docs/SMOKE.md](docs/SMOKE.md) | Manual smoke checklist before releases |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Engine / config wiring rules |
| [docs/KDE_STORE.md](docs/KDE_STORE.md) | Store listing updates & screenshots |
| [docs/FLATHUB.md](docs/FLATHUB.md) | Flatpak / Flathub notes |
| [CHANGELOG.md](CHANGELOG.md) | Full release history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Translations and contributions |
| [packaging/README.md](packaging/README.md) | Downstream packaging |

---

## What's new in 3.1.0

- Compact plasmoid + search + pin/unpin
- Local folder depth/exclude/sort; day-aware smart offline
- Preset gallery tiles; lock-screen sync status

## What's new in 3.0.1

- Schema migrate runs **before** KWallet API-key load
- Bug-report / debug exports **always** scrub the API key

## What's new in 3.0.0

- **Simple / Advanced** settings mode (Filters & Advanced tabs hide in Simple)
- **Local folder** browse mode + smart offline cache picks
- Config schema **v3** migration, export secret scrubbing, reduced motion
- Typed D-Bus status helpers and **per-monitor** plasmoid control

## What's new in 2.9.1

- Fix **blank wallpaper settings** panel (duplicate `visible` on browse mode)

## What's new in 2.9.0

- Settings filter **hides** non-matching rows (not just empty-state text)
- **Offline playlist** browse mode (cache / pinned-only)
- Collection **URL paste** + filter-by-name
- Wallpaper **details sheet** (desktop + plasmoid)
- **API health** / rate-limit visibility
- **Save API key to KWallet** (new installs default to load-from-wallet)

Earlier releases (2.8 → 1.5): see [CHANGELOG.md](CHANGELOG.md).

---

## Development commands

```bash
./dev-helper.sh deploy              # install + D-Bus + KRunner + restart plasmashell
./dev-helper.sh check               # structure, wiring audit, unit tests, smoke
./dev-helper.sh release             # tag + GitHub release from metadata version
./dev-helper.sh install-shortcuts   # Meta+Alt global shortcuts
./dev-helper.sh register-preset     # wallhaven://preset/ URL handler

./tools/wallhaven-ctl.sh next
./tools/wallhaven-ctl.sh search nature
./tools/wallhaven-ctl.sh info

./scripts/sync-i18n.sh              # extract strings, refresh .po, compile .mo
./scripts/capture-screenshots.sh --list
./tools/variety-bridge.sh --apply
```

Custom shortcut / D-Bus examples: `examples/plasma-shortcuts.md`.

---

## License

GPL-2.0-or-later
