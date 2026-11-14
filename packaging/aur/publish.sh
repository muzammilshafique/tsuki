#!/usr/bin/env bash
set -euo pipefail

# Publish a prepared AUR package directory (containing PKGBUILD, .SRCINFO,
# and optional install script) to an AUR git repository.
#
# Usage:
#   ./packaging/aur/publish.sh <pkg-name> <source-dir>
#
# Environment variables:
#   AUR_REPO_BASE   Base git URL (default: ssh://aur@aur.archlinux.org)
#   AUR_BRANCH      Target AUR branch (default: master)
#   AUR_GIT_NAME    Git commit author name (default: Muzammil Shafique)
#   AUR_GIT_EMAIL   Git commit author email (default: muzu@duck.com)
#   MAKEPKG_USER    Non-root user used for makepkg when running as root (default: builduser)

usage() {
    echo "Usage: $0 <pkg-name> <source-dir>" >&2
}

if [[ $# -ne 2 ]]; then
    usage
    exit 2
fi

PKG_NAME="$1"
SOURCE_DIR="$2"

AUR_REPO_BASE="${AUR_REPO_BASE:-ssh://aur@aur.archlinux.org}"
AUR_BRANCH="${AUR_BRANCH:-master}"
AUR_GIT_NAME="${AUR_GIT_NAME:-Muzammil Shafique}"
AUR_GIT_EMAIL="${AUR_GIT_EMAIL:-muzu@duck.com}"
MAKEPKG_USER="${MAKEPKG_USER:-builduser}"

if [[ -z "${PKG_NAME}" || "${PKG_NAME}" =~ [/[:space:]] ]]; then
    echo "Error: Invalid AUR package name: '${PKG_NAME}'" >&2
    exit 1
fi

if [[ ! -f "${SOURCE_DIR}/PKGBUILD" || ! -f "${SOURCE_DIR}/.SRCINFO" ]]; then
    echo "Error: '${SOURCE_DIR}' must contain PKGBUILD and .SRCINFO." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

parse_pkgbuild_var() {
    local pkgbuild_path="$1"
    local var_name="$2"
    bash -c 'set -e; source "$1" >/dev/null 2>&1; printf "%s" "${!2-}"' _ "${pkgbuild_path}" "${var_name}"
}

format_pkg_ver() {
    local epoch="$1"
    local pkgver="$2"
    local pkgrel="$3"
    if [[ -n "${epoch}" && "${epoch}" != "0" ]]; then
        printf '%s:%s-%s' "${epoch}" "${pkgver}" "${pkgrel}"
    else
        printf '%s-%s' "${pkgver}" "${pkgrel}"
    fi
}

format_base_ver() {
    local epoch="$1"
    local pkgver="$2"
    if [[ -n "${epoch}" && "${epoch}" != "0" ]]; then
        printf '%s:%s' "${epoch}" "${pkgver}"
    else
        printf '%s' "${pkgver}"
    fi
}

regenerate_srcinfo() {
    local dir="$1"
    if ! command -v makepkg >/dev/null 2>&1; then
        echo "Error: makepkg is required to regenerate .SRCINFO after bumping pkgrel." >&2
        return 1
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        if ! id -u "${MAKEPKG_USER}" >/dev/null 2>&1; then
            echo "Error: Running as root and MAKEPKG_USER '${MAKEPKG_USER}' does not exist." >&2
            return 1
        fi
        local tmp_src_dir makepkg_home
        tmp_src_dir="$(mktemp -d /tmp/aur-srcinfo.XXXXXX)"
        makepkg_home="$(getent passwd "${MAKEPKG_USER}" | cut -d: -f6)"
        cp -f "${dir}/PKGBUILD" "${tmp_src_dir}/PKGBUILD"
        if [[ -f "${dir}/tsuki.install" ]]; then
            cp -f "${dir}/tsuki.install" "${tmp_src_dir}/tsuki.install"
        fi
        chown -R "${MAKEPKG_USER}:${MAKEPKG_USER}" "${tmp_src_dir}"
        su -s /bin/bash "${MAKEPKG_USER}" -c "export HOME='${makepkg_home}'; cd '${tmp_src_dir}' && makepkg --printsrcinfo > .SRCINFO"
        cp -f "${tmp_src_dir}/.SRCINFO" "${dir}/.SRCINFO"
        rm -rf "${tmp_src_dir}"
    else
        (cd "${dir}" && makepkg --printsrcinfo > .SRCINFO)
    fi
}

REPO_URL="${AUR_REPO_BASE%/}/${PKG_NAME}.git"
REPO_DIR="${WORK_DIR}/repo"

echo "=== Cloning AUR repository ${REPO_URL} ==="
git clone "${REPO_URL}" "${REPO_DIR}"
cd "${REPO_DIR}"

HAS_HEAD=0
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    HAS_HEAD=1
    git checkout -B "${AUR_BRANCH}"
else
    git symbolic-ref HEAD "refs/heads/${AUR_BRANCH}"
fi

git config user.name "${AUR_GIT_NAME}"
git config user.email "${AUR_GIT_EMAIL}"

EXISTING_PKGVER=""
EXISTING_PKGREL=""
EXISTING_EPOCH=""
if [[ -f "${REPO_DIR}/PKGBUILD" ]]; then
    EXISTING_PKGVER="$(parse_pkgbuild_var "${REPO_DIR}/PKGBUILD" pkgver)"
    EXISTING_PKGREL="$(parse_pkgbuild_var "${REPO_DIR}/PKGBUILD" pkgrel)"
    EXISTING_EPOCH="$(parse_pkgbuild_var "${REPO_DIR}/PKGBUILD" epoch)"
fi

NEW_PKGVER="$(parse_pkgbuild_var "${SOURCE_DIR}/PKGBUILD" pkgver)"
NEW_PKGREL="$(parse_pkgbuild_var "${SOURCE_DIR}/PKGBUILD" pkgrel)"
NEW_EPOCH="$(parse_pkgbuild_var "${SOURCE_DIR}/PKGBUILD" epoch)"

if [[ -z "${NEW_PKGVER}" || -z "${NEW_PKGREL}" ]]; then
    echo "Error: Could not parse pkgver/pkgrel from '${SOURCE_DIR}/PKGBUILD'." >&2
    exit 1
fi

FILES_TO_STAGE=("PKGBUILD" ".SRCINFO")
cp -f "${SOURCE_DIR}/PKGBUILD" "${REPO_DIR}/PKGBUILD"
cp -f "${SOURCE_DIR}/.SRCINFO" "${REPO_DIR}/.SRCINFO"
if [[ -f "${SOURCE_DIR}/tsuki.install" ]]; then
    cp -f "${SOURCE_DIR}/tsuki.install" "${REPO_DIR}/tsuki.install"
    FILES_TO_STAGE+=("tsuki.install")
fi

if [[ -n "${EXISTING_PKGVER}" ]]; then
    if ! command -v vercmp >/dev/null 2>&1; then
        echo "Error: vercmp is required to compare AUR package versions." >&2
        exit 1
    fi

    EXISTING_BASE="$(format_base_ver "${EXISTING_EPOCH}" "${EXISTING_PKGVER}")"
    NEW_BASE="$(format_base_ver "${NEW_EPOCH}" "${NEW_PKGVER}")"
    BASE_CMP="$(vercmp "${NEW_BASE}" "${EXISTING_BASE}")"

    if (( BASE_CMP < 0 )); then
        echo "Error: Refusing to downgrade ${PKG_NAME} from $(format_pkg_ver "${EXISTING_EPOCH}" "${EXISTING_PKGVER}" "${EXISTING_PKGREL}") to $(format_pkg_ver "${NEW_EPOCH}" "${NEW_PKGVER}" "${NEW_PKGREL}")." >&2
        exit 1
    elif (( BASE_CMP == 0 )); then
        # Check if anything other than pkgrel changed compared to the current AUR HEAD.
        if [[ "${NEW_PKGREL}" != "${EXISTING_PKGREL}" ]]; then
            sed -i "s|^pkgrel=.*|pkgrel=${EXISTING_PKGREL}|" "${REPO_DIR}/PKGBUILD"
            regenerate_srcinfo "${REPO_DIR}"
        fi

        git add -- "${FILES_TO_STAGE[@]}"
        if git diff --cached --quiet; then
            echo "AUR package ${PKG_NAME} is already up to date at $(format_pkg_ver "${EXISTING_EPOCH}" "${EXISTING_PKGVER}" "${EXISTING_PKGREL}"); skipping push."
            exit 0
        fi

        # Contents changed for the same pkgver: ensure pkgrel strictly increases.
        TARGET_PKGREL="${NEW_PKGREL}"
        if [[ "${EXISTING_PKGREL}" =~ ^[0-9]+$ && "${TARGET_PKGREL}" =~ ^[0-9]+$ ]]; then
            if (( EXISTING_PKGREL >= TARGET_PKGREL )); then
                TARGET_PKGREL=$((EXISTING_PKGREL + 1))
            fi
        elif [[ "${TARGET_PKGREL}" == "${EXISTING_PKGREL}" ]]; then
            echo "Error: Non-integer pkgrel '${EXISTING_PKGREL}' cannot be auto-incremented." >&2
            exit 1
        fi
        sed -i "s|^pkgrel=.*|pkgrel=${TARGET_PKGREL}|" "${REPO_DIR}/PKGBUILD"
        regenerate_srcinfo "${REPO_DIR}"
    fi
fi

git add -- "${FILES_TO_STAGE[@]}"

if [[ "${HAS_HEAD}" -eq 1 ]] && git diff --cached --quiet; then
    echo "No changes to push for ${PKG_NAME}."
    exit 0
fi

FINAL_PKGVER="$(parse_pkgbuild_var "${REPO_DIR}/PKGBUILD" pkgver)"
FINAL_PKGREL="$(parse_pkgbuild_var "${REPO_DIR}/PKGBUILD" pkgrel)"
FINAL_EPOCH="$(parse_pkgbuild_var "${REPO_DIR}/PKGBUILD" epoch)"
FINAL_FULL_VER="$(format_pkg_ver "${FINAL_EPOCH}" "${FINAL_PKGVER}" "${FINAL_PKGREL}")"

if [[ "${HAS_HEAD}" -eq 1 ]]; then
    COMMIT_MSG="Update ${PKG_NAME} to ${FINAL_FULL_VER}"
else
    COMMIT_MSG="Initial import: ${PKG_NAME} (${FINAL_FULL_VER})"
fi

git commit -m "${COMMIT_MSG}"
git push -u origin "HEAD:refs/heads/${AUR_BRANCH}"
echo "=== Published ${PKG_NAME} (${FINAL_FULL_VER}) to ${REPO_URL} (${AUR_BRANCH}) ==="
