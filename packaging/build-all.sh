#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
DIST_DIR="${ROOT_DIR}/dist"

mkdir -p "${DIST_DIR}"

echo "=== Tsuki Universal Packaging Script ==="
echo "Version: ${VERSION}"
echo "Destination: ${DIST_DIR}"

TARGET="${1:-all}"

case "${TARGET}" in
    arch)
        "${ROOT_DIR}/packaging/arch/build-arch.sh" "${DIST_DIR}"
        ;;
    deb)
        "${ROOT_DIR}/packaging/debian/build-deb.sh" "${ROOT_DIR}/build" "${DIST_DIR}"
        ;;
    rpm)
        "${ROOT_DIR}/packaging/fedora/build-rpm.sh" "${DIST_DIR}"
        ;;
    appimage)
        "${ROOT_DIR}/packaging/appimage/build-appimage.sh" "${ROOT_DIR}/build" "${DIST_DIR}/Tsuki-${VERSION}-x86_64.AppImage"
        ;;
    all)
        echo "Building AppImage..."
        "${ROOT_DIR}/packaging/appimage/build-appimage.sh" "${ROOT_DIR}/build" "${DIST_DIR}/Tsuki-${VERSION}-x86_64.AppImage"

        echo "Building Debian package..."
        "${ROOT_DIR}/packaging/debian/build-deb.sh" "${ROOT_DIR}/build" "${DIST_DIR}"

        if command -v makepkg >/dev/null 2>&1; then
            echo "Building Arch Linux package..."
            "${ROOT_DIR}/packaging/arch/build-arch.sh" "${DIST_DIR}"
        fi

        if command -v rpmbuild >/dev/null 2>&1; then
            echo "Building Fedora RPM package..."
            "${ROOT_DIR}/packaging/fedora/build-rpm.sh" "${DIST_DIR}"
        fi
        ;;
    *)
        echo "Unknown target: ${TARGET}. Valid targets: arch, deb, rpm, appimage, all" >&2
        exit 1
        ;;
esac

echo "Packaging complete. Artifacts in ${DIST_DIR}:"
ls -lh "${DIST_DIR}"

