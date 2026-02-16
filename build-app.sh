#!/bin/bash

# Build script for GardenDefense macOS app bundle
# Creates a distributable .app and .zip file

set -e

APP_NAME="GardenDefense"
APP_BUNDLE="${APP_NAME}.app"
IDENTIFIER="com.example.gardendefense"
VERSION="1.0"
MIN_MACOS="11.0"

echo "🧹 Cleaning build directory..."
swift package clean

echo "🔨 Building ${APP_NAME} for release (arm64 - Apple Silicon)..."
swift build -c release --arch arm64

echo "🔨 Building ${APP_NAME} for release (x86_64 - Intel)..."
swift build -c release --arch x86_64

echo "📦 Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"

echo "📋 Creating universal binary with lipo..."
ARM64_BIN=".build/apple/Products/Release/${APP_NAME}"
X86_64_BIN=""
# swift build --arch places binaries under .build/apple/Products/Release/
# but paths may vary; locate them from the build directories
ARM64_BIN=$(find .build -path "*arm64-apple-macosx*release*" -name "${APP_NAME}" -type f 2>/dev/null | head -1)
X86_64_BIN=$(find .build -path "*x86_64-apple-macosx*release*" -name "${APP_NAME}" -type f 2>/dev/null | head -1)

if [ -z "$ARM64_BIN" ]; then
    echo "❌ arm64 binary not found"
    exit 1
fi
if [ -z "$X86_64_BIN" ]; then
    echo "❌ x86_64 binary not found"
    exit 1
fi

echo "   arm64:  $ARM64_BIN"
echo "   x86_64: $X86_64_BIN"
lipo -create "$ARM64_BIN" "$X86_64_BIN" -output "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "🔍 Verifying universal binary..."
lipo -info "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "🔊 Copying resources bundle..."
mkdir -p "${APP_BUNDLE}/Contents/Resources"
# Find and copy the resource bundle created by Swift Package Manager
RESOURCE_BUNDLE=$(find .build -path "*release*" -name "*.bundle" -type d 2>/dev/null | head -1)
if [ -n "$RESOURCE_BUNDLE" ]; then
    BUNDLE_NAME=$(basename "$RESOURCE_BUNDLE")
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/Resources/"
    # Also place bundle next to executable (where Bundle.module looks for it)
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/MacOS/"
    # And at the app bundle root level (another fallback location)
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/"
    echo "   Found: $RESOURCE_BUNDLE (copied to Resources/, MacOS/, and app root)"
else
    echo "   ⚠️ No resource bundle found (sounds may not work)"
fi

echo "📝 Generating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>Garden Defense</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
        <string>x86_64</string>
    </array>
</dict>
</plist>
EOF

echo "🧹 Removing quarantine attributes..."
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

echo "🗜️  Creating tar.gz archive..."
rm -f "${APP_NAME}.tar.gz"
tar -czf "${APP_NAME}.tar.gz" "${APP_BUNDLE}"

echo "📧 Creating .blob copy for email transfer..."
cp "${APP_NAME}.tar.gz" "${APP_NAME}.tar.gz.blob"

echo ""
echo "✅ Build complete!"
echo ""
echo "Created:"
echo "  - ${APP_BUNDLE} (double-click to run)"
echo "  - ${APP_NAME}.tar.gz (for sharing)"
echo "  - ${APP_NAME}.tar.gz.blob (for email - rename back to .tar.gz after receiving)"
echo ""
echo "To run on another Mac:"
echo "  1. Transfer ${APP_NAME}.tar.gz (or .tar.gz.blob, renamed back)"
echo "  2. Extract: tar -xzf ${APP_NAME}.tar.gz"
echo "  3. Right-click ${APP_BUNDLE} → Open → Open (first time only)"
echo "  4. Requires macOS ${MIN_MACOS}+"
