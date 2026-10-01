# Manual smoke checklist

Run after `./dev-helper.sh deploy` and before tagging a release.

## 3.7 — things only a person can check

- [ ] Change the search text in settings and click **Apply**: the wallpaper refetches once, without pressing Reload
- [ ] Change the interval and Apply: the widget countdown restarts with the new interval
- [ ] Paste the API key → **Save current API key to KWallet**: the field empties, the hint shows the key's last four characters, and `grep -c '^ApiKey=.\+' ~/.config/plasma-org.kde.plasma.desktop-appletsrc` prints `0`
- [ ] Log out and in: NSFW/favorites still work (key came from the wallet) and that `grep` still prints `0`
- [ ] Lock and unlock the screen: wallpaper is on screen again within a couple of seconds on every monitor
- [ ] With lock-screen sync on, the lock screen shows the current wallpaper; with it off everywhere and your own lock wallpaper set, that wallpaper stays
- [ ] Add **Wallhaven Control** to a panel: next / pause react immediately and the thumbnail follows the wallpaper
- [ ] Unplug a monitor: after 5 minutes it is gone from the widget's monitor picker

## D-Bus and control

- [ ] `systemctl --user is-active wallhaven-dbus.service` → `active`
- [ ] `qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Ping` → `ok`
- [ ] Wallpaper settings: D-Bus warning banner at the top clears within ~5s
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

- [ ] Essentials page: changing Search / categories / interval / pause / lock screen there matches All settings after switching
- [ ] Opening settings and switching Essentials ↔ All settings without edits leaves Apply disabled
- [ ] Tag blocklist, favorites, rotation list, time capsules, presets survive close/reopen
- [ ] Settings filter text persists after Apply/reopen
- [ ] Setup wizard shows D-Bus/upscaler status

## Plasmoid

- [ ] Thumbnail + tags line visible when D-Bus online
- [ ] History popup lists recent wallpapers; click restores one
- [ ] Swipe like/dislike updates tag favorites/blocklist
- [ ] Menu → Wallpaper info shows details / notification

## Sync groups

- [ ] Save profile for sync group A, switch group B, switch back — search settings restore
- [ ] “Use this screen’s name as sync group” sets group to cache namespace

## 2.9 extras

- [ ] Browse mode **Offline playlist** cycles cache; pinned-only skips unpinned
- [ ] Collection URL parse + filter-by-name on loaded collections
- [ ] Wallpaper Info opens details sheet; plasmoid menu shows details popup
- [ ] Diagnostics shows API health / rate-limit count
- [ ] Save API key to KWallet; restart still loads it with the toggle on
- [ ] Settings filter hides unrelated Form rows (try “playlist”, “kwallet”, “health”)
