# Manual smoke checklist

Run after `./dev-helper.sh deploy` and before tagging a release.

## D-Bus and control

- [ ] `systemctl --user is-active wallhaven-dbus.service` → `active`
- [ ] `qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Ping` → `ok`
- [ ] Settings → Performance: D-Bus banner clears within ~5s
- [ ] `./tools/wallhaven-ctl.sh next` advances wallpaper

## Search and filters

- [ ] **Prefer sharper matches** (Search → Filters): with random sort, undersized images appear less often over ~10 advances
- [ ] **Weather-reactive** (Effects): set a city, enable toggle; journal/debug shows weather tag appended to search
- [ ] **Tag favorites / blocklist**: edit, Apply, next fetch respects tags
- [ ] **More like current** browse mode: slideshow stays on `like:<id>` variants

## Cache and offline

- [ ] Disk cache count increases after new wallpapers
- [ ] Settings → cache list auto-updates without manual Refresh
- [ ] **Cache original file** (when enabled): cached JPG matches full resolution from Wallhaven
- [ ] **Offline only** with empty cache shows a desktop notification

## Effects

- [ ] Ken Burns + **Music-reactive**: Ken Burns speeds up while Spotify/VLC is playing
- [ ] **Screen lock pause**: slideshow pauses on lock, resumes on unlock
- [ ] **Pause on idle** (if enabled): pauses after session idle threshold

## Settings UI

- [ ] Tag blocklist, favorites, rotation list, time capsules, presets survive close/reopen
- [ ] Settings filter text persists after Apply/reopen
- [ ] Setup wizard shows D-Bus/upscaler status

## Plasmoid

- [ ] Thumbnail + tags line visible when D-Bus online
- [ ] History popup lists recent wallpapers; click restores one
- [ ] Swipe like/dislike updates tag favorites/blocklist

## Sync groups

- [ ] Save profile for sync group A, switch group B, switch back — search settings restore
