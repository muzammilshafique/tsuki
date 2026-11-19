%{!?pkg_version:%define pkg_version 0.2.0}
%{!?app_version:%define app_version %{pkg_version}}

Name:           tsuki
Version:        %{pkg_version}
Release:        1%{?dist}
Summary:        Native Linux game launcher for Wine, Proton, and native titles

License:        GPL-3.0-or-later
URL:            https://github.com/muzammilshafique/tsuki
Source0:        %{name}-%{pkg_version}.tar.gz

BuildRequires:  cmake >= 3.24
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  pkgconf-pkg-config
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtsvg-devel
BuildRequires:  pkgconfig(sdl2)
BuildRequires:  pkgconfig(zlib)

Requires:       qt6-qtbase
Requires:       qt6-qtbase-gui
Requires:       qt6-qtdeclarative
Requires:       qt6-qtsvg
Requires:       hicolor-icon-theme
Requires:       tar
Recommends:     qt6-qtwayland
Suggests:       wine
Suggests:       winetricks
Suggests:       mangohud
Suggests:       gamemode
Suggests:       p7zip
Suggests:       vulkan-loader

%description
Tsuki is a native Linux game launcher for Wine, Proton, and native titles,
written in C++20 and Qt 6 / QML. It supports runner downloads, isolated Wine
prefix management, Winetricks integration, SteamGridDB artwork, and virtual
Xbox 360 controller emulation over /dev/uinput.

%prep
%autosetup -n %{name}-%{pkg_version}

%build
%cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DTSUKI_VERSION=%{app_version}
%cmake_build

%check
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "${TEST_HOME}"' EXIT
mkdir -p "${TEST_HOME}/.config" "${TEST_HOME}/.local/share" "${TEST_HOME}/.cache"
HOME="${TEST_HOME}" \
XDG_CONFIG_HOME="${TEST_HOME}/.config" \
XDG_DATA_HOME="${TEST_HOME}/.local/share" \
XDG_CACHE_HOME="${TEST_HOME}/.cache" \
QT_QPA_PLATFORM=offscreen \
ctest --test-dir "%{_vpath_builddir}" --output-on-failure

%install
%cmake_install

%post
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || :
    udevadm trigger --subsystem-match=misc --sysname-match=uinput >/dev/null 2>&1 || :
fi
if [ ! -e /dev/uinput ] && command -v modprobe >/dev/null 2>&1; then
    modprobe uinput >/dev/null 2>&1 || :
fi

%postun
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules >/dev/null 2>&1 || :
fi

%files
%license LICENSE
%doc README.md
%{_bindir}/tsuki
%{_datadir}/applications/io.github.muzammilshafique.tsuki.desktop
%{_datadir}/metainfo/io.github.muzammilshafique.tsuki.metainfo.xml
%{_datadir}/icons/hicolor/scalable/apps/io.github.muzammilshafique.tsuki.svg
/usr/lib/udev/rules.d/70-tsuki-uinput.rules
/usr/lib/modules-load.d/tsuki-uinput.conf

%changelog
* Thu Nov 19 2026 Muzammil Shafique <muzu@duck.com> - 0.1.1-1
- Add Fedora RPM packaging specification

