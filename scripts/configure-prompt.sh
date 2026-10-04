#!/usr/bin/env bash
# Два вопроса: домен/IP в подписке и remark узла. Остальное — автоматически.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE=/etc/3x-ui-antitspu.env
EXAMPLE="$ROOT/config/antitspu.env.example"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

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

set_env() {
  local k="$1" v="$2" line
  line="$(printf '%s=%q' "$k" "$v")"
  if grep -q "^${k}=" "$ENV_FILE"; then
    sed -i "s|^${k}=.*|${line}|" "$ENV_FILE"
  else
    printf '%s\n' "$line" >>"$ENV_FILE"
  fi
}

is_ipv4() {
  [[ "$1" =~ ^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}$ ]]
}

apply_host_choice() {
  local val="$1"
  set_env PUBLIC_HOST "$val"
  if is_ipv4 "$val"; then
    set_env LINK_DOMAIN ""
    set_env SELFSTEAL_DOMAIN ""
    set_env LINK_DOMAIN_SUBS '*'
  else
    set_env LINK_DOMAIN "$val"
    set_env LINK_DOMAIN_SUBS '*'
    set_env SELFSTEAL_DOMAIN "$val"
  fi
}

# Прод Польши: не переспрашивать и не менять env при install/apply.
if [[ "$(cur NODE_REMARK)" == "poland" && -n "$(cur PUBLIC_HOST)" ]]; then
  exit 0
fi

host_def="$(detect_host_from_db)"
[[ -z "$host_def" ]] && host_def="$(default_ip)"
[[ -n "$(cur PUBLIC_HOST)" ]] && host_def="$(cur PUBLIC_HOST)"

val=""
read -r -p "Домен или IP для подписки и ссылок [$host_def]: " val || true
val="${val:-$host_def}"
[[ -n "$val" ]] || { warn "Пустое значение — оставляю $ENV_FILE без изменений"; exit 0; }

apply_host_choice "$val"

remark_def="$(cur NODE_REMARK)"
remark=""
read -r -p "Имя узла (remark на все inbound) [$remark_def]: " remark || true
remark="${remark:-$remark_def}"
if [[ -n "$remark" ]]; then
  set_env NODE_REMARK "$remark"
fi

say "Сохранено в $ENV_FILE"
