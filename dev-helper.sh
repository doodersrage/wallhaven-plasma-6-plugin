#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="org.robertsm.wallhaven"
PLASMOID_ID="org.robertsm.wallhaven.control"
KRUNNER_ID="org.robertsm.wallhaven"
INSTALL_DIR="${HOME}/.local/share/plasma/wallpapers/${PLUGIN_ID}"
PLASMOID_DIR="${HOME}/.local/share/plasma/plasmoids/${PLASMOID_ID}"
KRUNNER_DIR="${HOME}/.local/share/krunner/dplugins"
APPLICATIONS_DIR="${HOME}/.local/share/applications"
NOTIFY_DIR="${HOME}/.local/share/knotifications6"
DATA_DIR="${HOME}/.local/share/wallhaven-plasma"
SYSTEMD_USER="${HOME}/.config/systemd/user"

usage() {
    cat <<EOF
Wallhaven Plasma 6 wallpaper helper

Usage: $(basename "$0") <command>

Commands:
  install         Install wallpaper + plasmoid + notifyrc
  uninstall       Remove user installation
  restart         Restart plasmashell
  deploy          translations + install + dbus + restart
  package         Create distributable .tar.xz package
  test            Run wallhaven.js unit tests
  check           Validate structure + run tests
  release         Tag and publish GitHub release (see scripts/release.sh)
  translations    Compile .po files to contents/locale/
  sync-i18n       Extract strings, refresh .po, compile .mo
  extract-i18n    Extract translatable strings to po/*.pot
  dbus-install    Install and enable user D-Bus service
  dbus-uninstall  Disable and remove user D-Bus service
  help            Show this help
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

    mkdir -p "${DATA_DIR}"
    ln -sfn "${SCRIPT_DIR}" "${DATA_DIR}/source"
    cp -a "${SCRIPT_DIR}/tools" "${DATA_DIR}/"

    chmod +x "${DATA_DIR}/tools/wallhaven-ctl.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/register-shortcuts.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/variety-sync.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/apply-panel-tint.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/wallhaven-dbus.py" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/wallhaven-bot-example.py" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/variety-watch.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/variety-bridge.sh" 2>/dev/null || true
    chmod +x "${DATA_DIR}/tools/import-preset-url.sh" 2>/dev/null || true

    mkdir -p "${KRUNNER_DIR}"
    cp "${SCRIPT_DIR}/krunner/${KRUNNER_ID}.desktop" "${KRUNNER_DIR}/"

    mkdir -p "${APPLICATIONS_DIR}"
    sed "s|/home/USER/.local/share/wallhaven-plasma/tools|${DATA_DIR}/tools|g" \
        "${SCRIPT_DIR}/share/wallhaven-preset.desktop.in" \
        > "${APPLICATIONS_DIR}/wallhaven-preset.desktop"
    chmod +x "${APPLICATIONS_DIR}/wallhaven-preset.desktop" 2>/dev/null || true
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${APPLICATIONS_DIR}" 2>/dev/null || true
    fi
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default wallhaven-preset.desktop x-scheme-handler/wallhaven 2>/dev/null || true
    fi

    echo "Installed wallpaper to ${INSTALL_DIR}"
    echo "Installed plasmoid to ${PLASMOID_DIR}"
    echo "Installed KRunner plugin to ${KRUNNER_DIR}/${KRUNNER_ID}.desktop"
    if [[ -f "${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc" ]]; then
        echo "Installed notifications to ${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc"
    fi
    echo "Tools linked at ${DATA_DIR}/tools"
}

uninstall_plugin() {
    rm -rf "${INSTALL_DIR}" "${PLASMOID_DIR}"
    rm -f "${NOTIFY_DIR}/${PLUGIN_ID}.notifyrc"
    rm -f "${KRUNNER_DIR}/${KRUNNER_ID}.desktop"
    rm -f "${APPLICATIONS_DIR}/wallhaven-preset.desktop"
    echo "Removed ${INSTALL_DIR}, ${PLASMOID_DIR}, and KRunner plugin"
}

restart_plasma() {
    kquitapp6 plasmashell 2>/dev/null || true
    nohup plasmashell >/dev/null 2>&1 &
    echo "Plasmashell restarted"
}

run_tests() {
    node "${SCRIPT_DIR}/tests/test-wallhaven.js"
}

run_check() {
    "${SCRIPT_DIR}/scripts/validate.sh"
    run_tests
}

compile_translations() {
    "${SCRIPT_DIR}/scripts/compile-translations.sh"
}

extract_i18n() {
    "${SCRIPT_DIR}/scripts/extract-messages.sh"
}

package_plugin() {
    if compgen -G "${SCRIPT_DIR}/po/*.po" >/dev/null; then
        compile_translations
    fi
    local version
    version="$(grep -Po '"Version"\s*:\s*"\K[^"]+' "${SCRIPT_DIR}/metadata.json")"
    local archive="${SCRIPT_DIR}/wallhaven-plasma-${version}.tar.xz"
    local files=(contents metadata.json plasmoid tools krunner examples metainfo share packaging po)
    if [[ -f "${SCRIPT_DIR}/preview.jpg" ]]; then
        files+=(preview.jpg)
    fi
    tar -cJf "${archive}" -C "${SCRIPT_DIR}" "${files[@]}"
    echo "Created ${archive}"
}

install_dbus_service() {
    install_plugin
    mkdir -p "${SYSTEMD_USER}"
    sed "s|@INSTALL_DIR@|${DATA_DIR}|g" \
        "${SCRIPT_DIR}/tools/wallhaven-dbus.service.in" \
        > "${SYSTEMD_USER}/wallhaven-dbus.service"
    systemctl --user daemon-reload
    systemctl --user enable --now wallhaven-dbus.service
    echo "D-Bus service enabled: wallhaven-dbus.service"
    systemctl --user status wallhaven-dbus.service --no-pager || true
}

uninstall_dbus_service() {
    systemctl --user disable --now wallhaven-dbus.service 2>/dev/null || true
    rm -f "${SYSTEMD_USER}/wallhaven-dbus.service"
    systemctl --user daemon-reload
    echo "Removed wallhaven-dbus.service"
}

deploy_all() {
    run_check
    install_dbus_service
    restart_plasma
    echo "Deploy complete: plugin installed, D-Bus service running, plasmashell restarted"
    echo "Add 'Wallhaven Control' widget; configure wallpaper in System Settings."
}

run_release() {
    "${SCRIPT_DIR}/scripts/release.sh" "$@"
}

main() {
    cd "${SCRIPT_DIR}"
    case "${1:-help}" in
        install) install_plugin ;;
        uninstall) uninstall_plugin ;;
        restart) restart_plasma ;;
        deploy) deploy_all ;;
        package) package_plugin ;;
        test) run_tests ;;
        check) run_check ;;
        release) shift; run_release "$@" ;;
        translations) compile_translations ;;
        sync-i18n) "${SCRIPT_DIR}/scripts/sync-i18n.sh" ;;
        extract-i18n) extract_i18n ;;
        dbus-install) install_dbus_service ;;
        dbus-uninstall) uninstall_dbus_service ;;
        help|--help|-h) usage ;;
        *) echo "Unknown command: $1"; usage; exit 1 ;;
    esac
}

main "$@"
