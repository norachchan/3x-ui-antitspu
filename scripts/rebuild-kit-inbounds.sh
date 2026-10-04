#!/usr/bin/env bash
# Inbound'ы как на проде: полный набор KIT (vendor), затем единый NODE_REMARK.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
# shellcheck source=lib-credentials.sh
. "$ROOT/scripts/lib-credentials.sh"
# shellcheck source=lib-panel-ip.sh
. "$ROOT/scripts/lib-panel-ip.sh"
# shellcheck source=lib-panel-api.sh
. "$ROOT/scripts/lib-panel-api.sh"

export ANTITSPU_SKIP_PROMPT=1

[[ $EUID -eq 0 ]] || { echo "root only" >&2; exit 1; }
[[ -f /etc/x-ui/install-result.env ]] || die "Сначала установите панель (install.sh)."

[[ -x "$ROOT/scripts/fix-install-result-paths.sh" ]] && bash "$ROOT/scripts/fix-install-result-paths.sh"
bash "$ROOT/scripts/ensure-api-token.sh" 2>/dev/null || true
sleep 1
# shellcheck disable=SC1091
. /etc/x-ui/install-result.env
[[ -n "${XUI_API_TOKEN:-}" ]] || die "Нет API token — bash scripts/rotate-panel-bootstrap.sh"

API="$(panel_api_check)" || die "API панели не отвечает. Проверьте: systemctl status x-ui; journalctl -u x-ui -n 20; cat /etc/x-ui/install-result.env"
export PANEL_API_URL="$API"
say "API панели: $API"

ENV=/etc/3x-ui-antitspu.env
[[ -f "$ENV" ]] && # shellcheck disable=SC1091
  . "$ENV"
HOST="$(resolve_server_ip 2>/dev/null || true)"
[[ -n "$HOST" ]] || HOST="${XUI_SERVER_IP:-}"
[[ -n "$HOST" ]] || HOST="$(curl -4 -fsS ifconfig.me 2>/dev/null || true)"
[[ -n "$HOST" ]] || die "Не удалось определить IP сервера для KIT"
# REALITY маскируется под чужой SNI; домен подписки — в overlay (LINK_DOMAIN).
sni_arg=(--sni dl.google.com)

TOKEN="$XUI_API_TOKEN"
LOG=/var/log/kit-inbounds-rebuild.log

say "Удаляю текущие inbound'ы (кроме exit-*)"
raw=$(curl -fsk -m 30 -H "Authorization: Bearer $TOKEN" "$API/inbounds/list" || echo '{}')
list=$(jq -c 'if type == "array" then . elif .obj != null then .obj else [] end' <<<"$raw")
n_del=0
while read -r id remark; do
  [[ -n "$id" ]] || continue
  if curl -fsk -m 20 -H "Authorization: Bearer $TOKEN" -X POST "$API/inbounds/del/$id" >/dev/null; then
    n_del=$((n_del + 1))
  else
    warn "не удалил inbound $id ($remark)"
  fi
done < <(jq -r '.[] | select((.remark // "") | test("^exit-") | not) | "\(.id)\t\(.remark)"' <<<"$list")
say "Удалено inbound'ов: $n_del"

kit_protos="${KIT_PROTOCOLS:-reality,hy2,xhttp,ws,trojan,vmess,ss,tuic}"
say "Разворачиваю inbound'ы KIT (8 как на проде: $kit_protos)"
[[ -x "$ROOT/scripts/patch-vendor.sh" ]] && bash "$ROOT/scripts/patch-vendor.sh" >/dev/null 2>&1 || true
if ! grep -q 'KIT: разворачиваю inbound' "$ROOT/vendor/stack/3x-ui.sh" 2>/dev/null; then
  die "В vendor нет KIT fast-path — на сервере: cd $ROOT && git pull"
fi
extra=()
[[ -n "${INSTALLER_EXTRA_ARGS:-}" ]] && # shellcheck disable=SC2206
  extra=($INSTALLER_EXTRA_ARGS)
export KIT_INBOUNDS_ONLY=1
say "Лог: $LOG"
if ! bash "$ROOT/vendor/stack/3x-ui.sh" -y --host "$HOST" --protocols "$kit_protos" "${sni_arg[@]}" "${extra[@]}" 2>&1 | tee "$LOG"; then
  warn "vendor завершился с ошибкой — последние строки:"
  tail -25 "$LOG" >&2 || true
  die "См. полный лог: $LOG"
fi
unset KIT_INBOUNDS_ONLY

if [[ -n "${NODE_REMARK:-}" ]] && [[ -x "$ROOT/scripts/unify-inbound-remark.sh" ]]; then
  bash "$ROOT/scripts/unify-inbound-remark.sh"
fi

bash "$ROOT/scripts/ensure-api-token.sh" || true
say "Готово. Inbound'ов: $(python3 -c "import sqlite3;print(sqlite3.connect('/etc/x-ui/x-ui.db').execute('select count(*) from inbounds where enable=1').fetchone()[0])")"
