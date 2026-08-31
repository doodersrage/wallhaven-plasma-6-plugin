Name:           wallhaven-plasma
Version:        3.1.0
Release:        1%{?dist}
Summary:        Wallhaven wallpaper plugin for KDE Plasma 6
License:        GPL-2.0-or-later
URL:            https://github.com/doodersrage/wallhaven-plasma-6-plugin
BuildArch:      noarch
Requires:       plasma-workspace
Requires:       python3-dbus
Requires:       python3-gobject

%description
Wallhaven.cc wallpapers for KDE Plasma 6 with slideshow, KRunner, D-Bus, and MPRIS control.

%prep
%autosetup

%install
mkdir -p %{buildroot}%{_datadir}/plasma/wallpapers/org.robertsm.wallhaven
cp -r contents metadata.json %{buildroot}%{_datadir}/plasma/wallpapers/org.robertsm.wallhaven/
mkdir -p %{buildroot}%{_datadir}/plasma/plasmoids/org.robertsm.wallhaven.control
cp -r plasmoid/contents plasmoid/metadata.json %{buildroot}%{_datadir}/plasma/plasmoids/org.robertsm.wallhaven.control/
install -Dpm644 krunner/org.robertsm.wallhaven.desktop \
    %{buildroot}%{_datadir}/krunner/dplugins/org.robertsm.wallhaven.desktop
install -Dpm644 metainfo/org.robertsm.wallhaven.metainfo.xml \
    %{buildroot}%{_datadir}/metainfo/org.robertsm.wallhaven.metainfo.xml
install -Dpm644 contents/notifications/org.robertsm.wallhaven.notifyrc \
    %{buildroot}%{_datadir}/knotifications6/org.robertsm.wallhaven.notifyrc
mkdir -p %{buildroot}%{_datadir}/wallhaven-plasma/tools
cp -r tools/* %{buildroot}%{_datadir}/wallhaven-plasma/tools/
chmod +x %{buildroot}%{_datadir}/wallhaven-plasma/tools/*.sh \
    %{buildroot}%{_datadir}/wallhaven-plasma/tools/*.py 2>/dev/null || true
if compgen -G "contents/locale/*/LC_MESSAGES/*.mo" >/dev/null; then
    for mo in contents/locale/*/LC_MESSAGES/*.mo; do
        locale="$(echo "${mo}" | sed -n 's|.*/locale/\([^/]*\)/.*|\1|p')"
        install -Dpm644 "${mo}" \
            %{buildroot}%{_datadir}/locale/${locale}/LC_MESSAGES/org.robertsm.wallhaven.mo
    done
fi
install -Dpm644 packaging/wallhaven-dbus.service \
    %{buildroot}%{_prefix}/lib/systemd/user/wallhaven-dbus.service
install -Dpm644 share/org.robertsm.Wallhaven.service.in \
    %{buildroot}%{_datadir}/dbus-1/services/org.robertsm.Wallhaven.service
sed -i 's|@INSTALL_DIR@|%{_datadir}/wallhaven-plasma|g' \
    %{buildroot}%{_datadir}/dbus-1/services/org.robertsm.Wallhaven.service
install -Dpm644 share/wallhaven-preset.desktop.in \
    %{buildroot}%{_datadir}/applications/wallhaven-preset.desktop
sed -i 's|/home/USER/.local/share/wallhaven-plasma/tools|%{_datadir}/wallhaven-plasma/tools|g' \
    %{buildroot}%{_datadir}/applications/wallhaven-preset.desktop

%files
%{_datadir}/plasma/wallpapers/org.robertsm.wallhaven/
%{_datadir}/plasma/plasmoids/org.robertsm.wallhaven.control/
%{_datadir}/krunner/dplugins/org.robertsm.wallhaven.desktop
%{_datadir}/metainfo/org.robertsm.wallhaven.metainfo.xml
%{_datadir}/knotifications6/org.robertsm.wallhaven.notifyrc
%{_datadir}/wallhaven-plasma/tools/
%{_prefix}/lib/systemd/user/wallhaven-dbus.service
%{_datadir}/dbus-1/services/org.robertsm.Wallhaven.service
%{_datadir}/locale/*/LC_MESSAGES/org.robertsm.wallhaven.mo
%{_datadir}/applications/wallhaven-preset.desktop

%changelog
* Mon Aug 31 2026 Wallhaven Plasma Port <wallhaven@local> - 3.1.0-1
- 3.1.0 release

* Fri Aug 28 2026 Wallhaven Plasma Port <wallhaven@local> - 3.0.1-1
- 3.0.1 hotfix

* Fri Aug 28 2026 Wallhaven Plasma Port <wallhaven@local> - 3.0.0-1
- 3.0.0 release

* Thu Aug 27 2026 Wallhaven Plasma Port <wallhaven@local> - 2.9.1-1
- Fix blank wallpaper settings from duplicate QML visible property

* Thu Aug 27 2026 Wallhaven Plasma Port <wallhaven@local> - 2.9.0-1
- Offline playlist, settings filter, details sheet, API health, KWallet save

* Wed Aug 26 2026 Wallhaven Plasma Port <wallhaven@local> - 2.8.0-1
- Wiring audit, smoke CI, collections by user, HTTP presets, laptop mode, wallpaper info

* Tue Aug 25 2026 Wallhaven Plasma Port <wallhaven@local> - 2.7.0-1
- Hardening, preset browser, similar browse mode, idle pause, sync profiles, plasmoid polish

* Sun Aug 23 2026 Wallhaven Plasma Port <wallhaven@local> - 2.6.2-1
- Wire prefer-sharper, weather search, music/lock D-Bus unwrap, settings cfg bindings

* Fri Aug 21 2026 Wallhaven Plasma Port <wallhaven@local> - 2.6.1-1
- D-Bus name ownership, rolling disk cache, settings upscaler/history fixes

* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 2.0.0-1
- Stable 2.0 milestone: Variety preview, Flatpak, AppStream screenshots, stable PKGBUILD

* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.8.0-1
- Attribution layout, settings import via D-Bus, debug log append, slideshow auto-resume, packaging locales/systemd

* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.7.1-1
- Plasmashell stability: D-Bus ReadTextFile, inline settings wizard, cache URL fix

* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.7.0-1
- Complete packaging with tools, metainfo, notifications, preset URL handler

* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.6.0-1
- Initial RPM packaging stub
