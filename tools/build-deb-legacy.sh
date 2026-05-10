#!/usr/bin/env bash
# tools/build-deb-legacy.sh
#
# Builds the yauiclient-x11-legacy .deb on Debian 11 (or in a Debian 11
# container). Targets X11-only with bundled libmpv 0.41.0 + FFmpeg 7.1.1
# for systems on glibc 2.31+ (Debian 11+, Ubuntu 20.04+, Mint 20+).
#
# How it works:
#   dpkg-buildpackage hardcodes the 'debian/' directory name, so this
#   script temporarily swaps debian/ <-> debian-legacy/ for the duration
#   of the build. The swap is reversed by an EXIT trap whether the build
#   succeeds or fails.
#
# Prerequisites:
#   sdk/ must contain the LEGACY libmpv SDK + runtime tarballs (no
#   '-debian12' suffix). See Building-on-Linux.md > "Using the Prebuilt
#   Linux SDK" for the canonical extraction procedure, or run with
#   --download to fetch them automatically.
#
# Usage:
#   ./tools/build-deb-legacy.sh                   # assume sdk/ populated
#   ./tools/build-deb-legacy.sh --download        # fetch v0.41.0 legacy
#   ./tools/build-deb-legacy.sh --download v0.40.0
#
# Output:
#   bin/yauiclient-x11-legacy_VERSION_amd64.deb
#   bin/yauiclient_VERSION_amd64.changes
#   bin/yauiclient_VERSION_amd64.buildinfo

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
            sed -n '3,29p' "$0"
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

[[ -d debian-legacy ]] \
    || die "debian-legacy/ not found at $PWD. This script must run from the yauiclient repo root."

# ---------------------------------------------------------------------------
# Optional: download SDK + runtime tarballs (LEGACY = no -debian12 suffix)
# ---------------------------------------------------------------------------
if [[ "$DOWNLOAD" -eq 1 ]]; then
    BASE="https://raw.githubusercontent.com/wiki/emveepee/libmpv-mingw64-builder"
    SDK_TARBALL="libmpv-sdk-${LIBMPV_TAG}-linux-x86_64.tar.gz"
    RUNTIME_TARBALL="libmpv-runtime-${LIBMPV_TAG}-linux-x86_64.tar.gz"

    log "Downloading legacy libmpv SDK + runtime tarballs (${LIBMPV_TAG})"
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
# Pre-flight: sdk/ sanity
# ---------------------------------------------------------------------------
[[ -f "sdk/include/mpv/client.h" ]] \
    || die "sdk/include/mpv/client.h not found. Extract the legacy libmpv SDK tarball into sdk/, or run with --download."
[[ -f "sdk/lib/libmpv.so" ]] \
    || die "sdk/lib/libmpv.so not found. Extract the legacy runtime tarball into sdk/lib/."

# ---------------------------------------------------------------------------
# Pre-flight: install build deps if missing (Debian 11 packages)
# ---------------------------------------------------------------------------
log "Checking build dependencies"
MISSING_PKGS=()
for pkg in debhelper-compat cmake ninja-build pkg-config \
           libglfw3-dev libfmt-dev nlohmann-json3-dev zlib1g-dev \
           libcurl4-openssl-dev libluajit-5.1-dev libass-dev \
           libxss-dev libxpresent-dev \
           libva-dev libvdpau-dev liblcms2-dev libbluray-dev \
           libjpeg62-turbo-dev \
           dpkg-dev fakeroot; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    log "Installing missing build deps: ${MISSING_PKGS[*]}"
    # When running as root (e.g. in a CI container or fresh debian:11
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
# Atomic swap: debian/ <-> debian-legacy/
# ---------------------------------------------------------------------------
SAVED_DEBIAN=""

restore_debian() {
    if [[ -d debian-legacy.tmp ]]; then
        # Build is over (or aborted). Move our debian-legacy back, restore
        # the saved debian/ if there was one.
        if [[ -d debian ]]; then
            mv debian debian-legacy
        fi
        mv debian-legacy.tmp debian-legacy 2>/dev/null || true
    fi
    if [[ -n "$SAVED_DEBIAN" && -d "$SAVED_DEBIAN" ]]; then
        rm -rf debian
        mv "$SAVED_DEBIAN" debian
        SAVED_DEBIAN=""
    fi
}
trap restore_debian EXIT INT TERM

# Set aside the existing debian/ (the modern one) if it's there.
if [[ -d debian ]]; then
    SAVED_DEBIAN="debian.saved.$$"
    mv debian "$SAVED_DEBIAN"
fi

# Swap debian-legacy into place. We rename to .tmp first so that if
# dpkg-buildpackage is interrupted while reading, the trap can put things
# back deterministically.
mv debian-legacy debian-legacy.tmp
cp -a debian-legacy.tmp debian

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
log "Running dpkg-buildpackage (-b -uc -us, $(nproc) jobs) — legacy flavour"
dpkg-buildpackage -b -uc -us -j"$(nproc)"

# ---------------------------------------------------------------------------
# Restore debian/ tree before collecting artefacts (the trap will also do
# this on early exit, but we need the saved debian back before packing
# results into bin/ which lives under the source tree).
# ---------------------------------------------------------------------------
rm -rf debian
mv debian-legacy.tmp debian-legacy
if [[ -n "$SAVED_DEBIAN" ]]; then
    mv "$SAVED_DEBIAN" debian
    SAVED_DEBIAN=""
fi
trap - EXIT INT TERM

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
ls -la bin/yauiclient-x11-legacy*.deb 2>/dev/null || true

# ---------------------------------------------------------------------------
# Optional lintian
# ---------------------------------------------------------------------------
if command -v lintian >/dev/null 2>&1; then
    log "Running lintian (informational only)"
    lintian --no-tag-display-limit bin/yauiclient-x11-legacy*.deb || true
fi

cat <<EOF

Done. Legacy flavour built:
  bin/yauiclient-x11-legacy_*.deb       Debian 11 X11 + bundled libmpv

Install:
  sudo dpkg -i bin/yauiclient-x11-legacy_*.deb && sudo apt-get install -f

EOF
