# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 Wallhaven wallpaper plugin with search, collections, slideshow, effects, offline cache, blocklist, presets, KRunner, D-Bus control, and panel plasmoid.

## Quick start

```bash
./dev-helper.sh deploy
```

System Settings → Appearance → Wallpaper → **Wallhaven**

Enable **Wallhaven** in System Settings → Search → Plasma Search (KRunner).

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
./tools/import-preset-url.sh 'wallhaven://preset/...'
./tools/variety-bridge.sh
```

See `examples/plasma-shortcuts.md` for Custom Shortcuts and D-Bus examples.

## License

GPL-2.0-or-later
