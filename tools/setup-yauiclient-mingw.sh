#!/usr/bin/env bash
# setup-yauiclient-mingw.sh
#
# Sets up the yauiclient build environment for MinGW64 (MSYS2).
#
# What this script does:
#   1. Installs all dependencies via pacman (everything except libmpv)
#   2. Copies libmpv runtime DLLs from sdk/ into bin/Debug and bin/Release
#   3. Copies required MinGW runtime DLLs into bin/Debug and bin/Release
#
# Prerequisites:
#   - MSYS2 MinGW64 shell  (https://www.msys2.org)
#   - libmpv SDK tarball extracted to sdk/ in the repo root:
#       Download from https://github.com/emveepee/libmpv-mingw64-builder/wiki
#       Then: tar xzf libmpv-sdk-vX.X.X-windows-x86_64.tar.gz -C sdk/
#   - libmpv runtime tarball extracted to sdk/ in the repo root:
#       tar xzf libmpv-runtime-vX.X.X-windows-x86_64.tar.gz -C sdk/
#
# Usage:
#   Run from the repo root or tools/ directory:
#   ./tools/setup-yauiclient-mingw.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_DIR="$REPO_ROOT/sdk"
MINGW_PREFIX="${MINGW_PREFIX:-/mingw64}"
MINGW_BIN="$MINGW_PREFIX/bin"

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "WARNING: %s\n" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]] \
    || die "Run this script from an MSYS2 MinGW64 shell"

command -v pacman &>/dev/null || die "pacman not found - run from MSYS2 MinGW64 shell"

log "yauiclient MinGW64 setup"
echo "  Repo root   : $REPO_ROOT"
echo "  SDK dir     : $SDK_DIR"
echo "  MinGW prefix: $MINGW_PREFIX"

# ---------------------------------------------------------------------------
# Validate SDK
# ---------------------------------------------------------------------------
[[ -f "$SDK_DIR/include/mpv/client.h" ]] || die \
    "libmpv SDK not found at $SDK_DIR\n" \
    "Download the SDK tarball from the wiki and extract it:\n" \
    "  tar xzf libmpv-sdk-vX.X.X-windows-x86_64.tar.gz -C sdk/"

[[ -f "$SDK_DIR/lib/libmpv.dll.a" ]] || die \
    "libmpv.dll.a not found in $SDK_DIR/lib\n" \
    "Check that the correct Windows SDK tarball was extracted to sdk/"

log "SDK validated: $SDK_DIR"

# ---------------------------------------------------------------------------
# [1/3] Install dependencies via pacman
# ---------------------------------------------------------------------------
log "[1/3] Installing dependencies via pacman..."

PACKAGES=(
    mingw-w64-x86_64-cmake
    mingw-w64-x86_64-ninja
    mingw-w64-x86_64-gcc
    mingw-w64-x86_64-pkg-config
    mingw-w64-x86_64-cpr
    mingw-w64-x86_64-curl
    mingw-w64-x86_64-glew
    mingw-w64-x86_64-glfw
    mingw-w64-x86_64-nlohmann-json
    mingw-w64-x86_64-fmt
    mingw-w64-x86_64-zlib
)

pacman -S --needed --noconfirm "${PACKAGES[@]}"
log "[1/3] pacman dependencies installed OK."

# ---------------------------------------------------------------------------
# [2/3] Copy runtime DLLs into bin/Debug and bin/Release
# ---------------------------------------------------------------------------
log "[2/3] Copying libmpv runtime DLLs to bin/Debug and bin/Release..."

mkdir -p "$REPO_ROOT/bin/Debug"
mkdir -p "$REPO_ROOT/bin/Release"

copied=0
for f in "$SDK_DIR"/*.dll; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "$REPO_ROOT/bin/Debug/"
    cp -f "$f" "$REPO_ROOT/bin/Release/"
    echo "  + $(basename "$f")"
    copied=$(( copied + 1 ))
done
(( copied > 0 )) || warn "No DLLs found in $SDK_DIR - check that the runtime tarball was also extracted"

# ---------------------------------------------------------------------------
# [3/3] Copy MinGW runtime DLLs
# ---------------------------------------------------------------------------
log "[3/3] Copying MinGW runtime DLLs..."

# Note: libgcc_s_seh-1.dll and libstdc++-6.dll are NOT needed since
# libplacebo is self-contained (built with -static-libgcc -static-libstdc++)
RUNTIME_DLLS=(
    libcpr-1.dll
    libcurl-4.dll
    libglew32.dll
    libglfw3.dll
    libfmt-*.dll
    zlib1.dll
    libwinpthread-1.dll
)

copied=0
for pattern in "${RUNTIME_DLLS[@]}"; do
    for f in "$MINGW_BIN"/$pattern; do
        [[ -f "$f" ]] || continue
        cp -f "$f" "$REPO_ROOT/bin/Debug/"
        cp -f "$f" "$REPO_ROOT/bin/Release/"
        echo "  + $(basename "$f")"
        copied=$(( copied + 1 ))
    done
done
log "Copied $copied MinGW runtime DLLs"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Setup complete."
echo ""
echo " sdk/include/mpv/      - libmpv headers"
echo " sdk/lib/              - libmpv.dll.a + libmpv.def"
echo " bin/Debug/            - all runtime DLLs"
echo " bin/Release/          - all runtime DLLs"
echo ""
echo " To build:"
echo "   cmake -B build/windows -G Ninja \\"
echo "         -DCMAKE_BUILD_TYPE=Release \\"
echo "         -DLIBMPV_SDK_DIR=\$PWD/sdk"
echo "   cmake --build build/windows"
echo "============================================================"