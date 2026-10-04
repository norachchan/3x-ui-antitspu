#!/usr/bin/env bash
# Единый remark узла (NODE_REMARK) для всех inbound.
set -Eeuo pipefail

DB=/etc/x-ui/x-ui.db
[[ -f /etc/3x-ui-antitspu.env ]] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

NODE_REMARK="${NODE_REMARK:-}"
[[ -n "$NODE_REMARK" ]] || exit 0
[[ -f "$DB" ]] || { echo "Нет $DB" >&2; exit 1; }

n=$(python3 - "$DB" "$NODE_REMARK" <<'PY'
import sqlite3, sys
db, remark = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
cur = con.execute(
    "UPDATE inbounds SET remark=? WHERE remark NOT LIKE 'exit-%'",
    (remark,),
)
con.commit()
print(cur.rowcount)
PY
)
echo "==> inbound remark → «$NODE_REMARK» (обновлено строк: $n)"

if command -v x-ui >/dev/null; then
  x-ui restart 2>/dev/null || systemctl restart x-ui
else
  systemctl restart x-ui
fi
