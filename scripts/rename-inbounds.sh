#!/usr/bin/env bash
# Единый remark узла (NODE_REMARK) для всех inbound — как после ручной настройки на проде.
set -Eeuo pipefail

DB=/etc/x-ui/x-ui.db
[[ -f /etc/3x-ui-antitspu.env ]] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

NODE_REMARK="${NODE_REMARK:-}"
[[ -n "$NODE_REMARK" ]] || exit 0
[[ -f "$DB" ]] || { echo "Нет $DB" >&2; exit 1; }

esc="${NODE_REMARK//\'/\'\'}"
n=$(sqlite3 "$DB" "UPDATE inbounds SET remark='${esc}' WHERE remark NOT LIKE 'exit-%'; SELECT changes();")
echo "==> inbound remark → «$NODE_REMARK» (обновлено строк: $n)"

if command -v x-ui >/dev/null; then
  x-ui restart 2>/dev/null || systemctl restart x-ui
else
  systemctl restart x-ui
fi
