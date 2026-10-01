# API key & KWallet

Wallhaven NSFW/favorites features need an API key from https://wallhaven.cc/settings/account.

## Recommended: KWallet

1. Paste the key in **API key** (Essentials page, or All settings → Storage → Wallhaven account).
2. Click **Save current API key to KWallet**. The field empties: the key now lives in the wallet only.
3. Keep **Load API key from KWallet on startup** enabled (default for new installs).

The key is stored in wallet `kdewallet`, folder `org.robertsm.wallhaven`, entry `apikey`.

### Where the key is (and is not)

| Place | With KWallet | Without KWallet |
|-------|--------------|-----------------|
| KWallet | yes | no |
| Wallpaper memory (plasmashell) | yes, while running | yes |
| Wallpaper settings file (`plasma-org.kde.plasma.desktop-appletsrc`) | **no** | yes, plain text |
| Files under `~/.cache/plasmashell` | no | no |
| Process command lines | no | no |

At startup the wallpaper asks the D-Bus helper for the key (`GetApiKey`); the helper runs `kwallet-query` and returns the value over the session bus. Saving pipes the key to `kwallet-query` on stdin. Nothing is written to disk on the way.

A key typed into the settings field and applied *without* saving to KWallet stays in the settings file and takes priority over the wallet copy until you save or clear it.

**Clear API key** removes it from the settings and stops loading it from KWallet. It does not delete the wallet entry; remove that in KWalletManager if you want it gone.

### Upgrading from 3.6 or earlier

Older versions copied the wallet key back into the settings file on every start and left a plaintext copy in `~/.cache/plasmashell/kwallet-apikey.txt`. From 3.7 the helper deletes that file when it starts, and the wallpaper blanks the settings-file copy the first time the wallet answers with the same key. Sync-group profiles saved earlier could also contain the key; it is stripped from them at startup.

If your key was ever on a machine you share or in a backup you do not control, consider generating a new one on wallhaven.cc.

## Bug reports

Debug/bundle export can include a settings snapshot. With KWallet the key is not in it; otherwise keep **Export privacy → Omit API key from settings / bug-report exports** enabled, or clear the key before sharing.
