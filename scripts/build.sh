#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-development}"
case "$MODE" in
  development) IDENTITY="${LIGHT_CODESIGN_IDENTITY:?Set LIGHT_CODESIGN_IDENTITY to your Apple Development identity}" ;;
  distribution) IDENTITY="-" ;; # Deliberately ad-hoc, matching Glass/Yina distribution.
  *) echo 'usage: build.sh development|distribution' >&2; exit 64 ;;
esac
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
DERIVED="$ROOT/.build/Xcode"
APP="$DERIVED/Build/Products/Release/Light.app"
if [[ "$IDENTITY" != '-' ]]; then
  security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null || { echo 'Requested signing identity is unavailable' >&2; exit 1; }
fi
cd "$ROOT"
xcodebuild -project Light.xcodeproj -scheme Light -configuration Release \
  -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath "$DERIVED/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO LIGHT_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p "$ROOT/.build/helpers" "$ROOT/.build/module-cache"
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -target "$ARCH-apple-macosx13.0" \
    -module-cache-path "$ROOT/.build/module-cache" \
    "$ROOT/Sources/LightCtl/main.swift" -o "$ROOT/.build/helpers/lightctl-$ARCH"
done
lipo -create "$ROOT/.build/helpers/lightctl-arm64" "$ROOT/.build/helpers/lightctl-x86_64" \
  -output "$APP/Contents/MacOS/lightctl"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign nested code inside-out; keep the downloader's own entitlements.
for ITEM in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --sign "$IDENTITY" --options runtime --preserve-metadata=entitlements "$FRAMEWORK/$ITEM"
done
codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --options runtime "$APP/Contents/MacOS/lightctl"
if [[ "$MODE" == distribution ]]; then
  codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ROOT/config/Distribution.entitlements" "$APP"
else
  codesign --force --sign "$IDENTITY" --options runtime "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
for ARCH in arm64 x86_64; do
  lipo "$APP/Contents/MacOS/Light" -verify_arch "$ARCH"
  lipo "$APP/Contents/MacOS/lightctl" -verify_arch "$ARCH"
done
[[ "$("$APP/Contents/MacOS/Light" --self-check)" == "Light runtime loaded" ]]
echo "Verified: $APP"
