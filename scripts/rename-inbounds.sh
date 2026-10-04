#!/usr/bin/env bash
# Remark узла: «NODE_REMARK · REALITY» — иначе панель пишет (imported 1) при одном имени на все inbound.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

DB=/etc/x-ui/x-ui.db
[[ -f /etc/3x-ui-antitspu.env ]] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

NODE_REMARK="${NODE_REMARK:-}"
[[ -n "$NODE_REMARK" ]] || exit 0
[[ -f "$DB" ]] || { echo "Нет $DB" >&2; exit 1; }

n=$(python3 - "$DB" "$NODE_REMARK" <<'PY'
import json, sqlite3, sys

db, node = sys.argv[1], sys.argv[2].strip()
sep = " · "

# Имена inbound'ов в базовом установщике (vendor/stack)
KIT_REMARKS = {
    "REALITY", "XHTTP", "VLESS-WS", "Trojan-gRPC", "VMess-WS",
    "Shadowsocks", "Hysteria2", "TUIC", "WireGuard",
    "AmneziaWG", "AmneziaWG-3.1", "MTProto",
}

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

def proto_label(port, protocol, stream_raw, old_remark):
    if old_remark in KIT_REMARKS:
        return old_remark
    if sep in (old_remark or ""):
        tail = old_remark.split(sep, 1)[1].strip()
        if tail:
            return tail
    p = int(port or 0)
    if protocol == "hysteria" or (p == 443 and protocol == "hysteria"):
        return "Hysteria2"
    if p in PORT_LABEL:
        return PORT_LABEL[p]
    if stream_raw:
        try:
            st = json.loads(stream_raw) if isinstance(stream_raw, str) else stream_raw
            net = (st.get("network") or "").lower()
            if net == "xhttp":
                return "XHTTP"
            if net == "ws":
                return "VLESS-WS" if protocol == "vless" else "VMess-WS"
            if net == "grpc":
                return "Trojan-gRPC"
            if st.get("security") == "reality" or st.get("realitySettings"):
                return "REALITY"
        except (json.JSONDecodeError, TypeError):
            pass
    if protocol:
        return protocol.upper()
    return f"inbound-{p}" if p else "inbound"

con = sqlite3.connect(db)
rows = con.execute(
    "select id, remark, port, protocol, stream_settings from inbounds "
    "where enable=1 and remark not like 'exit-%'"
).fetchall()
updated = 0
for iid, old_rm, port, protocol, stream in rows:
    label = proto_label(port, protocol, stream, old_rm or "")
    new_rm = f"{node}{sep}{label}"
    if old_rm == new_rm:
        continue
    con.execute("update inbounds set remark=? where id=?", (new_rm, iid))
    updated += 1
con.commit()
print(updated)
PY
)
say "inbound remark → «${NODE_REMARK} · <протокол>» (обновлено: $n)"

if command -v x-ui >/dev/null; then
  x-ui restart 2>/dev/null || systemctl restart x-ui
else
  systemctl restart x-ui
fi
