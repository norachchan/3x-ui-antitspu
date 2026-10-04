#!/usr/bin/env bash
# NL/прод: bootstrap-пароль, API token, inbound'ы KIT, overlay, финальный экран.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ANTITSPU_SKIP_PROMPT=1
export SKIP_BASE_INSTALL=1

REBUILD_INBOUNDS="${REBUILD_INBOUNDS:-1}"
ROTATE_PANEL="${ROTATE_PANEL:-1}"

cd "$ROOT"
git pull --ff-only 2>/dev/null || true

[[ "$ROTATE_PANEL" == 1 ]] && bash "$ROOT/scripts/rotate-panel-bootstrap.sh"
[[ "$REBUILD_INBOUNDS" == 1 ]] && bash "$ROOT/scripts/rebuild-kit-inbounds.sh" || bash "$ROOT/scripts/apply.sh"
bash "$ROOT/scripts/finish-install.sh" full
