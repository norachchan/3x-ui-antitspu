#!/usr/bin/env bash
# Интерактивно заполнить /etc/3x-ui-antitspu.env (домен / IP / имя узла в панели).
set -Eeuo pipefail

ENV_FILE=/etc/3x-ui-antitspu.env
EXAMPLE="$(cd "$(dirname "$0")/.." && pwd)/config/antitspu.env.example"

[[ -f "$ENV_FILE" ]] || cp "$EXAMPLE" "$ENV_FILE"

if [[ "${ANTITSPU_NONINTERACTIVE:-0}" == 1 ]] || [[ ! -t 0 ]]; then
  exit 0
fi

default_ip() {
  curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

detect_host_from_db() {
  [[ -f /etc/x-ui/x-ui.db ]] || return 0
  python3 - /etc/x-ui/x-ui.db <<'PY' 2>/dev/null || true
import sqlite3, sys, urllib.parse
db = sqlite3.connect(sys.argv[1])
row = db.execute("select value from settings where key='subURI' limit 1").fetchone()
if not row or not row[0]:
    sys.exit(0)
u = urllib.parse.urlsplit(row[0].strip())
print(u.hostname or "")
PY
}

cur() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true; }

say() { printf '%s\n' "$*"; }
ask() {
  local var="$1" prompt="$2" default="$3" val
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " val || true
    val="${val:-$default}"
  else
    read -r -p "$prompt: " val || true
  fi
  set_env "$var" "$val"
}

set_env() {
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ENV_FILE"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$k" "$v" >>"$ENV_FILE"
  fi
}

say ""
say "=== 3x-ui-antitspu: адрес в ссылках и имя узла ==="
say "По умолчанию в ссылках только IP. Домен нужен для self-steal и WS/gRPC через nginx."
say ""

ip_def="$(detect_host_from_db)"
[[ -z "$ip_def" ]] && ip_def="$(default_ip)"
[[ -n "$(cur PUBLIC_HOST)" ]] && ip_def="$(cur PUBLIC_HOST)"

ask PUBLIC_HOST "IP или хост в подписке (как в ссылках)" "$ip_def"

say ""
say "Домен с A-записью на этот сервер (Enter = не использовать):"
dom_def="$(cur LINK_DOMAIN)"
ask LINK_DOMAIN "  LINK_DOMAIN (WS/gRPC в подписке)" "$dom_def"

if [[ -n "$(cur LINK_DOMAIN)" ]] || grep -q '^LINK_DOMAIN=' "$ENV_FILE"; then
  subs_def="$(cur LINK_DOMAIN_SUBS)"
  [[ -z "$subs_def" ]] && subs_def='*'
  ask LINK_DOMAIN_SUBS '  Кому подставлять домен (подписки, * = всем)' "$subs_def"
fi

steal_def="$(cur SELFSTEAL_DOMAIN)"
[[ -z "$steal_def" && -n "$(cur LINK_DOMAIN)" ]] && steal_def="$(cur LINK_DOMAIN)"
say ""
ask SELFSTEAL_DOMAIN "Self-steal REALITY (nginx zz-selfsteal), Enter = пропустить" "$steal_def"

say ""
say "Имя узла в панели (remark у всех inbound, как «poland» на другом сервере)."
say "В списке панели тип протокола (REALITY, XHTTP…) показывается отдельной строкой под именем."
node_def="$(cur NODE_REMARK)"
ask NODE_REMARK "  NODE_REMARK" "$node_def"

say ""
say "Сохранено в $ENV_FILE"
