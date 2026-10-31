#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="/Applications/Utilities/Light.app"
if [[ $# == 0 ]]; then
  "$ROOT/scripts/build.sh" development
  SOURCE="$ROOT/.build/Xcode/Build/Products/Release/Light.app"
else
  SOURCE="$1"
fi
[[ -d "$SOURCE/Contents" ]] || { echo 'Pass a verified Light.app bundle' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" == 'local.light' ]]
codesign --verify --deep --strict --verbose=2 "$SOURCE"
if pgrep -x Light >/dev/null; then
  echo 'Light is running. Stop it before replacing the installed app; the VPN can remain connected.' >&2
  exit 1
fi
# Stage and verify on the destination volume before replacing anything.
STAGING="$(mktemp -d /Applications/Utilities/.light-install.XXXXXX)"
INSTALLED=no
cleanup() {
  if [[ "$INSTALLED" != yes && -d "$STAGING/Previous.app" ]]; then
    rm -rf "$APP_PATH"
    mv "$STAGING/Previous.app" "$APP_PATH"
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
ditto "$SOURCE" "$STAGING/Light.app"
codesign --verify --deep --strict --verbose=2 "$STAGING/Light.app"
if [[ -d "$APP_PATH" ]]; then mv "$APP_PATH" "$STAGING/Previous.app"; fi
if ! mv "$STAGING/Light.app" "$APP_PATH" || ! codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
  rm -rf "$APP_PATH"
  if [[ -d "$STAGING/Previous.app" ]]; then mv "$STAGING/Previous.app" "$APP_PATH"; fi
  echo 'Install failed; restored the previous app.' >&2
  exit 1
fi
INSTALLED=yes
echo "Installed $APP_PATH"
