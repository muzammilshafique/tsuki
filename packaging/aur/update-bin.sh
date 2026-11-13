#!/usr/bin/env bash
set -euo pipefail

# Sync packaging/aur/tsuki-bin/{PKGBUILD,.SRCINFO} with a GitHub release.
# Usage:
#   ./packaging/aur/update-bin.sh                  # Fetch latest GitHub release
#   ./packaging/aur/update-bin.sh v1.0.0           # Fetch specific release tag
#   ./packaging/aur/update-bin.sh v1.0.0 <sha256>  # Update offline with known checksum

REPO="muzammilshafique/tsuki"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/tsuki-bin"
PKGBUILD_PATH="${BIN_DIR}/PKGBUILD"

TAG="${1:-}"
SHA256="${2:-}"

if [[ -z "${TAG}" ]]; then
    echo "Fetching latest release tag from GitHub (${REPO})..."
    TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    if [[ -z "${TAG}" ]]; then
        echo "Error: Could not determine latest GitHub release tag." >&2
        exit 1
    fi
fi

RAW_VERSION="${TAG#v}"
PKGVER="${RAW_VERSION//-/.}"
PKG_FILE="tsuki-${PKGVER}-1-x86_64.pkg.tar.zst"

if [[ -z "${SHA256}" ]]; then
    SUMS_URL="https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS"
    echo "Fetching SHA256SUMS from ${SUMS_URL}..."
    SHA256="$(curl -fsSL "${SUMS_URL}" | awk -v f="${PKG_FILE}" '$2 == f || $2 == ("./" f) { print $1; exit }' || true)"
    if [[ -z "${SHA256}" ]]; then
        echo "SHA256SUMS entry not found for ${PKG_FILE}; downloading package directly to compute checksum..."
        PKG_URL="https://github.com/${REPO}/releases/download/${TAG}/${PKG_FILE}"
        TMP_PKG="$(mktemp)"
        trap 'rm -f "${TMP_PKG}"' EXIT
        curl -fL "${PKG_URL}" -o "${TMP_PKG}"
        SHA256="$(sha256sum "${TMP_PKG}" | awk '{print $1}')"
    fi
fi

if [[ ! "${SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "Error: Invalid SHA-256 checksum: ${SHA256}" >&2
    exit 1
fi

sed -i "s|^pkgver=.*|pkgver=${PKGVER}|" "${PKGBUILD_PATH}"
sed -i "s|^_tag=.*|_tag=\"${TAG}\"|" "${PKGBUILD_PATH}"
sed -i "s|^pkgrel=.*|pkgrel=1|" "${PKGBUILD_PATH}"
sed -i "s|^sha256sums_x86_64=.*|sha256sums_x86_64=('${SHA256}')|" "${PKGBUILD_PATH}"

if command -v makepkg >/dev/null 2>&1; then
    (cd "${BIN_DIR}" && makepkg --printsrcinfo > .SRCINFO)
    echo "Updated ${PKGBUILD_PATH} and ${BIN_DIR}/.SRCINFO for ${TAG} (${PKG_FILE}, sha256=${SHA256})."
else
    echo "Warning: makepkg not found; updated PKGBUILD only. Run 'makepkg --printsrcinfo > .SRCINFO' on Arch Linux." >&2
fi

