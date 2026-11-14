#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW_VERSION="${VERSION:-$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || echo '0.1.1')}"
RAW_VERSION="${RAW_VERSION#v}"
PKGVER="${RAW_VERSION//-/.}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
WORK_DIR="$(mktemp -d /tmp/tsuki-arch-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Arch Linux Package (${PKGVER} / app version ${RAW_VERSION}) ==="
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

# Create clean source tarball excluding VCS, build artifacts, and temporary files
tar -czf "${WORK_DIR}/tsuki-${PKGVER}.tar.gz" -C "${ROOT_DIR}" \
    --exclude-vcs \
    --exclude='./build*' \
    --exclude='./dist*' \
    --exclude='./.temp*' \
    --exclude='./.qt*' \
    --exclude='./.cache*' \
    --transform "s,^\.,tsuki-${PKGVER}," .

TARBALL_SHA256="$(sha256sum "${WORK_DIR}/tsuki-${PKGVER}.tar.gz" | awk '{print $1}')"

cp "${ROOT_DIR}/packaging/arch/PKGBUILD" "${WORK_DIR}/"
cp "${ROOT_DIR}/packaging/arch/tsuki.install" "${WORK_DIR}/"

sed -i "s|^pkgver=.*|pkgver=${PKGVER}|" "${WORK_DIR}/PKGBUILD"
sed -i "s|^_rawver=.*|_rawver=\"${RAW_VERSION}\"|" "${WORK_DIR}/PKGBUILD"
sed -i "s|^sha256sums=.*|sha256sums=('${TARBALL_SHA256}')|" "${WORK_DIR}/PKGBUILD"

cd "${WORK_DIR}"
read -ra EXTRA_FLAGS <<< "${MAKEPKG_FLAGS:--f}"
makepkg "${EXTRA_FLAGS[@]}"

PKG_FILE=$(find "${WORK_DIR}" -maxdepth 1 -name "tsuki-${PKGVER}-*.pkg.tar.zst" ! -name "*-debug-*" | head -n 1)
if [[ -n "${PKG_FILE}" && -f "${PKG_FILE}" ]]; then
    cp "${PKG_FILE}" "${OUTPUT_DIR}/"
    echo "=== Arch Linux package created: ${OUTPUT_DIR}/$(basename "${PKG_FILE}") ==="
else
    echo "Error: Failed to find generated Arch package." >&2
    exit 1
fi

