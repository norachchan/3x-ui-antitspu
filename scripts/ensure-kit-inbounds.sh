#!/usr/bin/env bash
# Если inbound'ов мало (удалили / сбой rebuild) — развернуть KIT как на проде.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

[[ -f /etc/x-ui/x-ui.db ]] || exit 0
[[ "${KIT_REBUILDING:-0}" == 1 ]] && exit 0

MIN="${MIN_KIT_INBOUNDS:-8}"
count="$(python3 -c "import sqlite3;c=sqlite3.connect('/etc/x-ui/x-ui.db');print(c.execute('select count(*) from inbounds where enable=1').fetchone()[0])" 2>/dev/null || echo 0)"

if [[ "${count:-0}" -ge "$MIN" ]]; then
  exit 0
fi

warn "Inbound'ов в панели: ${count:-0} (нужно ≥$MIN) — пересоздаю KIT"
export KIT_REBUILDING=1
bash "$ROOT/scripts/rebuild-kit-inbounds.sh"
unset KIT_REBUILDING
