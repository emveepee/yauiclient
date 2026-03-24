#!/usr/bin/env bash
# build-linux.sh
# Builds yauiclient on Linux (Ubuntu/Debian or Arch)
#
# Prerequisites - Ubuntu/Debian:
#   sudo apt install -y \
#     build-essential cmake ninja-build pkg-config git curl \
#     libglfw3-dev libfmt-dev nlohmann-json3-dev zlib1g-dev \
#     libcurl4-dev libluajit-5.1-dev libass-dev libbluray-dev \
#     libjpeg62-turbo
#
# Prerequisites - Arch:
#   sudo pacman -S --needed \
#     base-devel cmake ninja pkgconf git curl \
#     glfw fmt nlohmann-json zlib curl \
#     luajit libass libbluray libjpeg-turbo
#
# Note: cpr is fetched and built automatically via CMake FetchContent.
# See https://github.com/emveepee/yauiclient#dependencies for full details.
#
# SDK setup (required before building):
#   Download the SDK and runtime tarballs from:
#     https://github.com/emveepee/libmpv-mingw64-builder/wiki/Building-on-Linux
#   Extract both to sdk/ in the repo root:
#     tar xzf libmpv-sdk-vX.X.X-linux-x86_64.tar.gz -C sdk/
#     tar xzf libmpv-runtime-vX.X.X-linux-x86_64.tar.gz -C sdk/
#
# Usage:
#   ./tools/build-linux.sh [Release|Debug]
#
# Environment:
#   YAUICLIENT_USE_SYSTEM_MPV=1   use system libmpv instead of sdk/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_TYPE="${1:-Release}"
USE_SYSTEM_MPV="${YAUICLIENT_USE_SYSTEM_MPV:-0}"
BUILD_DIR="$REPO_ROOT/build/linux-${BUILD_TYPE}"
OUT_DIR="$REPO_ROOT/bin/${BUILD_TYPE}"
SDK_DIR="$REPO_ROOT/sdk"
ARCH="$(uname -m)"
JOBS="${JOBS:-$(nproc)}"

log() { printf "\n==> %s\n" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Detect distro
# ---------------------------------------------------------------------------
if command -v apt-get &>/dev/null; then
  DISTRO="debian"
elif command -v pacman &>/dev/null; then
  DISTRO="arch"
else
  DISTRO="unknown"
fi
log "Distro: $DISTRO, Arch: $ARCH, Build type: $BUILD_TYPE"

# ---------------------------------------------------------------------------
# Validate tools
# ---------------------------------------------------------------------------
command -v cmake  &>/dev/null || die "cmake not found - install build tools first"
command -v ninja  &>/dev/null || die "ninja not found - install ninja-build"

# ---------------------------------------------------------------------------
# Determine MPV flags
# ---------------------------------------------------------------------------
if [[ "$USE_SYSTEM_MPV" == "1" ]]; then
  pkg-config --exists mpv 2>/dev/null || die "system libmpv not found via pkg-config"
  MPV_FLAGS="-DYAUICLIENT_USE_SYSTEM_MPV=ON"
  log "Using system libmpv"
else
  [[ -f "$SDK_DIR/include/mpv/client.h" ]] || die \
"libmpv SDK not found at $SDK_DIR
Download the SDK tarball from the wiki and extract it:
  tar xzf libmpv-sdk-vX.X.X-linux-${ARCH}.tar.gz -C sdk/
  https://github.com/emveepee/libmpv-mingw64-builder/wiki/Building-on-Linux"
  MPV_FLAGS="-DLIBMPV_SDK_DIR=$SDK_DIR"
  log "Using SDK libmpv: $SDK_DIR"
fi

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------
log "Configuring yauiclient ($BUILD_TYPE)"
mkdir -p "$BUILD_DIR"

cmake -B "$BUILD_DIR" -S "$REPO_ROOT" \
  -G "Ninja" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  $MPV_FLAGS

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
log "Building yauiclient"
cmake --build "$BUILD_DIR" --parallel "$JOBS"

# ---------------------------------------------------------------------------
# Assemble output
# ---------------------------------------------------------------------------
mkdir -p "$OUT_DIR"
cp -f "$BUILD_DIR/yauiclient" "$OUT_DIR/"

if [[ "$USE_SYSTEM_MPV" != "1" ]]; then
  # Copy libmpv.so and versioned symlinks
  find "$SDK_DIR/lib" -name "libmpv.so*" -exec cp -Pf {} "$OUT_DIR/" \;

  # Copy runtime FFmpeg libs from sdk/lib if present (SDK runtime tarball)
  for lib in \
      libavcodec libavformat libavutil \
      libavfilter libswresample libswscale; do
    find "$SDK_DIR/lib" -name "${lib}.so*" -exec cp -Pf {} "$OUT_DIR/" \; 2>/dev/null || true
  done

  # Copy libplacebo if present in sdk/lib
  find "$SDK_DIR/lib" -name "libplacebo.so*" -exec cp -Pf {} "$OUT_DIR/" \; 2>/dev/null || true

  if ! ls "$OUT_DIR"/libmpv.so* &>/dev/null; then
    log "WARNING: libmpv.so not found in $OUT_DIR - yauiclient will fail to start"
    log "  Extract the runtime tarball to sdk/:"
    log "  tar xzf libmpv-runtime-vX.X.X-linux-${ARCH}.tar.gz -C sdk/"
  fi
fi

log "Build complete: $OUT_DIR/yauiclient"