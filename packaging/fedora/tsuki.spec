Name:           tsuki
Version:        1.0.0
Release:        1%{?dist}
Summary:        Native Linux Game Launcher for Wine and Proton

License:        GPL-3.0-or-later
URL:            https://github.com/muzammilshafique/tsuki
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc-c++
BuildRequires:  cmake >= 3.24
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(sdl2)
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtsvg-devel
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

Requires:       hicolor-icon-theme
Requires:       qt6-qtbase
Requires:       qt6-qtdeclarative
Requires:       qt6-qtsvg
Requires:       SDL2
Requires:       tar

Recommends:     wine
Recommends:     winetricks
Recommends:     mangohud
Recommends:     gamemode
Recommends:     p7zip

%description
Tsuki is a modern native Linux game launcher designed for Wine and Proton games.
It provides seamless prefix management, Wine and Proton runner downloads,
Winetricks integration, SteamGridDB artwork fetching, and virtual Xbox
controller emulation.

%prep
%autosetup

%build
%cmake -G Ninja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%check
%ctest

%install
%cmake_install

%post
/usr/bin/udevadm control --reload-rules >/dev/null 2>&1 || :
/usr/bin/udevadm trigger /dev/uinput >/dev/null 2>&1 || :
/usr/bin/update-desktop-database >/dev/null 2>&1 || :
/usr/bin/touch --no-create %{_datadir}/icons/hicolor >/dev/null 2>&1 || :

%postun
/usr/bin/udevadm control --reload-rules >/dev/null 2>&1 || :
/usr/bin/udevadm trigger /dev/uinput >/dev/null 2>&1 || :
/usr/bin/update-desktop-database >/dev/null 2>&1 || :

%files
%license LICENSE
%{_bindir}/tsuki
%{_datadir}/applications/io.github.muzammilshafique.tsuki.desktop
%{_datadir}/applications/tsuki.desktop
%{_datadir}/metainfo/io.github.muzammilshafique.tsuki.metainfo.xml
%{_datadir}/mime/packages/tsuki.xml
%{_datadir}/icons/hicolor/*/apps/tsuki.*
%{_datadir}/icons/hicolor/*/apps/io.github.muzammilshafique.tsuki.*
%{_datadir}/pixmaps/tsuki.*
%{_prefix}/lib/udev/rules.d/70-tsuki-uinput.rules
%{_prefix}/lib/modules-load.d/tsuki-uinput.conf

%changelog
* Tue Nov 10 2026 Muzammil Shafique <muzammil@example.com> - 1.0.0-1
- Initial release

