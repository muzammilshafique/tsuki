# Tsuki

A Linux game launcher for Wine, Proton, native Linux games, and the Epic Games Store, written in C++20 and Qt 6 / QML.

## Screenshots

![Library view](packaging/screenshots/1.png)

![Game details and settings](packaging/screenshots/2.png)

## Features

- Manage Windows games (Wine / Proton), native Linux games, and Epic Games titles in one library with **custom collections**, multi-select filters, and **hidden games** support
- **Native Epic Games Store integration** (100% C++20/Qt6 — zero `QtWebEngine` or external CLI required):
  - External-browser OAuth sign-in, persistent session refresh, sign-out confirmation, and **secure credential storage** via Freedesktop Secret Service (`libsecret` with strict `0600` file fallback)
  - Native binary/JSON manifest parsing, multi-threaded zlib/SHA-1 chunk downloading, persistent pause/resume across restarts, file verification, optional install tags, update detection with **smaller delta downloads**, and automatic **prerequisites installation**
  - **Epic Cloud Saves**: automatic pre-launch sync and post-exit upload, conflict resolution prompt, automatic local `.tar.gz` safety snapshots with 1-click restore, and custom save folder overrides
  - Persistent disk caching and lazy viewport loading for Epic library artwork, plus optional automatic SteamGridDB / Steam Store artwork fetching after downloads
  - **Import existing installations** (e.g. Heroic Games Launcher folders) with **Copy**, **Move**, or **Keep in Place** transfer modes, runner/prefix selection, and optional disk cleanup when uninstalling
  - Online multiplayer support via OAuth exchange codes, native **EOS Social Overlay** installation & prefix registry management, hiding games, automatic non-game app filtering, and toggleable Epic badges
- **Downloads Manager**: dedicated downloads queue with concurrency limits, chunk worker tuning, speed throttling, and automatic pause while a game is running
- **UMU Launcher & Modern Linux Gaming**: integrated `umu-run` / Steam Linux Runtime 3.0 support with automatic UMU ID resolution, **NTSYNC**, **Proton Wayland driver**, **HDR**, **NVIDIA NVAPI**, **Wine Fullscreen FSR**, and per-game or global **GPU selection** (NVIDIA PRIME offload, `DRI_PRIME`, and DXVK/VKD3D device filtering)
- Download and manage **Proton-GE** and **Proton-CachyOS** runners (`x86-64-v3` CPU detection and SHA-512 verification), use system Wine and Steam Proton installations, and remove runners (with Steam runner deletion gated in Settings)
- Auto-detect or 1-click install **Proton EasyAntiCheat (EAC)** and **BattlEye** anti-cheat runtimes for Epic games
- Create, clone, back up, restore, and clean shader/temp caches for isolated Wine prefixes, plus **game folder relocation**
- Built-in **Winetricks** component installer and Settings **Storage Cleaning** (logs, cache, unused artwork & manifests, prefix caches)
- Automatic cover, banner, logo, and icon fetching via SteamGridDB / Steam Store
- Virtual Xbox 360 controller emulation over `/dev/uinput` (with udev rule included)
- Optional **MangoHud**, **Feral GameMode**, and **Gamescope** microcompositor integration
- System diagnostics, per-game launch logs, custom GPU rounded-cover shader (`0 FBO` cards at rest), and smooth synced sidebar/grid transitions
- Full Keyboard & Gamepad navigation support across the launcher (PlayStation and Xbox prompts)

## Installation

### Arch Linux

**From GitHub Releases (`.pkg.tar.zst`)**

Download the latest `.pkg.tar.zst` from the [Releases](https://github.com/muzammilshafique/tsuki/releases) page and install it:

```bash
sudo pacman -U ./tsuki-*.pkg.tar.zst
```

**From the AUR**

```bash
# Prebuilt binary from the latest GitHub release
yay -S tsuki-bin

# Build from the latest git commit
yay -S tsuki-git
```

Support is also provided for **AppImage**, **Ubuntu / Debian (`.deb`)**, and **Fedora (`.rpm`)**:

### AppImage (Universal Linux)

Download the `.AppImage` from the [Releases](https://github.com/muzammilshafique/tsuki/releases) page (works on most distributions including Ubuntu 22.04+, Debian 12+, Fedora, Arch, and SteamOS):

```bash
chmod +x ./Tsuki-*-x86_64.AppImage
./Tsuki-*-x86_64.AppImage
```

### Ubuntu / Debian

Download the `.deb` package from the [Releases](https://github.com/muzammilshafique/tsuki/releases) page (requires Qt 6.8+, e.g. Ubuntu 25.10+ / 26.04 LTS or Debian 13 Trixie) and install it:

```bash
sudo apt install ./tsuki_*_amd64.deb
```

### Fedora

Download the `.rpm` package from the [Releases](https://github.com/muzammilshafique/tsuki/releases) page and install it:

```bash
sudo dnf install ./tsuki-*.x86_64.rpm
```

## Building from Source

### Dependencies

**Arch Linux:**

```bash
sudo pacman -S cmake ninja pkgconf qt6-base qt6-declarative qt6-svg sdl2 zlib hicolor-icon-theme tar
```

**Ubuntu / Debian:**

```bash
sudo apt install cmake ninja-build pkg-config g++ qt6-base-dev qt6-declarative-dev qt6-svg-dev qt6-qpa-plugins qt6-svg-plugins libqt6sql6-sqlite qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-effects libsdl2-dev zlib1g-dev libgl-dev hicolor-icon-theme tar
```

**Fedora:**

```bash
sudo dnf install cmake ninja-build gcc-c++ pkgconf-pkg-config qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel 'pkgconfig(sdl2)' 'pkgconfig(zlib)' hicolor-icon-theme tar
```

Optional runtime packages: `wine`, `winetricks`, `mangohud`, `gamemode`, `gamescope`, `7zip` (`p7zip`), `vulkan-icd-loader` (`vulkan-tools` / `vulkan-loader`), and `ttf-jetbrains-mono-nerd` (Arch).

### Build, Test, and Install

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build
ctest --test-dir build --output-on-failure
sudo cmake --install build
```

## License

Licensed under the [GNU General Public License v3.0 or later](LICENSE).

