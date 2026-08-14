#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="org.robertsm.wallhaven"
INSTALL_DIR="${HOME}/.local/share/plasma/wallpapers/${PLUGIN_ID}"
NOTIFY_DIR="${HOME}/.local/share/knotifications6"

usage() {
    cat <<EOF
Wallhaven Plasma 6 wallpaper helper

Usage: $(basename "$0") <command>

Commands:
  install     Install to ~/.local/share/plasma/wallpapers/
  uninstall   Remove user installation
  restart     Restart plasmashell
  package     Create distributable .tar.xz package
  test        Run wallhaven.js unit tests
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
    if [[ -f "${SCRIPT_DIR}/contents/notifications/${PLUGIN_ID}.notifyrc" ]]; then
        mkdir -p "${NOTIFY_DIR}"
        cp "${SCRIPT_DIR}/contents/notifications/${PLUGIN_ID}.notifyrc" "${NOTIFY_DIR}/"
    fi
    echo "Installed to ${INSTALL_DIR}"
    if [[ -f "${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc" ]]; then
        echo "Installed notifications to ${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc"
    fi
    echo "Restart plasmashell, then pick 'Wallhaven' in System Settings → Appearance → Wallpaper."
}

uninstall_plugin() {
    rm -rf "${INSTALL_DIR}"
    rm -f "${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc"
    echo "Removed ${INSTALL_DIR}"
}

restart_plasma() {
    kquitapp6 plasmashell 2>/dev/null || true
    nohup plasmashell >/dev/null 2>&1 &
    echo "Plasmashell restarted"
}

run_tests() {
    node "${SCRIPT_DIR}/tests/test-wallhaven.js"
}

package_plugin() {
    local version
    version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' "${SCRIPT_DIR}/metadata.json")"
    local archive="${SCRIPT_DIR}/wallhaven-plasma-${version}.tar.xz"
    local files=(contents metadata.json)
    if [[ -f "${SCRIPT_DIR}/preview.jpg" ]]; then
        files+=(preview.jpg)
    fi
    if [[ -d "${SCRIPT_DIR}/metainfo" ]]; then
        files+=(metainfo)
    fi
    tar -cJf "${archive}" -C "${SCRIPT_DIR}" "${files[@]}"
    echo "Created ${archive}"
    echo "See RELEASE.md for publish steps."
}

main() {
    cd "${SCRIPT_DIR}"
    case "${1:-help}" in
        install) install_plugin ;;
        uninstall) uninstall_plugin ;;
        restart) restart_plasma ;;
        package) package_plugin ;;
        test) run_tests ;;
        help|--help|-h) usage ;;
        *) echo "Unknown command: $1"; usage; exit 1 ;;
    esac
}

main "$@"
