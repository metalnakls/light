#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build/checks" "$ROOT/.build/module-cache"
xcrun swiftc -parse-as-library -module-cache-path "$ROOT/.build/module-cache" \
  "$ROOT/Sources/Light/VPNController.swift" "$ROOT/Sources/Light/TunnelHealth.swift" \
  "$ROOT/Sources/Light/Indicator.swift" "$ROOT/Sources/Light/Hotkeys.swift" \
  "$ROOT/Tests/PolicyChecks.swift" -o "$ROOT/.build/checks/policies"
"$ROOT/.build/checks/policies"
for script in "$ROOT"/scripts/*.sh; do bash -n "$script"; done
plutil -lint "$ROOT/Sources/Light/Info.plist" "$ROOT/Light.xcodeproj/project.pbxproj"
git -C "$ROOT" diff --check
