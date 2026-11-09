#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
WORK_DIR="$(mktemp -d /tmp/tsuki-arch-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Arch Linux Package (v${VERSION}) ==="
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

# Create clean source tarball excluding build artifacts and temporary files
tar -czf "${WORK_DIR}/tsuki-${VERSION}.tar.gz" -C "${ROOT_DIR}" \
    --exclude-vcs \
    --exclude='./build*' \
    --exclude='./dist*' \
    --exclude='./.temp*' \
    --transform "s,^\.,tsuki-${VERSION}," .

cp "${ROOT_DIR}/packaging/arch/PKGBUILD" "${WORK_DIR}/"

cd "${WORK_DIR}"
makepkg -f --nodeps

PKG_FILE=$(find "${WORK_DIR}" -maxdepth 1 -name "tsuki-${VERSION}-*.pkg.tar.zst" ! -name "*-debug-*" | head -n 1)
if [[ -n "${PKG_FILE}" && -f "${PKG_FILE}" ]]; then
    cp "${PKG_FILE}" "${OUTPUT_DIR}/"
    echo "=== Arch Linux package created: ${OUTPUT_DIR}/$(basename "${PKG_FILE}") ==="
else
    echo "Error: Failed to find generated Arch package." >&2
    exit 1
fi

