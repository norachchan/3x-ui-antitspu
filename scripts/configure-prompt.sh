#!/usr/bin/env bash
# Интерактивно заполнить /etc/3x-ui-antitspu.env (домен / IP / имя узла в панели).
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
  local k="$1" v="$2" line
  # %q — иначе LINK_DOMAIN_SUBS=* ломает source и jq
  line="$(printf '%s=%q' "$k" "$v")"
  if grep -q "^${k}=" "$ENV_FILE"; then
    sed -i "s|^${k}=.*|${line}|" "$ENV_FILE"
  else
    printf '%s\n' "$line" >>"$ENV_FILE"
  fi
}

antitspu_banner
echo "Настройка адреса в ссылках и имени узла (Enter — оставить по умолчанию)."
echo "${D}Этот хост попадёт в URL подписки и (после apply) в subURI панели.${N}"
echo "${D}LINK_DOMAIN — только подмена домена внутри ссылок WS/gRPC; панель на :40455 остаётся с IP, пока нет TLS на домен.${N}"
echo

ip_def="$(detect_host_from_db)"
[[ -z "$ip_def" ]] && ip_def="$(default_ip)"
[[ -n "$(cur PUBLIC_HOST)" ]] && ip_def="$(cur PUBLIC_HOST)"

ask PUBLIC_HOST "IP или хост в подписке (как в ссылках)" "$ip_def"

echo
echo "Домен с A-записью на этот сервер (Enter = не использовать):"
dom_def="$(cur LINK_DOMAIN)"
ask LINK_DOMAIN "  LINK_DOMAIN (WS/gRPC в подписке)" "$dom_def"

if [[ -n "$(cur LINK_DOMAIN)" ]] || grep -q '^LINK_DOMAIN=' "$ENV_FILE"; then
  subs_def="$(cur LINK_DOMAIN_SUBS)"
  [[ -z "$subs_def" ]] && subs_def='*'
  ask LINK_DOMAIN_SUBS '  Кому подставлять домен (подписки, * = всем)' "$subs_def"
fi

steal_def="$(cur SELFSTEAL_DOMAIN)"
[[ -z "$steal_def" && -n "$(cur LINK_DOMAIN)" ]] && steal_def="$(cur LINK_DOMAIN)"
echo
ask SELFSTEAL_DOMAIN "Self-steal REALITY (nginx zz-selfsteal), Enter = пропустить" "$steal_def"

echo
echo "Имя узла (префикс remark): в панели будет «имя · REALITY», «имя · XHTTP» и т.д."
echo "${D}Одно имя на все inbound без протокола даёт в панели «(imported 1)» вместо типа.${N}"
node_def="$(cur NODE_REMARK)"
ask NODE_REMARK "  NODE_REMARK" "$node_def"

echo
say "Сохранено в $ENV_FILE"
