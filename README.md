# Wallhaven — KDE Plasma 6 Wallpaper

KDE Plasma 6 Wallhaven wallpaper plugin with search, collections, slideshow, effects, offline cache, blocklist, presets, KRunner, D-Bus control, and panel plasmoid.

**Install from KDE Store / OpenDesktop:** [Wallhaven Extended (p/2368647)](https://www.opendesktop.org/p/2368647/)

## Quick start

```bash
./dev-helper.sh deploy
```

System Settings → Appearance → Wallpaper → **Wallhaven**

Enable **Wallhaven** in System Settings → Search → Plasma Search (KRunner).

**Control without opening settings:** see [docs/CONTROL.md](docs/CONTROL.md) (plasmoid, Meta+Alt shortcuts, KRunner, D-Bus).

**KDE Store listing:** [opendesktop.org/p/2368647](https://www.opendesktop.org/p/2368647/) — see [docs/KDE_STORE.md](docs/KDE_STORE.md) for maintainer notes.

## v2.8.0 — distribution & follow-ups

Closes the post-2.7 checklist: wiring audit correctness, CI smoke, collections/presets UX, laptop mode, wallpaper info, and bug-report export.

| Area | Highlights |
|------|------------|
| **Hardening** | Typed `cfg_*` bindings counted; missing ones fail CI; offline smoke script |
| **Search** | Load collections by username; import presets from HTTPS JSON |
| **Power** | One-click laptop mode preset |
| **History** | Up to 2000 seen IDs + clear button |
| **Control** | Wallpaper info action / plasmoid / `wh info` |
| **Multi-monitor** | Use this screen’s name as sync group |
| **Diagnostics** | Export bug-report JSON file |

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.8.0
```

Upload the release tarball to [OpenDesktop p/2368647](https://www.opendesktop.org/p/2368647/) — see [docs/KDE_STORE.md](docs/KDE_STORE.md).

## v2.7.0 — hardening & polish

Hardening, UX polish, and several opt-in 2.7 features on top of the 2.6 wiring fixes.

| Area | Highlights |
|------|------------|
| **Hardening** | CI config-wiring audit (`scripts/check-config-wiring.sh`); architecture + smoke docs |
| **Search** | **More like current** browse mode (`like:id`); preset browser with full snapshot export |
| **Cache** | Optional download of original-resolution file; cache list auto-refreshes; offline empty-cache notification |
| **Effects** | Panel blur strength; music-reactive gated on Ken Burns; idle slideshow pause |
| **Sync** | Per control-bus group search profiles (save/apply on group switch) |
| **Plasmoid** | Tags under thumbnail; recent wallpapers in context menu |
| **Setup** | Wizard shows D-Bus, upscaler, and shortcuts status |

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.7.0
```

See also: [docs/SMOKE.md](docs/SMOKE.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/FLATHUB.md](docs/FLATHUB.md)

## v2.6.2 — feature wiring

Several advertised toggles were silent no-ops; they now reach the engine and D-Bus replies unwrap correctly.

| Area | Highlights |
|------|------------|
| **Search** | Prefer sharper matches and weather-reactive tags actually affect picks/queries |
| **Effects** | Music-reactive Ken Burns and screen-lock pause read wrapped D-Bus replies correctly |
| **Settings** | Blocklist, favorites, rotation, capsules, and presets use Plasma `cfg_*` bindings |
| **Plasmoid** | History scrubber and status thumb unwrap `ReadTextFile` before parsing |

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.6.2
```

## v2.6.1 — patch

Settings and D-Bus correctness on top of 2.6.0.

| Area | Highlights |
|------|------------|
| **D-Bus** | Service keeps `org.robertsm.Wallhaven` for the process lifetime (`Type=dbus` + session activation). Settings pings the service instead of a one-shot getter, so the offline banner clears when it is actually up |
| **Cache** | Slot count is a ceiling again: oldest unused unpinned wallpapers are aged out. Pinned slots stay |
| **Settings** | Upscaler status no longer sticks on "Checking…". Wallpaper history gallery reads from the live wallpaper and shows thumbnails or an empty-state message |

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.6.1
```

## v2.6.0 — sharper wallpapers

Opt-in image-quality tools plus several correctness fixes.

| Area | Highlights |
|------|------------|
| **Search** | Prefer sharper matches (resolution/aspect-aware, off by default) |
| **Effects** | Brightness / contrast / saturation enhance at render time |
| **Upscale** | Optional `realesrgan-ncnn-vulkan` hook for low-res matches, plus re-upscale of already-cached files |
| **Fixes** | Theme-sync color format, small-quality thumbs, overlapping transitions, pinned cache slots, D-Bus detection, pause on screen lock |

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.6.0
```

## v2.5.0 — fun release

| Area | Highlights |
|------|------------|
| **Panel widget** | Swipe the thumbnail (or use its menu) to like/dislike tags; new "Recent wallpapers" history scrubber |
| **Reactivity** | Ken Burns speeds up with playing music (MPRIS); search leans toward rain/snow/storm tags via local weather |
| **Scheduling** | Time capsules — auto-switch search on a date, recurring (`MM-DD`) or one-off (`YYYY-MM-DD`) |
| **Theming** | Auto panel accent can also sync to GTK apps and `kdeglobals` |
| **Fun** | Opt-in milestone/streak toast notifications |

All seven are opt-in and off by default — enable them in **Effects** and **Schedule** settings tabs.

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.5.0
```

## v2.4.0 — bugfix

| Area | Highlights |
|------|------------|
| **Presets** | Curated/community import works; Apply reloads search and turns People off when omitted |
| **Cache** | Per-monitor files; skip cached people/NSFW when those filters are off |
| **Effects** | Parallax slowly pans; Ken Burns pan works |
| **Lock screen** | Copies current wallpaper into kscreenlocker’s Image keys |

```bash
./dev-helper.sh deploy
./dev-helper.sh release              # tag v2.4.0
```

## v2.3.0 — store ready

| Area | Highlights |
|------|------------|
| **i18n** | Italian UI (~415 strings) + DE/FR/ES |
| **Shortcuts** | Fixed Arch CMake build; PKGBUILD ships binary + autostart |
| **Docs** | Control guide + KDE Store checklist |
| **UX** | Settings filter “no matches” hint |
| **CI** | Neon shortcuts build + variety D-Bus tests |

```bash
./dev-helper.sh deploy
sudo pacman -S extra-cmake-modules   # Arch
./dev-helper.sh install-shortcuts
./scripts/capture-screenshots.sh     # replace placeholder PNGs
./dev-helper.sh release              # tag v2.3.0
```

## v2.2.0 — discover & control

| Area | Highlights |
|------|------------|
| **i18n** | Spanish UI (~409 strings) + [CONTRIBUTING.md](CONTRIBUTING.md) translator guide |
| **Shortcuts** | KGlobalAccel binary (`./dev-helper.sh install-shortcuts`) — Meta+Alt+arrows |
| **Plasmoid** | Click thumb → open page, similar/block/copy menu, offline states |
| **Variety** | Watch `variety.conf` for live search import |
| **CI** | Flatpak manifest smoke + Spanish locale in tarball checks |

```bash
./dev-helper.sh deploy
./dev-helper.sh install-shortcuts
./dev-helper.sh release           # tag v2.2.0 + GitHub release
```

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
| **i18n** | Full German + French + Spanish UI (~409 strings each) |
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
