#!/usr/bin/env bash
set -euo pipefail
DEST=/Applications/Utilities/Light.app
if pgrep -x Light >/dev/null; then
  echo 'Stop Light before installing. Your VPN can remain connected.' >&2
  exit 1
fi
WORK="$(mktemp -d)"
STAGING=''
INSTALLED=no
cleanup() {
  if [[ "$INSTALLED" != yes && -n "$STAGING" && -d "$STAGING/Previous.app" ]]; then
    rm -rf "$DEST"
    mv "$STAGING/Previous.app" "$DEST"
  fi
  rm -rf "$WORK"
  [[ -z "$STAGING" ]] || rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# Resolve latest once; all assets then come from the same immutable release.
LATEST="$(curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 -o /dev/null -w '%{url_effective}' https://github.com/metalnakls/light/releases/latest)"
TAG="${LATEST##*/}"
[[ "$TAG" =~ ^v[0-9]+(\.[0-9]+)*$ ]] || { echo 'Could not resolve a Light release' >&2; exit 1; }
BASE="https://github.com/metalnakls/light/releases/download/$TAG"
for FILE in Light.zip SHA256SUMS; do
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$BASE/$FILE" -o "$WORK/$FILE"
done
cd "$WORK"
grep -E '^[0-9a-f]{64}  Light.zip$' SHA256SUMS > Light.sha256
[[ -s Light.sha256 ]] || { echo 'Missing archive checksum' >&2; exit 1; }
shasum -a 256 -c Light.sha256
ditto -x -k Light.zip extracted
APP="$WORK/extracted/Light.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.light ]]
codesign --verify --deep --strict "$APP"
STAGING="$(mktemp -d /Applications/Utilities/.light-install.XXXXXX)"
ditto "$APP" "$STAGING/Light.app"
codesign --verify --deep --strict "$STAGING/Light.app"
# Only the installed app is exempted from download quarantine, as documented.
xattr -dr com.apple.quarantine "$STAGING/Light.app" 2>/dev/null || true
if [[ -d "$DEST" ]]; then mv "$DEST" "$STAGING/Previous.app"; fi
if ! mv "$STAGING/Light.app" "$DEST" || ! codesign --verify --deep --strict "$DEST"; then
  rm -rf "$DEST"
  [[ ! -d "$STAGING/Previous.app" ]] || mv "$STAGING/Previous.app" "$DEST"
  echo 'Installation failed; restored the previous app.' >&2
  exit 1
fi
INSTALLED=yes
echo "Installed $DEST ($TAG). Open it to choose your VPN profile."
