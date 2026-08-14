Name:           wallhaven-plasma
Version:        1.7.0
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
%{_datadir}/applications/wallhaven-preset.desktop

%changelog
* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.7.0-1
- Complete packaging with tools, metainfo, notifications, preset URL handler

* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.6.0-1
- Initial RPM packaging stub
