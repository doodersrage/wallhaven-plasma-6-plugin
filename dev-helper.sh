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
  test            Run wallhaven.js unit tests, QML smoke checks, and D-Bus service tests (if python3-dbus is installed)
  check           Validate structure + run tests
  release         Tag and publish GitHub release (see scripts/release.sh)
  translations    Compile .po files to contents/locale/
  sync-i18n       Extract strings, refresh .po, compile .mo
  extract-i18n    Extract translatable strings to po/*.pot
  dbus-install    Install and enable user D-Bus service
  dbus-uninstall  Disable and remove user D-Bus service
  register-preset Register wallhaven:// preset URL handler (xdg-mime)
  install-shortcuts Build and autostart KGlobalAccel shortcuts (Meta+Alt+arrows)
  uninstall-shortcuts Remove shortcuts autostart entry
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
    bash "${SCRIPT_DIR}/tests/validate-qml.sh"
    if python3 -c "import dbus, gi" >/dev/null 2>&1; then
        python3 "${SCRIPT_DIR}/tests/test-variety-dbus.py"
    else
        echo "Skipping tests/test-variety-dbus.py (python3-dbus/python3-gi not installed)"
    fi
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
    local files=(contents metadata.json plasmoid tools krunner examples metainfo share packaging po screenshots docs CONTRIBUTING.md)
    if [[ -f "${SCRIPT_DIR}/preview.jpg" ]]; then
        files+=(preview.jpg)
    fi
    tar -cJf "${archive}" -C "${SCRIPT_DIR}" "${files[@]}"
    echo "Created ${archive}"
}

# The D-Bus service needs python-dbus + python-gobject (package names vary by
# distro) on top of the interpreter; dev-helper never installs system
# packages itself, so check for them before touching systemd rather than
# enabling a unit that is guaranteed to crash-loop.
check_dbus_deps() {
    if python3 -c "import dbus, gi; from gi.repository import GLib" >/dev/null 2>&1; then
        return 0
    fi
    echo "Missing D-Bus service dependencies (the python3 'dbus' and 'gi' modules)." >&2
    echo "wallhaven-dbus.py exits immediately without them, so systemd will crash-loop the unit." >&2
    echo "Install the system packages (not pip) for your distro, then rerun 'dev-helper.sh dbus-install':" >&2
    echo "  Arch:   sudo pacman -S python-dbus python-gobject" >&2
    echo "  Fedora: sudo dnf install python3-dbus python3-gobject-base" >&2
    echo "  Debian: sudo apt install python3-dbus python3-gi" >&2
    return 1
}

install_dbus_service() {
    install_plugin
    mkdir -p "${SYSTEMD_USER}"
    sed "s|@INSTALL_DIR@|${DATA_DIR}|g" \
        "${SCRIPT_DIR}/tools/wallhaven-dbus.service.in" \
        > "${SYSTEMD_USER}/wallhaven-dbus.service"
    mkdir -p "${HOME}/.local/share/dbus-1/services"
    sed "s|@INSTALL_DIR@|${DATA_DIR}|g" \
        "${SCRIPT_DIR}/share/org.robertsm.Wallhaven.service.in" \
        > "${HOME}/.local/share/dbus-1/services/org.robertsm.Wallhaven.service"
    systemctl --user daemon-reload

    if ! check_dbus_deps; then
        echo "Skipping service start until dependencies are installed." >&2
        return 1
    fi

    # A unit that crash-looped past systemd's StartLimitBurst is left
    # "failed" and ignores further 'enable --now' calls until this is
    # cleared -- which is exactly what running deploy repeatedly against a
    # missing dependency looks like from the outside ("still not running").
    systemctl --user reset-failed wallhaven-dbus.service >/dev/null 2>&1 || true
    systemctl --user enable --now wallhaven-dbus.service

    sleep 1
    if systemctl --user is-active --quiet wallhaven-dbus.service; then
        echo "D-Bus service enabled and running: wallhaven-dbus.service"
    else
        echo "D-Bus service failed to start. Recent log:" >&2
        journalctl --user -u wallhaven-dbus.service -n 20 --no-pager >&2 || true
        return 1
    fi
}

uninstall_dbus_service() {
    systemctl --user disable --now wallhaven-dbus.service 2>/dev/null || true
    rm -f "${SYSTEMD_USER}/wallhaven-dbus.service"
    rm -f "${HOME}/.local/share/dbus-1/services/org.robertsm.Wallhaven.service"
    systemctl --user daemon-reload
    echo "Removed wallhaven-dbus.service"
}

register_preset_handler() {
    install_plugin
    if command -v xdg-mime >/dev/null 2>&1; then
        xdg-mime default wallhaven-preset.desktop x-scheme-handler/wallhaven 2>/dev/null || true
        echo "Registered wallhaven:// preset handler (wallhaven-preset.desktop)"
    else
        echo "xdg-mime not found; install xdg-utils" >&2
        exit 1
    fi
}

install_shortcuts() {
    install_plugin
    if ! command -v cmake >/dev/null 2>&1; then
        echo "cmake is required to build wallhaven-shortcuts" >&2
        exit 1
    fi
    if ! command -v g++ >/dev/null 2>&1; then
        echo "g++ is required to build wallhaven-shortcuts" >&2
        exit 1
    fi
    if [[ ! -d /usr/share/ECM ]]; then
        echo "KF6 CMake modules not found (extra-cmake-modules)." >&2
        echo "Install build dependencies, then rerun:" >&2
        echo "  Arch:   sudo pacman -S extra-cmake-modules qt6-base kglobalaccel ki18n kcoreaddons cmake gcc" >&2
        echo "  Fedora: sudo dnf install kf6-extra-cmake-modules qt6-qtbase-devel kf6-kglobalaccel-devel kf6-ki18n-devel kf6-kcoreaddons-devel cmake gcc-c++" >&2
        echo "  Debian: sudo apt install extra-cmake-modules qt6-base-dev libkf6globalaccel-dev libkf6i18n-dev libkf6coreaddons-dev cmake g++" >&2
        exit 1
    fi
    local build_dir="${SCRIPT_DIR}/build-shortcuts"
    rm -rf "${build_dir}"
    cmake -S "${SCRIPT_DIR}/tools/wallhaven-shortcuts" -B "${build_dir}" -DCMAKE_BUILD_TYPE=Release
    cmake --build "${build_dir}"
    mkdir -p "${DATA_DIR}/bin"
    install -m755 "${build_dir}/wallhaven-shortcuts" "${DATA_DIR}/bin/wallhaven-shortcuts"
    mkdir -p "${HOME}/.config/autostart"
    sed "s|@INSTALL_DIR@|${DATA_DIR}|g" \
        "${SCRIPT_DIR}/share/wallhaven-shortcuts.desktop.in" \
        > "${HOME}/.config/autostart/wallhaven-shortcuts.desktop"
    echo "Installed wallhaven-shortcuts to ${DATA_DIR}/bin/wallhaven-shortcuts"
    echo "Autostart entry: ~/.config/autostart/wallhaven-shortcuts.desktop"
    echo "Shortcuts: Meta+Alt+Right/Left/P/R"
    echo "Log out and back in (or reboot) if shortcuts do not register immediately."
}

uninstall_shortcuts() {
    rm -f "${HOME}/.config/autostart/wallhaven-shortcuts.desktop"
    rm -f "${DATA_DIR}/bin/wallhaven-shortcuts"
    echo "Removed Wallhaven global shortcuts autostart"
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
        register-preset) register_preset_handler ;;
        install-shortcuts) install_shortcuts ;;
        uninstall-shortcuts) uninstall_shortcuts ;;
        help|--help|-h) usage ;;
        *) echo "Unknown command: $1"; usage; exit 1 ;;
    esac
}

main "$@"
