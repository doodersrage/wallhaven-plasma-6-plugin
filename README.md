# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 Wallhaven wallpaper plugin with search, collections, slideshow, effects, offline cache, blocklist, presets, KRunner, D-Bus control, and panel plasmoid.

## Quick start

```bash
./dev-helper.sh deploy
```

System Settings → Appearance → Wallpaper → **Wallhaven**

Enable **Wallhaven** in System Settings → Search → Plasma Search (KRunner).

## v2.1.0 — polish release

| Area | Highlights |
|------|------------|
| **i18n** | Full French UI (~406 strings) + unified `fill-po.py` pipeline |
| **Store** | Six screenshot assets + AppStream gallery for KDE Store / Discover |
| **Control** | Plasmoid uses local cache thumbnail; D-Bus offline hints in settings |
| **Packaging** | AUR auto-publish on release tags, PKGBUILD smoke CI, preset MIME helper |

```bash
./dev-helper.sh deploy
./dev-helper.sh register-preset   # wallhaven:// URL handler
./dev-helper.sh release           # tag v2.1.0 + GitHub release
```

## v2.0.0 — stable milestone

Wallhaven for KDE Plasma 6 is feature-complete for this port cycle. Highlights across the 1.x → 2.0 line:

| Area | Highlights |
|------|------------|
| **Wallpaper** | Search, collections, favorites, WOTD, disk cache, effects, blocklist, presets |
| **Control** | D-Bus service, MPRIS, KRunner, panel plasmoid, control bus, sync advance |
| **Integration** | Variety bridge, lock screen sync, panel accent, KWallet, preset URLs |
| **i18n** | Full German + French UI (~406 strings each) |
| **Packaging** | Arch/Fedora, Flatpak, AUR workflows, systemd user service |

```bash
./dev-helper.sh deploy
./dev-helper.sh release    # tag v2.0.0 + GitHub release
```

## v1.8.0 highlights

| Feature | Notes |
|---------|--------|
| Settings import | JSON import via D-Bus (works in Desktop Folder Settings) |
| Slideshow rules | Auto-resume when battery/activity conditions normalize |
| Debug log | D-Bus append with rotation + preview in settings |
| Packaging | Locales, systemd user service, preset handler docs |
| Attribution | Fixed corner overlay layout |

## v1.7.1 highlights

| Feature | Notes |
|---------|--------|
| Plasmashell stability | D-Bus file I/O replaces blocked XHR/Process APIs |
| Settings panel | Inline setup wizard works in Desktop Folder Settings |
| Cache URLs | Fixed double `file://` prefix on cached wallpapers |

## v1.7.0 highlights

| Feature | Notes |
|---------|--------|
| German i18n | Full UI translation + `scripts/sync-i18n.sh` pipeline |
| Variety apply | `--apply` flag + settings button imports Variety search |
| Live MPRIS | Status file watcher updates media keys / KDE Connect UI |
| Screenshots | Guided 6-shot capture script for KDE Store |
| Packaging | Complete PKGBUILD/RPM + AUR workflow template |

## v1.6.0 highlights

| Feature | Notes |
|---------|--------|
| MPRIS | Full `org.mpris.MediaPlayer2.wallhaven` for media keys / KDE Connect |
| Preset URLs | `wallhaven://preset/…` handler + import in settings |
| KRunner extras | `wallhaven open`, `block`, `copy tags` |
| Plasmoid menu | Open, block, copy tags from panel widget |
| Panel accent | Auto-apply accent from wallpaper via `plasma-apply-colors` |
| Smart color | Derive Wallhaven color filter from wallpaper palette |
| Favorite tags | Boost preferred tags in search queries |
| Slideshow rules | Pause on low battery or inactive session |
| Debug metrics | Fetch timing + cache stats in status / debug bundle |
| Community presets | Shipped pack + variety bridge script |
| Packaging | AUR PKGBUILD + RPM spec stubs |

## v1.5.0 highlights

| Feature | Notes |
|---------|--------|
| Setup wizard | First-run overlay in settings |
| Settings filter | Search box filters visible options |
| Wallpaper of the day | Toplist / 24h mode |
| Cache manager | Pin, unpin, evict cached wallpapers |
| Debug log | Copy debug bundle for bug reports |
| Curated presets | Shipped pack + `wallhaven://preset/…` URLs |
| KRunner | `wh next`, `wallhaven search anime` |
| D-Bus player | `/Player` Next/Previous/PlayPause/Metadata |
| Adaptive preload | Fewer preloads when offline/metered |

## Commands

```bash
./dev-helper.sh deploy            # validate, install, D-Bus, KRunner, restart
./dev-helper.sh check
./dev-helper.sh release
./tools/wallhaven-ctl.sh next
./tools/wallhaven-ctl.sh search nature   # via D-Bus one-shot
python3 tools/wallhaven-bot-example.py   # webhook example (optional)
./tools/variety-watch.sh ~/Pictures/Variety
./scripts/sync-i18n.sh              # extract + update de.po + compile .mo
./scripts/capture-screenshots.sh --list
./tools/variety-bridge.sh --apply
```

See `examples/plasma-shortcuts.md` for Custom Shortcuts and D-Bus examples.

## License

GPL-2.0-or-later
