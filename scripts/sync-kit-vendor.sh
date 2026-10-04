#!/usr/bin/env bash
# Скачать scripts/3x-ui.sh и kit-sub.py из тега 3X-UI_KIT в vendor/kit/.
set -Eeuo pipefail

TAG="${1:-v1.1.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/vendor/kit"
BASE="https://raw.githubusercontent.com/itsnotkubrick/3X-UI_KIT/${TAG}/scripts"

mkdir -p "$DEST"
curl -fsSL --retry 3 -o "$DEST/3x-ui.sh" "$BASE/3x-ui.sh"
curl -fsSL --retry 3 -o "$DEST/kit-sub.py" "$BASE/kit-sub.py"
echo "${TAG#v}" >"$DEST/VERSION"
bash -n "$DEST/3x-ui.sh"
python3 -m py_compile "$DEST/kit-sub.py"
echo "OK vendor/kit ← $TAG"
