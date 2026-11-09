#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="${1:-${ROOT_DIR}/build}"
OUTPUT_DIR="${2:-${ROOT_DIR}/dist}"

echo "=== Building Debian/Ubuntu Package (v${VERSION}) ==="
mkdir -p "${OUTPUT_DIR}"

if [[ ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    cmake -B "${BUILD_DIR}" -S "${ROOT_DIR}" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCPACK_PACKAGE_VERSION="${VERSION}"
fi
cmake --build "${BUILD_DIR}"

cpack -D CPACK_PACKAGE_VERSION="${VERSION}" --config "${BUILD_DIR}/CPackConfig.cmake" -G DEB -B "${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}/_CPack_Packages"

DEB_FILE=$(find "${OUTPUT_DIR}" -maxdepth 1 -name "*.deb" | head -n 1)
if [[ -n "${DEB_FILE}" && -f "${DEB_FILE}" ]]; then
    echo "=== Debian package created: ${DEB_FILE} ==="
else
    echo "Error: Failed to find generated Debian package." >&2
    exit 1
fi
