#!/usr/bin/env bash
# Вернуть remark inbound'ов как после базового установщика (REALITY, XHTTP, …).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

DB=/etc/x-ui/x-ui.db
[[ -f "$DB" ]] || { die "Нет $DB"; }

n=$(python3 - "$DB" <<'PY'
import sqlite3, sys

PORT_LABEL = {
    10443: "REALITY",
    10444: "XHTTP",
    10445: "MTProto",
    10451: "VLESS-WS",
    10452: "VMess-WS",
    10453: "Trojan-gRPC",
    8388: "Shadowsocks",
    8444: "TUIC",
    51820: "WireGuard",
    51821: "AmneziaWG",
    51822: "AmneziaWG-3.1",
    10447: "REALITY",
}

db = sys.argv[1]
con = sqlite3.connect(db)
updated = 0
for iid, port, protocol in con.execute(
    "select id, port, protocol from inbounds where enable=1 and remark not like 'exit-%'"
):
    p = int(port or 0)
    if protocol == "hysteria" or (p == 443 and protocol == "hysteria"):
        label = "Hysteria2"
    elif p in PORT_LABEL:
        label = PORT_LABEL[p]
    else:
        continue
    cur = con.execute("update inbounds set remark=? where id=? and remark!=?", (label, iid, label))
    updated += cur.rowcount
con.commit()
print(updated)
PY
)
say "remark inbound'ов как в базовом стеке (обновлено: $n)"

if command -v x-ui >/dev/null; then
  x-ui restart 2>/dev/null || systemctl restart x-ui
else
  systemctl restart x-ui
fi
