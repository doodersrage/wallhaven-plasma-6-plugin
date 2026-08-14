Name:           wallhaven-plasma
Version:        1.6.0
Release:        1%{?dist}
Summary:        Wallhaven wallpaper plugin for KDE Plasma 6
License:        GPL-2.0-or-later
URL:            https://github.com/doodersrage/wallhaven-plasma-6-plugin
BuildArch:      noarch
Requires:       plasma-workspace

%description
Wallhaven.cc wallpapers for KDE Plasma 6 with slideshow, KRunner, and D-Bus control.

%prep
%autosetup

%install
mkdir -p %{buildroot}%{_datadir}/plasma/wallpapers/org.robertsm.wallhaven
cp -r contents metadata.json %{buildroot}%{_datadir}/plasma/wallpapers/org.robertsm.wallhaven/
mkdir -p %{buildroot}%{_datadir}/plasma/plasmoids/org.robertsm.wallhaven.control
cp -r plasmoid/contents plasmoid/metadata.json %{buildroot}%{_datadir}/plasma/plasmoids/org.robertsm.wallhaven.control/
install -Dpm644 krunner/org.robertsm.wallhaven.desktop \
    %{buildroot}%{_datadir}/krunner/dplugins/org.robertsm.wallhaven.desktop

%files
%{_datadir}/plasma/wallpapers/org.robertsm.wallhaven/
%{_datadir}/plasma/plasmoids/org.robertsm.wallhaven.control/
%{_datadir}/krunner/dplugins/org.robertsm.wallhaven.desktop

%changelog
* Fri Aug 14 2026 Wallhaven Plasma Port <wallhaven@local> - 1.6.0-1
- Initial RPM packaging stub
