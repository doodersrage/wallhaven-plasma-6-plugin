#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="org.robertsm.wallhaven"
INSTALL_DIR="${HOME}/.local/share/plasma/wallpapers/${PLUGIN_ID}"

usage() {
    cat <<EOF
Wallhaven Plasma 6 wallpaper helper

Usage: $(basename "$0") <command>

Commands:
  install     Install to ~/.local/share/plasma/wallpapers/
  uninstall   Remove user installation
  restart     Restart plasmashell
  package     Create distributable .tar.xz package
  help        Show this help
EOF
}

install_plugin() {
    rm -rf "${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
    cp -r "${SCRIPT_DIR}/contents" "${INSTALL_DIR}/"
    cp "${SCRIPT_DIR}/metadata.json" "${INSTALL_DIR}/"
    if [[ -f "${SCRIPT_DIR}/preview.jpg" ]]; then
        cp "${SCRIPT_DIR}/preview.jpg" "${INSTALL_DIR}/"
    fi
    echo "Installed to ${INSTALL_DIR}"
    echo "Restart plasmashell, then pick 'Wallhaven' in System Settings → Appearance → Wallpaper."
}

uninstall_plugin() {
    rm -rf "${INSTALL_DIR}"
    echo "Removed ${INSTALL_DIR}"
}

restart_plasma() {
    kquitapp6 plasmashell 2>/dev/null || true
    nohup plasmashell >/dev/null 2>&1 &
    echo "Plasmashell restarted"
}

package_plugin() {
    local version
    version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' "${SCRIPT_DIR}/metadata.json")"
    local archive="${SCRIPT_DIR}/wallhaven-plasma-${version}.tar.xz"
    tar -cJf "${archive}" -C "${SCRIPT_DIR}" contents metadata.json preview.jpg 2>/dev/null \
        || tar -cJf "${archive}" -C "${SCRIPT_DIR}" contents metadata.json
    echo "Created ${archive}"
}

main() {
    cd "${SCRIPT_DIR}"
    case "${1:-help}" in
        install) install_plugin ;;
        uninstall) uninstall_plugin ;;
        restart) restart_plasma ;;
        package) package_plugin ;;
        help|--help|-h) usage ;;
        *) echo "Unknown command: $1"; usage; exit 1 ;;
    esac
}

main "$@"
