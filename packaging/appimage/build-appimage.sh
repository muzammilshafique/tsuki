#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION" 2>/dev/null || git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || echo '0.2.3')"
RAW_VERSION="${VERSION:-${DEFAULT_VERSION}}"
RAW_VERSION="${RAW_VERSION#v}"
ARCH="${APPIMAGE_ARCH:-x86_64}"
OUTPUT_DIR="${1:-${ROOT_DIR}/dist}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"
WORK_DIR="$(mktemp -d /tmp/tsuki-appimage-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Tsuki AppImage (${RAW_VERSION}, arch ${ARCH}) ==="
mkdir -p "${WORK_DIR}/build" "${WORK_DIR}/AppDir" "${WORK_DIR}/tools" \
    "${WORK_DIR}/test-home/.config" "${WORK_DIR}/test-home/.local/share" "${WORK_DIR}/test-home/.cache"

QT_ROOT="${QT_DIR:-${Qt6_DIR:-}}"
if [[ -n "${QT_ROOT}" ]]; then
    export PATH="${QT_ROOT}/bin:${PATH}"
    export CMAKE_PREFIX_PATH="${QT_ROOT}:${CMAKE_PREFIX_PATH:-}"
    export LD_LIBRARY_PATH="${QT_ROOT}/lib:${LD_LIBRARY_PATH:-}"
fi

QMAKE_BIN="${QMAKE:-}"
if [[ -z "${QMAKE_BIN}" ]]; then
    if command -v qmake6 >/dev/null 2>&1; then
        QMAKE_BIN="$(command -v qmake6)"
    elif command -v qmake >/dev/null 2>&1; then
        QMAKE_BIN="$(command -v qmake)"
    fi
fi

if [[ -z "${QMAKE_BIN}" ]]; then
    echo "Error: Could not find qmake/qmake6. Set QT_DIR or QMAKE to your Qt 6 installation." >&2
    exit 1
fi
export QMAKE="${QMAKE_BIN}"
QT_PLUGINS_DIR="$("${QMAKE}" -query QT_INSTALL_PLUGINS)"

# Stage a filtered Qt plugins tree so linuxdeploy-plugin-qt does not try to deploy
# unused SQL drivers (e.g. libqsqlmysql.so needing libmysqlclient.so.21).
STAGED_QT_PLUGINS="${WORK_DIR}/qt-plugins"
mkdir -p "${STAGED_QT_PLUGINS}"
for entry in "${QT_PLUGINS_DIR}"/*; do
    [[ -e "${entry}" ]] || continue
    name="$(basename "${entry}")"
    if [[ "${name}" == "sqldrivers" ]]; then
        if [[ -f "${entry}/libqsqlite.so" ]]; then
            mkdir -p "${STAGED_QT_PLUGINS}/sqldrivers"
            cp -a "${entry}/libqsqlite.so" "${STAGED_QT_PLUGINS}/sqldrivers/libqsqlite.so"
        fi
    else
        ln -sf "${entry}" "${STAGED_QT_PLUGINS}/${name}"
    fi
done

mkdir -p "${WORK_DIR}/bin"
QMAKE_WRAPPER="${WORK_DIR}/bin/qmake"
cat << EOF > "${QMAKE_WRAPPER}"
#!/usr/bin/env bash
if [[ "\${1:-}" == "-query" ]]; then
    if [[ "\${2:-}" == "QT_INSTALL_PLUGINS" ]]; then
        printf '%s\n' "${STAGED_QT_PLUGINS}"
    else
        "${QMAKE_BIN}" "\$@" | sed "s|^QT_INSTALL_PLUGINS:.*|QT_INSTALL_PLUGINS:${STAGED_QT_PLUGINS}|"
    fi
else
    exec "${QMAKE_BIN}" "\$@"
fi
EOF
chmod +x "${QMAKE_WRAPPER}"
export QMAKE="${QMAKE_WRAPPER}"

cmake -S "${ROOT_DIR}" -B "${WORK_DIR}/build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DINSTALL_UDEV_RULES=OFF \
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

APPDIR="${WORK_DIR}/AppDir"
DESTDIR="${APPDIR}" cmake --install "${WORK_DIR}/build"

TOOLS_DIR="${LINUXDEPLOY_DIR:-${WORK_DIR}/tools}"
mkdir -p "${TOOLS_DIR}"

fetch_tool() {
    local url="$1"
    local dest="$2"
    if [[ ! -x "${dest}" ]]; then
        echo "Downloading $(basename "${dest}")..."
        curl -fsSL --retry 3 --retry-delay 3 "${url}" -o "${dest}"
        chmod +x "${dest}"
    fi
}

LINUXDEPLOY_BIN="${TOOLS_DIR}/linuxdeploy-${ARCH}.AppImage"
QT_PLUGIN_BIN="${TOOLS_DIR}/linuxdeploy-plugin-qt-${ARCH}.AppImage"
APPIMAGE_PLUGIN_BIN="${TOOLS_DIR}/linuxdeploy-plugin-appimage-${ARCH}.AppImage"

fetch_tool "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${ARCH}.AppImage" "${LINUXDEPLOY_BIN}"
fetch_tool "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-${ARCH}.AppImage" "${QT_PLUGIN_BIN}"
fetch_tool "https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-${ARCH}.AppImage" "${APPIMAGE_PLUGIN_BIN}"

ln -sf "${QT_PLUGIN_BIN}" "${TOOLS_DIR}/linuxdeploy-plugin-qt"
ln -sf "${APPIMAGE_PLUGIN_BIN}" "${TOOLS_DIR}/linuxdeploy-plugin-appimage"
export PATH="${TOOLS_DIR}:${PATH}"

# Copy icon outside AppDir with desktop-matching basename so linuxdeploy never copies onto itself
cp -f "${ROOT_DIR}/resources/icons/brand/tsuki.svg" "${WORK_DIR}/io.github.muzammilshafique.tsuki.svg"

export APPIMAGE_EXTRACT_AND_RUN=1
export QML_SOURCES_PATHS="${ROOT_DIR}/src/qml"
export EXTRA_QT_MODULES="svg"
export EXTRA_PLATFORM_PLUGINS="libqwayland-egl.so;libqwayland-generic.so;libqoffscreen.so"

"${LINUXDEPLOY_BIN}" \
    --appdir "${APPDIR}" \
    --executable "${APPDIR}/usr/bin/tsuki" \
    --desktop-file "${ROOT_DIR}/packaging/desktop/io.github.muzammilshafique.tsuki.desktop" \
    --icon-file "${WORK_DIR}/io.github.muzammilshafique.tsuki.svg" \
    --plugin qt

# Ensure critical Qt runtime plugins (HTTPS/TLS, SQLite, SVG icons, image formats) are bundled
ensure_qt_plugin() {
    local rel_path="$1"
    local src="${QT_PLUGINS_DIR}/${rel_path}"
    local dst="${APPDIR}/usr/plugins/${rel_path}"
    if [[ -f "${src}" && ! -f "${dst}" ]]; then
        mkdir -p "$(dirname "${dst}")"
        cp -a "${src}" "${dst}"
        "${LINUXDEPLOY_BIN}" --appdir "${APPDIR}" --deploy-deps-only "${dst}" || true
    fi
}

ensure_qt_plugin "sqldrivers/libqsqlite.so"
ensure_qt_plugin "tls/libqopensslbackend.so"
ensure_qt_plugin "iconengines/libqsvgicon.so"
ensure_qt_plugin "imageformats/libqsvg.so"
ensure_qt_plugin "imageformats/libqjpeg.so"
ensure_qt_plugin "imageformats/libqico.so"
ensure_qt_plugin "imageformats/libqwebp.so"
if [[ -d "${QT_PLUGINS_DIR}/networkinformation" ]]; then
    for f in "${QT_PLUGINS_DIR}/networkinformation/"*.so; do
        [[ -f "${f}" ]] && ensure_qt_plugin "networkinformation/$(basename "${f}")"
    done
fi

OUTPUT_APPIMAGE="${OUTPUT_DIR}/Tsuki-${RAW_VERSION}-${ARCH}.AppImage"
export LDAI_OUTPUT="${OUTPUT_APPIMAGE}"
export VERSION="${RAW_VERSION}"

"${LINUXDEPLOY_BIN}" \
    --appdir "${APPDIR}" \
    --output appimage

if [[ ! -f "${OUTPUT_APPIMAGE}" ]]; then
    echo "Error: Expected AppImage not created at ${OUTPUT_APPIMAGE}" >&2
    exit 1
fi
chmod +x "${OUTPUT_APPIMAGE}"

echo "=== AppImage created: ${OUTPUT_APPIMAGE} ==="
