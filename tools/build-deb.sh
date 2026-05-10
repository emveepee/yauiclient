#!/usr/bin/env bash
# tools/build-deb.sh
#
# Builds all three yauiclient .deb flavours in one dpkg-buildpackage run:
#   yauiclient-x11             X11 + bundled libmpv
#   yauiclient-wayland         Wayland + bundled libmpv
#   yauiclient-wayland-system  Wayland + system libmpv2
#
# Prerequisites:
#   sdk/ must contain the libmpv SDK + runtime tarballs already extracted.
#   The bundled flavours need this; the system flavour does not, but
#   building the source once produces all three binaries together.
#
#   See Building-on-Linux.md > "Using the Prebuilt SDK (Debian 12, X11+Wayland)"
#   for the canonical extraction procedure, or run with --download to fetch
#   the tarballs automatically.
#
# Usage:
#   ./tools/build-deb.sh                   # assumes sdk/ already populated
#   ./tools/build-deb.sh --download        # fetch v0.41.0 tarballs into sdk/
#   ./tools/build-deb.sh --download v0.40.0  # fetch a specific tag
#
# Output (in bin/):
#   yauiclient-x11_VERSION_amd64.deb
#   yauiclient-wayland_VERSION_amd64.deb
#   yauiclient-wayland-system_VERSION_amd64.deb
#   yauiclient_VERSION_amd64.changes
#   yauiclient_VERSION_amd64.buildinfo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DOWNLOAD=0
LIBMPV_TAG="v0.41.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --download)
            DOWNLOAD=1
            shift
            if [[ $# -gt 0 && "$1" =~ ^v[0-9] ]]; then
                LIBMPV_TAG="$1"
                shift
            fi
            ;;
        -h|--help)
            sed -n '3,32p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$1'" >&2
            echo "Run with -h for usage." >&2
            exit 2
            ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
command -v dpkg-buildpackage >/dev/null 2>&1 \
    || die "dpkg-buildpackage not found. Install with: sudo apt install dpkg-dev devscripts"

# ---------------------------------------------------------------------------
# Optional: download SDK + runtime tarballs
# ---------------------------------------------------------------------------
if [[ "$DOWNLOAD" -eq 1 ]]; then
    BASE="https://raw.githubusercontent.com/wiki/emveepee/libmpv-mingw64-builder"
    SDK_TARBALL="libmpv-sdk-${LIBMPV_TAG}-linux-x86_64-debian12.tar.gz"
    RUNTIME_TARBALL="libmpv-runtime-${LIBMPV_TAG}-linux-x86_64-debian12.tar.gz"

    log "Downloading libmpv SDK + runtime tarballs (${LIBMPV_TAG})"
    rm -rf sdk
    mkdir -p sdk
    curl -fL --retry 3 -o "/tmp/${SDK_TARBALL}" "${BASE}/${SDK_TARBALL}"
    curl -fL --retry 3 -o "/tmp/${RUNTIME_TARBALL}" "${BASE}/${RUNTIME_TARBALL}"

    log "Extracting SDK into sdk/"
    tar xzf "/tmp/${SDK_TARBALL}" -C sdk/

    log "Extracting runtime into sdk/lib/"
    tar xzf "/tmp/${RUNTIME_TARBALL}" -C sdk/lib/

    rm -f "/tmp/${SDK_TARBALL}" "/tmp/${RUNTIME_TARBALL}"
fi

# ---------------------------------------------------------------------------
# Pre-flight: sdk/ sanity (needed for the two bundled flavours)
# ---------------------------------------------------------------------------
[[ -f "sdk/include/mpv/client.h" ]] \
    || die "sdk/include/mpv/client.h not found. Extract the libmpv SDK tarball into sdk/, or run with --download."
[[ -f "sdk/lib/libmpv.so" ]] \
    || die "sdk/lib/libmpv.so not found. Extract the runtime tarball into sdk/lib/."
ls sdk/lib/libdav1d.so.6* >/dev/null 2>&1 \
    || die "sdk/lib/libdav1d.so.6 not found. The runtime tarball appears incomplete."

# ---------------------------------------------------------------------------
# Pre-flight: install build deps if not already present
# ---------------------------------------------------------------------------
log "Checking build dependencies"
MISSING_PKGS=()
for pkg in debhelper-compat cmake ninja-build pkg-config \
           libfmt-dev nlohmann-json3-dev zlib1g-dev \
           libcurl4-openssl-dev libluajit-5.1-dev libass-dev \
           libxss-dev libxpresent-dev \
           libxinerama-dev libxcursor-dev libxi-dev libxkbcommon-dev \
           libwayland-dev libwayland-bin wayland-protocols \
           libmpv-dev unzip dpkg-dev fakeroot; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    log "Installing missing build deps: ${MISSING_PKGS[*]}"
    # When running as root (e.g. in a CI container or fresh debian:12
    # image) sudo is neither available nor needed.
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
    else
        SUDO="sudo"
    fi
    $SUDO apt-get update
    $SUDO apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}"
fi

# ---------------------------------------------------------------------------
# Build GLFW 3.4 from source
# ---------------------------------------------------------------------------
# Debian 12 (bookworm) ships GLFW 3.3.8; yauiclient's Wayland flavour needs
# 3.4 features (GLFW_PLATFORM, GLFW_WAYLAND_APP_ID). bookworm-backports
# does not ship GLFW. So we build 3.4 from source into glfw-prefix/ here
# and CMake picks it up via CMAKE_PREFIX_PATH (set in debian/rules).
#
# Skipped if glfw-prefix/lib/libglfw.so.3 already exists, so repeated runs
# of this script don't waste time recompiling GLFW.
GLFW_VERSION="3.4"
GLFW_PREFIX="$REPO_ROOT/glfw-prefix"
if [[ ! -e "$GLFW_PREFIX/lib/libglfw.so.3" ]]; then
    log "Building GLFW $GLFW_VERSION from source into $GLFW_PREFIX"
    rm -rf "$GLFW_PREFIX" /tmp/glfw-build
    curl -fL --retry 3 -o /tmp/glfw.tar.gz \
        "https://github.com/glfw/glfw/releases/download/${GLFW_VERSION}/glfw-${GLFW_VERSION}.zip" \
      || curl -fL --retry 3 -o /tmp/glfw.tar.gz \
        "https://github.com/glfw/glfw/archive/refs/tags/${GLFW_VERSION}.tar.gz"
    mkdir -p /tmp/glfw-build
    tar xzf /tmp/glfw.tar.gz -C /tmp/glfw-build --strip-components=1 2>/dev/null \
      || (cd /tmp/glfw-build && unzip -q /tmp/glfw.tar.gz && mv glfw-*/* . && rmdir glfw-*)
    cmake -S /tmp/glfw-build -B /tmp/glfw-build/build \
        -DCMAKE_INSTALL_PREFIX="$GLFW_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DGLFW_BUILD_DOCS=OFF \
        -DGLFW_BUILD_TESTS=OFF \
        -DGLFW_BUILD_EXAMPLES=OFF \
        -DGLFW_BUILD_X11=ON \
        -DGLFW_BUILD_WAYLAND=ON \
        -G Ninja
    cmake --build /tmp/glfw-build/build --parallel "$(nproc)"
    cmake --install /tmp/glfw-build/build
    rm -rf /tmp/glfw-build /tmp/glfw.tar.gz
    log "GLFW $GLFW_VERSION installed at $GLFW_PREFIX"
else
    log "GLFW already built at $GLFW_PREFIX (delete to force rebuild)"
fi

# Export the prefix so debian/rules can pick it up via CMAKE_PREFIX_PATH
export YAUI_GLFW_PREFIX="$GLFW_PREFIX"

# ---------------------------------------------------------------------------
# Build all three .debs in one dpkg-buildpackage run
# ---------------------------------------------------------------------------
log "Running dpkg-buildpackage (-b -uc -us, $(nproc) jobs)"
dpkg-buildpackage -b -uc -us -j"$(nproc)"

# ---------------------------------------------------------------------------
# Collect artefacts
# ---------------------------------------------------------------------------
mkdir -p bin
shopt -s nullglob
moved=0
for f in ../yauiclient*_*.deb ../yauiclient_*.changes ../yauiclient_*.buildinfo; do
    mv "$f" bin/
    moved=$((moved + 1))
done
shopt -u nullglob

[[ "$moved" -gt 0 ]] || die "No build artefacts found in parent directory. Did dpkg-buildpackage fail silently?"

log "Build complete:"
ls -la bin/yauiclient*.deb 2>/dev/null || true

# ---------------------------------------------------------------------------
# Optional lintian scan (informational)
# ---------------------------------------------------------------------------
if command -v lintian >/dev/null 2>&1; then
    log "Running lintian (informational only)"
    for f in bin/yauiclient*.deb; do
        echo "--- lintian on $f ---"
        lintian --no-tag-display-limit "$f" || true
    done
fi

cat <<EOF

Done. Three flavours built:
  bin/yauiclient-x11_*.deb              X11 + bundled libmpv
  bin/yauiclient-wayland_*.deb          Wayland + bundled libmpv
  bin/yauiclient-wayland-system_*.deb   Wayland + system libmpv2

Install ONE flavour (they conflict with each other):
  sudo dpkg -i bin/yauiclient-wayland_*.deb && sudo apt-get install -f

EOF
