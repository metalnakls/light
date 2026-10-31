#!/usr/bin/env bash
set -euo pipefail
DEST=/Applications/Utilities/Light.app
if pgrep -x Light >/dev/null; then
  echo 'Stop Light before installing. Your VPN can remain connected.' >&2
  exit 1
fi
WORK="$(mktemp -d)"
STAGING=''
NEEDS_ADMIN=no
privileged() { if [[ "$NEEDS_ADMIN" == yes ]]; then sudo "$@"; else "$@"; fi; }
INSTALLED=no
IN_PLACE=no
cleanup() {
  if [[ "$INSTALLED" != yes && -n "$STAGING" ]]; then
    if [[ "$IN_PLACE" == yes && -d "$STAGING/PreviousContents" ]]; then
      rm -rf "$DEST/Contents"
      mv "$STAGING/PreviousContents" "$DEST/Contents"
    elif [[ -d "$STAGING/Previous.app" ]]; then
      privileged rm -rf "$DEST"
      privileged mv "$STAGING/Previous.app" "$DEST"
    fi
  fi
  rm -rf "$WORK"
  [[ -z "$STAGING" ]] || privileged rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
if [[ "${1:-}" == --bundle && $# == 2 ]]; then
  APP="$2"
elif [[ $# == 0 ]]; then
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
else
  echo 'usage: install.sh [--bundle /path/to/Light.app]' >&2; exit 64
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == local.light ]]
codesign --verify --deep --strict "$APP"
[[ "$("$APP/Contents/MacOS/Light" --self-check)" == "Light runtime loaded" ]]
[[ ! -L "$DEST" ]] || { echo 'Refusing to replace a symlink at the install destination' >&2; exit 1; }
if [[ -d "$DEST" && -w "$DEST" && -w "$DEST/Contents" ]]; then
  # Preserve the existing user-owned wrapper inside the protected Utilities folder.
  IN_PLACE=yes
  STAGING="$WORK/staging"
  mkdir -p "$STAGING"
else
  if [[ ! -w /Applications/Utilities ]]; then
    echo 'Administrator access is needed to install into Applications/Utilities.'
    NEEDS_ADMIN=yes
    sudo -v
  fi
  STAGING="$(privileged mktemp -d /Applications/Utilities/.light-install.XXXXXX)"
fi
privileged chown "$(id -u):$(id -g)" "$STAGING"
privileged ditto "$APP" "$STAGING/Light.app"
privileged chown -R "$(id -u):$(id -g)" "$STAGING/Light.app"
codesign --verify --deep --strict "$STAGING/Light.app"
# Exempt only this verified app from download quarantine, as documented.
xattr -dr com.apple.quarantine "$STAGING/Light.app" 2>/dev/null || true
if [[ "$IN_PLACE" == yes ]]; then
  mv "$DEST/Contents" "$STAGING/PreviousContents"
  mv "$STAGING/Light.app/Contents" "$DEST/Contents"
else
  if [[ -d "$DEST" ]]; then privileged mv "$DEST" "$STAGING/Previous.app"; fi
  privileged mv "$STAGING/Light.app" "$DEST"
fi
codesign --verify --deep --strict "$DEST"
INSTALLED=yes
echo "Installed $DEST. Open it to choose your VPN profile."
