# Screenshots

Capture these for the KDE Store / GitHub release page:

1. **Settings — Source tab** with preview and browse mode
2. **Settings — Filters tab** showing tag blocklist
3. **Settings — Advanced tab** with history gallery
4. **Wallhaven Control plasmoid** showing thumbnail + countdown
5. **Desktop wallpaper** with attribution overlay (optional)
6. **Wallpaper Actions menu** showing Reload / Next / Similar

Suggested command after applying the wallpaper:

```bash
spectacle -f -o screenshots/settings-source.png
```

Or use your preferred screenshot tool. Recommended size: 1280×720 or wider.

Generate placeholder crops from `preview.jpg` when real captures are unavailable:

```bash
chmod +x scripts/generate-screenshots-from-preview.sh
./scripts/generate-screenshots-from-preview.sh
```

## Wayland resize checklist

After changing display scale or resolution:

- [ ] Wallpaper refills the screen without letterboxing
- [ ] No excessive blur or pixelation
- [ ] Slideshow continues after reconnect
- [ ] Settings preview updates within ~2 seconds
