#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${VERSION:-1.0.0}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
WORK_DIR="$(mktemp -d /tmp/tsuki-rpm-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Fedora RPM Package (v${VERSION}) ==="
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}/SOURCES" "${WORK_DIR}/SPECS" "${WORK_DIR}/BUILD" "${WORK_DIR}/RPMS" "${WORK_DIR}/SRPMS"

# Create source tarball
tar -czf "${WORK_DIR}/SOURCES/tsuki-${VERSION}.tar.gz" -C "${ROOT_DIR}" \
    --exclude-vcs \
    --exclude='./build*' \
    --exclude='./dist*' \
    --exclude='./.temp*' \
    --transform "s,^\.,tsuki-${VERSION}," .

cp "${ROOT_DIR}/packaging/fedora/tsuki.spec" "${WORK_DIR}/SPECS/"
sed -i "s/^Version:.*/Version:        ${VERSION}/" "${WORK_DIR}/SPECS/tsuki.spec"

rpmbuild --define "_topdir ${WORK_DIR}" -ba "${WORK_DIR}/SPECS/tsuki.spec"

RPM_FILE=$(find "${WORK_DIR}/RPMS" -type f -name "*.rpm" ! -name "*-debuginfo-*" ! -name "*-debugsource-*" | head -n 1)
if [[ -n "${RPM_FILE}" && -f "${RPM_FILE}" ]]; then
    cp "${RPM_FILE}" "${OUTPUT_DIR}/"
    echo "=== Fedora RPM created: ${OUTPUT_DIR}/$(basename "${RPM_FILE}") ==="
else
    echo "Error: Failed to find generated RPM package." >&2
    exit 1
fi

