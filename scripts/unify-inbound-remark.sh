#!/usr/bin/env bash
# Одно имя remark на все inbound (как poland на проде). В панели возможно «(imported 1)».
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

DB=/etc/x-ui/x-ui.db
[[ -f /etc/3x-ui-antitspu.env ]] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

name="${NODE_REMARK:-}"
[[ -n "$name" ]] || exit 0
[[ -f "$DB" ]] || { echo "Нет $DB" >&2; exit 1; }

n=$(python3 - "$DB" "$name" <<'PY'
import sqlite3, sys

db, name = sys.argv[1], sys.argv[2].strip()
if not name:
    sys.exit(0)
con = sqlite3.connect(db)
cur = con.execute(
    "update inbounds set remark=? where enable=1 and remark not like 'exit-%' "
    "and (remark is null or remark!=?)",
    (name, name),
)
con.commit()
print(cur.rowcount)
PY
)
say "remark всех inbound → «${name}» (обновлено: $n)"

if command -v x-ui >/dev/null; then
  x-ui restart 2>/dev/null || systemctl restart x-ui
else
  systemctl restart x-ui
fi
