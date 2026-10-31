#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO=metalnakls/light
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DIST="$ROOT/.build/distribution"
APP="$ROOT/.build/Xcode/Build/Products/Release/Light.app"
TOOLS="${SPARKLE_TOOLS:-$ROOT/.build/Xcode/SourcePackages/artifacts/sparkle/Sparkle/bin}"
case "${1:-prepare}" in
  prepare)
    "$ROOT/scripts/build.sh" distribution
    mkdir -p "$DIST"
    APP_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Light.zip"
    SIGNATURE="$(security find-generic-password -a ed25519 -s https://sparkle-project.org -w | "$TOOLS/sign_update" --ed-key-file - -p "$DIST/Light.zip")"
    xcrun swiftc -module-cache-path "$ROOT/.build/module-cache" "$ROOT/scripts/verify-update.swift" -o "$DIST/verify-update"
    "$DIST/verify-update" "$DIST/Light.zip" "$SIGNATURE" "$APP_KEY"
    export LIGHT_VERSION="$VERSION" LIGHT_SIGNATURE="$SIGNATURE" LIGHT_DIST="$DIST"
    python3 "$ROOT/scripts/appcast.py"
    security find-generic-password -a ed25519 -s https://sparkle-project.org -w | "$TOOLS/sign_update" --ed-key-file - "$DIST/appcast.xml"
    security find-generic-password -a ed25519 -s https://sparkle-project.org -w | "$TOOLS/sign_update" --ed-key-file - --verify "$DIST/appcast.xml"
    (cd "$DIST" && shasum -a 256 Light.zip appcast.xml > SHA256SUMS)
    git -C "$ROOT" rev-parse HEAD > "$DIST/source-commit"
    echo "Prepared Light $VERSION. Commit the release files before publishing."
    ;;
  publish)
    [[ "${LIGHT_PUBLISH_APPROVED:-}" == yes ]] || { echo 'Explicit publication authorization is required' >&2; exit 1; }
    [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo 'Commit or preserve outstanding changes before publication' >&2; exit 1; }
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(cat "$DIST/source-commit")" ]] || { echo 'Source changed since preparation; prepare the release again' >&2; exit 1; }
    (cd "$DIST" && shasum -a 256 -c SHA256SUMS)
    security find-generic-password -a ed25519 -s https://sparkle-project.org -w | "$TOOLS/sign_update" --ed-key-file - --verify "$DIST/appcast.xml"
    if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then echo 'Release already exists' >&2; exit 1; fi
    if git -C "$ROOT" ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then echo 'Tag already exists' >&2; exit 1; fi
    [[ "$(gh api "repos/$REPO/commits/main" --jq .sha)" == "$(git -C "$ROOT" rev-parse HEAD)" ]] || { echo 'Push the approved source commit first' >&2; exit 1; }
    python3 "$ROOT/scripts/even-minute.py"
    gh release create "v$VERSION" "$DIST/Light.zip" "$DIST/appcast.xml" "$DIST/SHA256SUMS" \
      --repo "$REPO" --target "$(git -C "$ROOT" rev-parse HEAD)" --title "$VERSION" \
      --notes-file "$ROOT/docs/release-notes.md"
    ;;
  *) echo 'usage: release.sh prepare|publish' >&2; exit 64 ;;
esac
