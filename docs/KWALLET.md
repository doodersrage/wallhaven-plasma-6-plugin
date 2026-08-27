# API key & KWallet

Wallhaven NSFW/favorites features need an API key from https://wallhaven.cc/settings/account.

## Recommended: KWallet

1. Paste the key in **Source → API key**.
2. Click **Save current API key to KWallet**.
3. Keep **Load API key from KWallet on startup** enabled (default for new installs).

The key is stored in KWallet folder `org.robertsm.wallhaven`, entry `apikey` (wallet `wallhaven` or `kdewallet`).

Leaving the key only in wallpaper settings works, but the settings file is easier to leak via backups or bug-report exports. Prefer KWallet for anything beyond SFW search.

## Bug reports

Debug/bundle export can include a settings snapshot. Clear or omit the API key before sharing exports, or rely on KWallet so the plain config field stays empty.
