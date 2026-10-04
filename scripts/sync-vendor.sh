#!/usr/bin/env bash
# Обновить vendor/stack из upstream-релиза (см. vendor/stack/UPSTREAM.md).
set -Eeuo pipefail

TAG="${1:-v1.1.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/stack"
BASE="https://raw.githubusercontent.com/itsnotkubrick/3X-UI_KIT/${TAG}/scripts"

mkdir -p "$DEST"
curl -fsSL --retry 3 -o "$DEST/3x-ui.sh" "$BASE/3x-ui.sh"
curl -fsSL --retry 3 -o "$DEST/sub-proxy-base.py" "$BASE/kit-sub.py"
echo "${TAG#v}" >"$DEST/VERSION"
bash "$ROOT/scripts/patch-vendor.sh"
python3 -m py_compile "$DEST/sub-proxy-base.py"
echo "OK vendor/stack ← $TAG"
