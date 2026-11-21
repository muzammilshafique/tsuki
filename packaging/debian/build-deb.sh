#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION" 2>/dev/null || git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || echo '0.2.3')"
RAW_VERSION="${VERSION:-${DEFAULT_VERSION}}"
RAW_VERSION="${RAW_VERSION#v}"
DEB_UPSTREAM_VER="${RAW_VERSION//-/\~}"
DEB_REVISION="${DEB_REVISION:-1}"
DEB_VERSION="${DEB_UPSTREAM_VER}-${DEB_REVISION}"
ARCH="${DEB_ARCH:-$(dpkg --print-architecture)}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
WORK_DIR="$(mktemp -d /tmp/tsuki-deb-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Debian/Ubuntu Package (${DEB_VERSION} / app version ${RAW_VERSION}, arch ${ARCH}) ==="
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}/build" "${WORK_DIR}/pkg" "${WORK_DIR}/shlibs/debian" "${WORK_DIR}/test-home/.config" "${WORK_DIR}/test-home/.local/share" "${WORK_DIR}/test-home/.cache"

cmake -S "${ROOT_DIR}" -B "${WORK_DIR}/build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DTSUKI_VERSION="${RAW_VERSION}"

cmake --build "${WORK_DIR}/build"

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
    HOME="${WORK_DIR}/test-home" \
    XDG_CONFIG_HOME="${WORK_DIR}/test-home/.config" \
    XDG_DATA_HOME="${WORK_DIR}/test-home/.local/share" \
    XDG_CACHE_HOME="${WORK_DIR}/test-home/.cache" \
    QT_QPA_PLATFORM=offscreen \
    ctest --test-dir "${WORK_DIR}/build" --output-on-failure
fi

PKG_ROOT="${WORK_DIR}/pkg"
DESTDIR="${PKG_ROOT}" cmake --install "${WORK_DIR}/build"

if command -v strip >/dev/null 2>&1; then
    strip --strip-unneeded "${PKG_ROOT}/usr/bin/tsuki"
fi

install -Dm644 "${ROOT_DIR}/LICENSE" "${PKG_ROOT}/usr/share/doc/tsuki/copyright"

cat << 'EOF' > "${WORK_DIR}/shlibs/debian/control"
Source: tsuki

Package: tsuki
Architecture: any
EOF

SHLIB_DEPS="$(cd "${WORK_DIR}/shlibs" && dpkg-shlibdeps -O "${PKG_ROOT}/usr/bin/tsuki" | sed -n 's/^shlibs:Depends=//p')"
if [[ -z "${SHLIB_DEPS}" ]]; then
    echo "Error: Failed to compute shared library dependencies with dpkg-shlibdeps." >&2
    exit 1
fi

RUNTIME_QML_DEPS="qt6-qpa-plugins, qt6-svg-plugins, libqt6sql6-sqlite, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-effects, hicolor-icon-theme, tar"
ALL_DEPS="${SHLIB_DEPS}, ${RUNTIME_QML_DEPS}"
INSTALLED_SIZE="$(du -sk "${PKG_ROOT}" | awk '{print $1}')"

mkdir -p "${PKG_ROOT}/DEBIAN"

cat << EOF > "${PKG_ROOT}/DEBIAN/control"
Package: tsuki
Version: ${DEB_VERSION}
Section: games
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Depends: ${ALL_DEPS}
Recommends: qt6-wayland
Suggests: wine, winetricks, mangohud, gamemode, 7zip, vulkan-tools
Maintainer: Muzammil Shafique <muzu@duck.com>
Homepage: https://github.com/muzammilshafique/tsuki
Description: Native Linux game launcher for Wine, Proton, and native titles
 Tsuki is a native Linux game launcher written in C++20 and Qt 6 / QML.
 It supports managing Windows (Wine / Proton) and native Linux games,
 Wine prefix management, Winetricks, SteamGridDB artwork, and virtual
 Xbox 360 controller emulation over /dev/uinput.
EOF

cat << 'EOF' > "${PKG_ROOT}/DEBIAN/postinst"
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules >/dev/null 2>&1 || true
        udevadm trigger --subsystem-match=misc --sysname-match=uinput >/dev/null 2>&1 || true
    fi
    if [ ! -e /dev/uinput ] && command -v modprobe >/dev/null 2>&1; then
        modprobe uinput >/dev/null 2>&1 || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
fi
exit 0
EOF

cat << 'EOF' > "${PKG_ROOT}/DEBIAN/postrm"
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules >/dev/null 2>&1 || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
fi
exit 0
EOF

chmod 0755 "${PKG_ROOT}/DEBIAN" "${PKG_ROOT}/DEBIAN/postinst" "${PKG_ROOT}/DEBIAN/postrm"

DEB_OUT="${OUTPUT_DIR}/tsuki_${DEB_VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "${PKG_ROOT}" "${DEB_OUT}"

echo "=== Debian/Ubuntu package created: ${DEB_OUT} ==="

