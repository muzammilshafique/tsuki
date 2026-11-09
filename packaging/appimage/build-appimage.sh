#!/usr/bin/env bash
set -euo pipefail

# Tsuki AppImage Build Script
# Usage: ./packaging/appimage/build-appimage.sh [build_dir] [output_file]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${1:-${ROOT_DIR}/build}"
VERSION="${VERSION:-1.0.0}"
OUTPUT_FILE="${2:-${ROOT_DIR}/Tsuki-${VERSION}-x86_64.AppImage}"
WORK_DIR="$(mktemp -d /tmp/tsuki-appimage-build.XXXXXX)"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "=== Building Tsuki AppImage (v${VERSION}) ==="
echo "Source: ${ROOT_DIR}"
echo "Build Dir: ${BUILD_DIR}"
echo "Output: ${OUTPUT_FILE}"

APPDIR="${WORK_DIR}/AppDir"
mkdir -p "${APPDIR}"

# Ensure project is built
if [[ ! -f "${BUILD_DIR}/tsuki" ]]; then
    echo "Executable ${BUILD_DIR}/tsuki not found. Configuring and building..."
    cmake -B "${BUILD_DIR}" -S "${ROOT_DIR}" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build "${BUILD_DIR}"
fi

# Install project into AppDir
DESTDIR="${APPDIR}" cmake --install "${BUILD_DIR}"

# Setup root symlinks and AppRun
ln -sf usr/share/applications/tsuki.desktop "${APPDIR}/tsuki.desktop"
ln -sf usr/share/icons/hicolor/256x256/apps/tsuki.png "${APPDIR}/tsuki.png"
ln -sf tsuki.png "${APPDIR}/.DirIcon"

cat << 'EOF' > "${APPDIR}/AppRun"
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export APPDIR="${HERE}"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="${HERE}/usr/plugins:${QT_PLUGIN_PATH}"
export QML2_IMPORT_PATH="${HERE}/usr/qml:${QML2_IMPORT_PATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS}"
exec "${HERE}/usr/bin/tsuki" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

# Deploy Qt Plugins
PLUGINS_DEST="${APPDIR}/usr/plugins"
mkdir -p "${PLUGINS_DEST}/platforms" "${PLUGINS_DEST}/imageformats" "${PLUGINS_DEST}/sqldrivers" "${PLUGINS_DEST}/tls" "${PLUGINS_DEST}/wayland-shell-integration"

QT_PLUGIN_DIR=""
for candidate in \
    "$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)" \
    "$(qmake -query QT_INSTALL_PLUGINS 2>/dev/null || true)" \
    "/usr/lib/x86_64-linux-gnu/qt6/plugins" \
    "/usr/lib64/qt6/plugins" \
    "/usr/lib/qt6/plugins"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
        QT_PLUGIN_DIR="${candidate}"
        break
    fi
done

if [[ -n "${QT_PLUGIN_DIR}" ]]; then
    echo "Found Qt plugins at: ${QT_PLUGIN_DIR}"
    cp -L "${QT_PLUGIN_DIR}/platforms"/libqxcb*.so "${PLUGINS_DEST}/platforms/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/platforms"/libqwayland*.so "${PLUGINS_DEST}/platforms/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/platforms"/libqoffscreen*.so "${PLUGINS_DEST}/platforms/" 2>/dev/null || true
    cp -rL "${QT_PLUGIN_DIR}/wayland-shell-integration"/* "${PLUGINS_DEST}/wayland-shell-integration/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/imageformats"/libqsvg*.so "${PLUGINS_DEST}/imageformats/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/imageformats"/libqjpeg*.so "${PLUGINS_DEST}/imageformats/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/imageformats"/libqpng*.so "${PLUGINS_DEST}/imageformats/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/sqldrivers"/libqsqlite*.so "${PLUGINS_DEST}/sqldrivers/" 2>/dev/null || true
    cp -L "${QT_PLUGIN_DIR}/tls"/libqopensslbackend*.so "${PLUGINS_DEST}/tls/" 2>/dev/null || true
fi

# Deploy Qt QML Modules
QML_DEST="${APPDIR}/usr/qml"
mkdir -p "${QML_DEST}"
QT_QML_DIR=""
for candidate in \
    "$(qmake6 -query QT_INSTALL_QML 2>/dev/null || true)" \
    "$(qmake -query QT_INSTALL_QML 2>/dev/null || true)" \
    "/usr/lib/x86_64-linux-gnu/qt6/qml" \
    "/usr/lib64/qt6/qml" \
    "/usr/lib/qt6/qml"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
        QT_QML_DIR="${candidate}"
        break
    fi
done

if [[ -n "${QT_QML_DIR}" ]]; then
    echo "Found Qt QML modules at: ${QT_QML_DIR}"
    for mod in QtQuick Qt; do
        if [[ -d "${QT_QML_DIR}/${mod}" && ! -d "${QML_DEST}/${mod}" ]]; then
            cp -rL "${QT_QML_DIR}/${mod}" "${QML_DEST}/"
        fi
    done
fi

# Bundle Shared Libraries using Python dependency scanner
python3 - "${APPDIR}" << 'PYEOF'
import os, sys, shutil, subprocess

appdir = sys.argv[1]
lib_dest = os.path.join(appdir, "usr/lib")
os.makedirs(lib_dest, exist_ok=True)

elf_files = []
for root, dirs, files in os.walk(appdir):
    for f in files:
        full = os.path.join(root, f)
        if not os.path.islink(full):
            try:
                with open(full, 'rb') as fb:
                    if fb.read(4) == b'\x7fELF':
                        elf_files.append(full)
            except:
                pass

EXCLUDE_PREFIXES = [
    "libc.so", "libm.so", "libdl.so", "librt.so", "libpthread.so",
    "libresolv.so", "libnss", "ld-linux", "libGL.so", "libGLX.so",
    "libOpenGL.so", "libEGL.so", "libdrm.so"
]

def should_exclude(name):
    return any(name.startswith(p) for p in EXCLUDE_PREFIXES)

needed = set()
for elf in elf_files:
    try:
        out = subprocess.check_output(["ldd", elf], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if "=>" in line:
                parts = line.strip().split("=>")
                soname = parts[0].strip()
                tpath = parts[1].strip().split()[0]
                if tpath.startswith("/") and not should_exclude(soname):
                    needed.add(tpath)
    except:
        pass

for p in needed:
    dest = os.path.join(lib_dest, os.path.basename(p))
    if not os.path.exists(dest):
        try:
            shutil.copy2(p, dest)
        except Exception:
            pass
PYEOF

# Download appimagetool if not found
APPIMAGETOOL="${APPIMAGETOOL:-}"
if [[ -z "${APPIMAGETOOL}" ]]; then
    if command -v appimagetool >/dev/null 2>&1; then
        APPIMAGETOOL="appimagetool"
    elif [[ -f "/tmp/test-appimage/tools/appimagetool" ]]; then
        APPIMAGETOOL="/tmp/test-appimage/tools/appimagetool"
    else
        APPIMAGETOOL="${WORK_DIR}/appimagetool"
        echo "Downloading appimagetool..."
        curl -sL -o "${APPIMAGETOOL}" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod +x "${APPIMAGETOOL}"
    fi
fi

# Run appimagetool
export ARCH=x86_64
export APPIMAGE_EXTRACT_AND_RUN=1
echo "Generating AppImage: ${OUTPUT_FILE}"
mkdir -p "$(dirname "${OUTPUT_FILE}")"
"${APPIMAGETOOL}" --no-appstream "${APPDIR}" "${OUTPUT_FILE}"
chmod +x "${OUTPUT_FILE}"

# Smoke test
echo "Verifying generated AppImage..."
QT_QPA_PLATFORM=offscreen "${OUTPUT_FILE}" --smoke-test
echo "=== AppImage build verified successfully: ${OUTPUT_FILE} ==="
