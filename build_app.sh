#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MicReminder"
BUNDLE_DIR="AppBundle/${APP_NAME}.app"
INSTALL_DIR="/Applications/${APP_NAME}.app"

swift build -c release

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp .build/release/mic-reminder "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"

cat > "$BUNDLE_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.kubukoz.mic-reminder</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

echo "Built $BUNDLE_DIR"

if [ "${1:-}" = "--install" ]; then
    rm -rf "$INSTALL_DIR"
    cp -R "$BUNDLE_DIR" "$INSTALL_DIR"
    echo "Installed to $INSTALL_DIR"
fi
