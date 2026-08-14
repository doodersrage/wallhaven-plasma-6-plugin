# Plasma Custom Shortcuts examples

Use **System Settings → Shortcuts → Custom Shortcuts → Edit → New → Command**.

| Name | Command |
|------|---------|
| Wallhaven Next | `~/.local/share/wallhaven-plasma/tools/wallhaven-ctl.sh next` |
| Wallhaven Previous | `~/.local/share/wallhaven-plasma/tools/wallhaven-ctl.sh prev` |
| Wallhaven Pause | `~/.local/share/wallhaven-plasma/tools/wallhaven-ctl.sh pause` |
| Wallhaven Reload | `~/.local/share/wallhaven-plasma/tools/wallhaven-ctl.sh reload` |

## D-Bus (when `wallhaven-dbus.service` is running)

```bash
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.Command next
qdbus6 org.robertsm.Wallhaven /Wallhaven org.robertsm.Wallhaven.CommandInGroup search "nature" 
qdbus6 org.robertsm.Wallhaven /Player org.robertsm.Wallhaven.Player.Next
```

## KRunner

Enable **Wallhaven** runner in System Settings → Search → Plasma Search.

Examples:

- `wh next`
- `wallhaven search anime city`

## qdbus6 evaluateScript (legacy)

Plasma does not expose wallpaper actions on a stable public D-Bus API; prefer `wallhaven-ctl.sh` or the D-Bus service above.
