#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Light"
APP_PATH="/Applications/Utilities/${APP_NAME}.app"
EXECUTABLE="$ROOT/.build/release/${APP_NAME}"
CONTROL_EXECUTABLE="$ROOT/.build/release/lightctl"

cd "$ROOT"
swift build -c release

sudo rm -rf "$APP_PATH"
sudo mkdir -p "$APP_PATH/Contents/MacOS"
sudo cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/$APP_NAME"
sudo chmod 755 "$APP_PATH/Contents/MacOS/$APP_NAME"
sudo cp "$CONTROL_EXECUTABLE" "$APP_PATH/Contents/MacOS/lightctl"
sudo chmod 755 "$APP_PATH/Contents/MacOS/lightctl"

INFO_PLIST="$(mktemp)"
cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.light</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>Light Controls</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>light</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST
sudo cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
sudo chmod 644 "$APP_PATH/Contents/Info.plist"
rm "$INFO_PLIST"

echo "Installed $APP_PATH"
