#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="org.robertsm.wallhaven"
PLASMOID_ID="org.robertsm.wallhaven.control"
INSTALL_DIR="${HOME}/.local/share/plasma/wallpapers/${PLUGIN_ID}"
PLASMOID_DIR="${HOME}/.local/share/plasma/plasmoids/${PLASMOID_ID}"
NOTIFY_DIR="${HOME}/.local/share/knotifications6"

usage() {
    cat <<EOF
Wallhaven Plasma 6 wallpaper helper

Usage: $(basename "$0") <command>

Commands:
  install       Install wallpaper + plasmoid + notifyrc
  uninstall     Remove user installation
  restart       Restart plasmashell
  package       Create distributable .tar.xz package
  test          Run wallhaven.js unit tests
  translations  Compile .po files to contents/locale/
  help          Show this help
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

    rm -rf "${PLASMOID_DIR}"
    mkdir -p "${PLASMOID_DIR}"
    cp -r "${SCRIPT_DIR}/plasmoid/contents" "${PLASMOID_DIR}/"
    cp "${SCRIPT_DIR}/plasmoid/metadata.json" "${PLASMOID_DIR}/"

    chmod +x "${SCRIPT_DIR}/tools/wallhaven-ctl.sh" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/tools/register-shortcuts.sh" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/tools/variety-sync.sh" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/tools/apply-panel-tint.sh" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/tools/wallhaven-dbus.py" 2>/dev/null || true

    echo "Installed wallpaper to ${INSTALL_DIR}"
    echo "Installed plasmoid to ${PLASMOID_DIR}"
    if [[ -f "${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc" ]]; then
        echo "Installed notifications to ${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc"
    fi
    echo "Restart plasmashell, pick 'Wallhaven' wallpaper, optionally add 'Wallhaven Control' widget."
}

uninstall_plugin() {
    rm -rf "${INSTALL_DIR}" "${PLASMOID_DIR}"
    rm -f "${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc"
    echo "Removed ${INSTALL_DIR} and ${PLASMOID_DIR}"
}

restart_plasma() {
    kquitapp6 plasmashell 2>/dev/null || true
    nohup plasmashell >/dev/null 2>&1 &
    echo "Plasmashell restarted"
}

run_tests() {
    node "${SCRIPT_DIR}/tests/test-wallhaven.js"
}

compile_translations() {
    "${SCRIPT_DIR}/scripts/compile-translations.sh"
}

package_plugin() {
    local version
    version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' "${SCRIPT_DIR}/metadata.json")"
    local archive="${SCRIPT_DIR}/wallhaven-plasma-${version}.tar.xz"
    local files=(contents metadata.json plasmoid tools)
    if [[ -f "${SCRIPT_DIR}/preview.jpg" ]]; then
        files+=(preview.jpg)
    fi
    if [[ -d "${SCRIPT_DIR}/metainfo" ]]; then
        files+=(metainfo)
    fi
    if [[ -d "${SCRIPT_DIR}/contents/locale" ]]; then
        : # already under contents/
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
        translations) compile_translations ;;
        help|--help|-h) usage ;;
        *) echo "Unknown command: $1"; usage; exit 1 ;;
    esac
}

main "$@"
