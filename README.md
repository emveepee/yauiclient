# yauiclient

A cross-platform media player client for [NextPVR](https://nextpvr.com), a whole-home digital video recorder available on Windows, Linux, macOS and Docker.

yauiclient uses [libmpv](https://mpv.io) for video playback with an OpenGL overlay rendered from NextPVR's UI, communicating with the NextPVR server over HTTP/JSON. It supports both standard HTTP image transfer and a high-performance shared memory mode for local installations.

> **Status:** Early alpha — not yet suitable for general use.

---

## Features

- Hardware-accelerated video playback via libmpv (VAAPI on Linux, DXVA2/D3D11 on Windows, VideoToolbox on macOS)
- OpenGL overlay driven by NextPVR server UI
- Shared memory (shmem) mode for low-latency local rendering
- Thumbnail strip seek UI
- LiveTV and recording playback
- Blu-ray, teletext (libzvbi) support via custom libmpv build
- Long-press key support for DPAD-only remotes

---

## Supported platforms

| Platform | Status |
|---|---|
| Windows (MSVC) | ✓ Working |
| Windows (MinGW64 / MSYS2) | ✓ Working |
| Linux x86_64 | ✓ Working |
| macOS x86_64 (13.0+) | ✓ Working |
| macOS Apple Silicon | 🔧 Untested |
| Linux aarch64 / RPi | 🔧 In progress |

---

## Repo layout

```
yauiclient/
├── CMakeLists.txt
├── README.md
├── LICENSE
├── src/                  # C++ sources and headers
├── sdk/                  # libmpv SDK - gitignored, populate before building
├── tools/                # build and setup scripts
├── build/                # gitignored - CMake build tree
└── bin/                  # gitignored - executables and runtime libs
```

---

## macOS quick start

**Prerequisites — install Homebrew and dependencies:**

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install cmake ninja pkg-config curl glfw fmt nlohmann-json zlib mpv
```

**Clone and build:**

```bash
git clone https://github.com/emveepee/yauiclient.git
cd yauiclient
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
cmake -B build/macos-Release -S . -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DYAUICLIENT_USE_SYSTEM_MPV=ON
cmake --build build/macos-Release --parallel $(sysctl -n hw.logicalcpu)
```

Output: `build/macos-Release/yauiclient`

**Notes:**
- macOS uses the system libmpv from Homebrew — no SDK tarballs needed
- OpenGL is deprecated on macOS but fully functional on macOS 13.0+
- Shared memory mode requires both the NextPVR server and yauiclient running on the same Mac
- mpv configuration can be placed in `~/.config/mpv/mpv.conf`

**Rebuilding after updates:**

```bash
cmake --build build/macos-Release --parallel $(sysctl -n hw.logicalcpu)
```

Clean rebuild:

```bash
rm -rf build/macos-Release
cmake -B build/macos-Release -S . -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DYAUICLIENT_USE_SYSTEM_MPV=ON
cmake --build build/macos-Release --parallel $(sysctl -n hw.logicalcpu)
```

**Packaging a distributable app bundle:**

```bash
brew install dylibbundler
chmod +x tools/package-macos.sh
./tools/package-macos.sh Release
```

Output: `dist/yauiclient.app` and `dist/yauiclient-macos-x64.tar.gz`

> **Note:** The app bundle is ad-hoc signed but not notarized. On first launch,
> right-click → Open to bypass Gatekeeper, or run:
> ```bash
> xattr -dr com.apple.quarantine /Applications/yauiclient.app
> ```

---

## Linux quick start

**Ubuntu/Debian — install prerequisites:**

```bash
sudo apt install -y \
  build-essential cmake ninja-build pkg-config git curl \
  libglfw3-dev libfmt-dev nlohmann-json3-dev zlib1g-dev \
  libcurl4-dev libluajit-5.1-dev libass-dev libbluray-dev \
  libjpeg62-turbo
```

**Arch — install prerequisites:**

```bash
sudo pacman -S --needed \
  base-devel cmake ninja pkgconf git curl \
  glfw fmt nlohmann-json zlib \
  luajit libass libbluray libjpeg-turbo
```

**Clone and build:**

```bash
# Clone
git clone https://github.com/emveepee/yauiclient.git
cd yauiclient

# Download SDK and runtime tarballs
# Full list at: https://github.com/emveepee/libmpv-mingw64-builder/wiki/Building-on-Linux
curl -L -o /tmp/libmpv-sdk-v0.41.0-linux-x86_64.tar.gz \
  https://raw.githubusercontent.com/wiki/emveepee/libmpv-mingw64-builder/libmpv-sdk-v0.41.0-linux-x86_64.tar.gz
curl -L -o /tmp/libmpv-runtime-v0.41.0-linux-x86_64.tar.gz \
  https://raw.githubusercontent.com/wiki/emveepee/libmpv-mingw64-builder/libmpv-runtime-v0.41.0-linux-x86_64.tar.gz

# Extract to sdk/
tar xzf /tmp/libmpv-sdk-v0.41.0-linux-x86_64.tar.gz -C sdk/
tar xzf /tmp/libmpv-runtime-v0.41.0-linux-x86_64.tar.gz -C sdk/

# Build
chmod +x tools/build-linux.sh
./tools/build-linux.sh Release
```

Output: `bin/Release/yauiclient`

---

## Full build instructions

See [Using the SDK](https://github.com/emveepee/libmpv-mingw64-builder/wiki/Using-the-SDK)
for full per-platform instructions including Windows (MSVC and MinGW64).

---

## Rebuilding after updates

### macOS

```bash
cmake --build build/macos-Release --parallel $(sysctl -n hw.logicalcpu)
```

### Linux

After a `git pull` just re-run the build script — CMake will only recompile changed files:

```bash
./tools/build-linux.sh Release
```

To do a clean rebuild:

```bash
rm -rf build/linux-Release
./tools/build-linux.sh Release
```

### Windows (MSVC)

The first `cmake` run generates `build\windows\yauiclient.sln`. Open it in Visual Studio for all subsequent builds — no need to re-run cmake unless `CMakeLists.txt` changes.

If `CMakeLists.txt` changes, re-run cmake (Visual Studio will also prompt you):

```bat
cmake -B build\windows ^
  -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake ^
  -DLIBMPV_SDK_DIR=%CD%\sdk
```

To do a clean rebuild:

```bat
rmdir /S /Q build\windows
cmake -B build\windows ^
  -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake ^
  -DLIBMPV_SDK_DIR=%CD%\sdk
cmake --build build\windows --config Release
```

### Windows (MinGW64)

After a `git pull`, rebuild with:

```bash
cmake --build build/windows
```

To do a clean rebuild:

```bash
rm -rf build/windows
cmake -B build/windows -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBMPV_SDK_DIR=$PWD/sdk
cmake --build build/windows
```

---

## Using system libmpv (Linux and macOS)

If you prefer the distro/Homebrew-packaged libmpv (no teletext, may be an older version):

**Linux:**
```bash
YAUICLIENT_USE_SYSTEM_MPV=1 ./tools/build-linux.sh Release
```

**macOS:**
```bash
cmake -B build/macos-Release -S . -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DYAUICLIENT_USE_SYSTEM_MPV=ON
```

No SDK or runtime tarballs needed on either platform with this option.

---

## Configuration

yauiclient reads `yauiclient.conf` from the same directory as the executable.
See the wiki for configuration options including NextPVR server address, SSL,
and remote control key mapping.

---

## Dependencies

| Library | How it is provided |
|---|---|
| libmpv | Prebuilt SDK from wiki (Windows/Linux), Homebrew (macOS), or system package |
| FFmpeg | Bundled in libmpv SDK runtime |
| libplacebo | Bundled in libmpv SDK runtime |
| GLFW3 | System package / vcpkg / Homebrew |
| fmt | System package / vcpkg / Homebrew |
| nlohmann-json | System package / vcpkg / Homebrew |
| cpr | Fetched automatically by CMake (FetchContent) |
| libcurl | System package / vcpkg / Homebrew |
| zlib | System package / vcpkg / Homebrew |

---

## License

MIT License — see [LICENSE](LICENSE) for full text.

Copyright (c) 2025-2026 Pinstripe Limited, Wellington, New Zealand
Copyright (c) 2025-2026 Martin Vallevand