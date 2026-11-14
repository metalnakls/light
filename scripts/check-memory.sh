#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS="$ROOT/.build/Xcode/Build/Products/Release"
[[ -d "$FRAMEWORKS/Sparkle.framework" ]] || { echo 'Build Light first to resolve Sparkle.' >&2; exit 1; }
mkdir -p "$ROOT/.build/checks" "$ROOT/.build/module-cache"
xcrun swiftc -D DEBUG -parse-as-library -module-cache-path "$ROOT/.build/module-cache" \
  -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "$ROOT"/Sources/Light/{VPNController,TunnelHealth,Indicator,Hotkeys,LoginItem,Updates,Settings}.swift \
  "$ROOT/Tests/MemoryChecks.swift" -o "$ROOT/.build/checks/memory"
"$ROOT/.build/checks/memory"
