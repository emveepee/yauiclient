#!/usr/bin/env bash
# package-macos.sh
# Creates a self-contained yauiclient.app bundle for macOS 13.0+
#
# Prerequisites:
#   brew install dylibbundler
#
# Usage:
#   ./tools/package-macos.sh [Release|Debug]
#
# Output:
#   dist/yauiclient.app          - app bundle
#   dist/yauiclient-macos.tar.gz - distributable archive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_TYPE="${1:-Release}"
BUILD_DIR="$REPO_ROOT/build/macos-${BUILD_TYPE}"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/yauiclient.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

log() { printf "\n==> %s\n" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

BINARY="$BUILD_DIR/yauiclient"
[[ -f "$BINARY" ]] || die "Binary not found at $BUILD_DIR/yauiclient
Build first:
  cmake -B build/macos-${BUILD_TYPE} -S . -G Ninja -DCMAKE_BUILD_TYPE=${BUILD_TYPE} -DLIBMPV_SDK_DIR=\$PWD/sdk
  cmake --build build/macos-${BUILD_TYPE} --parallel \$(sysctl -n hw.logicalcpu)"

command -v dylibbundler &>/dev/null || die "dylibbundler not found — install it:
  brew install dylibbundler"

# Verify SDK runtime dylibs are present
if ! ls "$BUILD_DIR"/libmpv*.dylib &>/dev/null; then
    echo ""
    echo "WARNING: libmpv runtime dylibs not found alongside binary."
    echo "  This appears to be a system/Homebrew mpv build."
    echo "  The resulting bundle will depend on the user having mpv installed via Homebrew."
    echo "  For a fully self-contained bundle with teletext support, extract the runtime tarball:"
    echo "    tar xzf libmpv-runtime-vX.X.X-macos-x86_64.tar.gz -C $BUILD_DIR/"
    echo ""
    read -r -p "Continue anyway? [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]] || die "Aborted."
fi
command -v dylibbundler &>/dev/null || die "dylibbundler not found — install it:
  brew install dylibbundler"

# ---------------------------------------------------------------------------
# Clean and create bundle structure
# ---------------------------------------------------------------------------
log "Creating app bundle structure"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

# ---------------------------------------------------------------------------
# Copy binary
# ---------------------------------------------------------------------------
log "Copying binary"
cp -f "$BINARY" "$MACOS_DIR/yauiclient"

# ---------------------------------------------------------------------------
# Bundle dylibs (walks full dependency tree and fixes rpaths)
# ---------------------------------------------------------------------------
log "Bundling dylibs with dylibbundler"
dylibbundler \
    --overwrite-dir \
    --bundle-deps \
    --fix-file "$MACOS_DIR/yauiclient" \
    --dest-dir "$FRAMEWORKS_DIR" \
    --install-path "@executable_path/../Frameworks/"

# ---------------------------------------------------------------------------
# Write Info.plist
# ---------------------------------------------------------------------------
log "Writing Info.plist"
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>yauiclient</string>
    <key>CFBundleIdentifier</key>
    <string>com.nextpvr.yauiclient</string>
    <key>CFBundleName</key>
    <string>yauiclient</string>
    <key>CFBundleDisplayName</key>
    <string>yauiclient</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# ---------------------------------------------------------------------------
# Ad-hoc code sign (required for macOS to run unsigned bundles)
# ---------------------------------------------------------------------------
log "Ad-hoc code signing"
# Sign all frameworks first
find "$FRAMEWORKS_DIR" -name "*.dylib" | while read -r lib; do
    codesign --force --sign - "$lib" 2>/dev/null || true
done
# Sign the bundle
codesign --force --deep --sign - "$APP_DIR"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
log "Verifying bundle"
codesign --verify --verbose "$APP_DIR" || true
otool -L "$MACOS_DIR/yauiclient" | grep -v "/System\|/usr/lib\|@executable_path" || true

# ---------------------------------------------------------------------------
# Create distributable archive
# ---------------------------------------------------------------------------
log "Creating archive"
mkdir -p "$DIST_DIR"
ARCHIVE="$DIST_DIR/yauiclient-macos-x64.tar.gz"
cd "$DIST_DIR"
tar czf "$ARCHIVE" yauiclient.app
log "Archive created: $ARCHIVE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
BUNDLE_SIZE=$(du -sh "$APP_DIR" | cut -f1)
ARCHIVE_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
log "Package complete"
echo "  Bundle:  $APP_DIR ($BUNDLE_SIZE)"
echo "  Archive: $ARCHIVE ($ARCHIVE_SIZE)"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo "  # or from terminal:"
echo "  $MACOS_DIR/yauiclient"