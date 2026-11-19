#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RAW_VERSION="${VERSION:-$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || echo '0.1.1')}"
RAW_VERSION="${RAW_VERSION#v}"
RPM_VER="${RAW_VERSION//-/\~}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
WORK_DIR="$(mktemp -d /tmp/tsuki-rpm-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Fedora RPM Package (${RPM_VER} / app version ${RAW_VERSION}) ==="
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

tar -czf "${WORK_DIR}/SOURCES/tsuki-${RPM_VER}.tar.gz" -C "${ROOT_DIR}" \
    --exclude-vcs \
    --exclude='./build*' \
    --exclude='./dist*' \
    --exclude='./.temp*' \
    --exclude='./.qt*' \
    --exclude='./.cache*' \
    --transform "s,^\.,tsuki-${RPM_VER}," .

cp "${ROOT_DIR}/packaging/fedora/tsuki.spec" "${WORK_DIR}/SPECS/tsuki.spec"

rpmbuild -bb \
    --define "_topdir ${WORK_DIR}" \
    --define "pkg_version ${RPM_VER}" \
    --define "app_version ${RAW_VERSION}" \
    "${WORK_DIR}/SPECS/tsuki.spec"

RPM_FILE=$(find "${WORK_DIR}/RPMS" -type f -name "tsuki-${RPM_VER}-*.rpm" ! -name "*-debuginfo-*" ! -name "*-debugsource-*" | head -n 1)
if [[ -n "${RPM_FILE}" && -f "${RPM_FILE}" ]]; then
    cp "${RPM_FILE}" "${OUTPUT_DIR}/"
    echo "=== Fedora RPM package created: ${OUTPUT_DIR}/$(basename "${RPM_FILE}") ==="
else
    echo "Error: Failed to find generated Fedora RPM package." >&2
    exit 1
fi

