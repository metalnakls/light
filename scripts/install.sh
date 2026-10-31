#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# == 0 ]]; then
  "$ROOT/scripts/build.sh" development
  SOURCE="$ROOT/.build/Xcode/Build/Products/Release/Light.app"
else
  SOURCE="$1"
fi
exec "$ROOT/scripts/install-bundle.sh" --bundle "$SOURCE"
