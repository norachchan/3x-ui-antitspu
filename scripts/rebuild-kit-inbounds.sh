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

export ANTITSPU_SKIP_PROMPT=1

[[ $EUID -eq 0 ]] || { echo "root only" >&2; exit 1; }
[[ -f /etc/x-ui/install-result.env ]] || die "Сначала установите панель (install.sh)."

# shellcheck disable=SC1091
. /etc/x-ui/install-result.env
[[ -n "${XUI_API_TOKEN:-}" ]] || { bash "$ROOT/scripts/ensure-api-token.sh"; . /etc/x-ui/install-result.env; }
[[ -n "${XUI_API_TOKEN:-}" ]] || die "Нет API token — bash scripts/rotate-panel-bootstrap.sh или создайте token в панели"

ENV=/etc/3x-ui-antitspu.env
[[ -f "$ENV" ]] && # shellcheck disable=SC1091
  . "$ENV"
HOST="${PUBLIC_HOST:-${XUI_SERVER_IP:-}}"
[[ -n "$HOST" ]] || HOST="$(resolve_server_ip 2>/dev/null || curl -4 -fsS ifconfig.me)"
[[ -n "$HOST" ]] || die "Укажите PUBLIC_HOST в $ENV"

API="https://127.0.0.1:${XUI_PANEL_PORT}/${XUI_WEB_BASE_PATH}/panel/api"
TOKEN="$XUI_API_TOKEN"

say "Удаляю текущие inbound'ы (кроме exit-*)"
raw=$(curl -fsk -m 30 -H "Authorization: Bearer $TOKEN" "$API/inbounds/list" || echo '{}')
list=$(jq -c 'if type == "array" then . elif .obj != null then .obj else [] end' <<<"$raw")
while read -r id remark; do
  [[ -n "$id" ]] || continue
  curl -fsk -m 20 -H "Authorization: Bearer $TOKEN" -X POST "$API/inbounds/del/$id" >/dev/null \
    || warn "не удалил inbound $id ($remark)"
done < <(jq -r '.[] | select((.remark // "") | test("^exit-") | not) | "\(.id)\t\(.remark)"' <<<"$list")

say "Разворачиваю inbound'ы KIT (как прод, --protocols all)"
extra=()
[[ -n "${INSTALLER_EXTRA_ARGS:-}" ]] && # shellcheck disable=SC2206
  extra=($INSTALLER_EXTRA_ARGS)
export KIT_INBOUNDS_ONLY=1
bash "$ROOT/vendor/stack/3x-ui.sh" -y --host "$HOST" --protocols all "${extra[@]}"
unset KIT_INBOUNDS_ONLY

if [[ -n "${NODE_REMARK:-}" ]] && [[ -x "$ROOT/scripts/unify-inbound-remark.sh" ]]; then
  bash "$ROOT/scripts/unify-inbound-remark.sh"
fi

bash "$ROOT/scripts/apply.sh" || true
say "Готово. bash scripts/finish-install.sh full"
