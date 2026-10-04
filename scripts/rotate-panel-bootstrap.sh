#!/usr/bin/env bash
# Пароль/логин/путь панели как bootstrap-xui (gen_alnum 12/60/18). Сохраняет install-result.env.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
# shellcheck source=lib-credentials.sh
. "$ROOT/scripts/lib-credentials.sh"
# shellcheck source=lib-panel-ip.sh
. "$ROOT/scripts/lib-panel-ip.sh"

[[ $EUID -eq 0 ]] || { echo "root only" >&2; exit 1; }
xui_bin >/dev/null || die "x-ui не установлен"

ENVF=/etc/x-ui/install-result.env
DB=/etc/x-ui/x-ui.db
[[ -f "$DB" ]] || die "Нет $DB"

pick_free_panel_port() {
  local port tries=0
  while ((tries < 80)); do
    port=$((20000 + RANDOM % 40001))
    if ! ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then
      echo "$port"
      return 0
    fi
    ((tries++)) || true
  done
  shuf -i 20000-60000 -n 1
}

say "Новые учётные данные панели (bootstrap-xui)"
PANEL_USER=$(gen_alnum 12)
PANEL_PASS=$(gen_alnum 60)
PANEL_PATH=$(gen_alnum 18)
if panel_on_443; then
  PANEL_PORT=$(grep -m1 '^XUI_PANEL_PORT=' "$ENVF" 2>/dev/null | cut -d= -f2- | tr -d "'\"" || true)
  [[ -n "$PANEL_PORT" ]] || PANEL_PORT=$(python3 -c "import sqlite3;print(sqlite3.connect('$DB').execute(\"select value from settings where key='webPort'\").fetchone()[0])")
else
  PANEL_PORT=$(pick_free_panel_port)
fi

systemctl stop x-ui 2>/dev/null || true
sleep 1

if ! xui_cli setting \
  -username "$PANEL_USER" \
  -password "$PANEL_PASS" \
  -port "$PANEL_PORT" \
  -webBasePath "$PANEL_PATH" \
  -resetTwoFactor=true >/dev/null 2>&1; then
  xui_cli setting \
    -username "$PANEL_USER" \
    -password "$PANEL_PASS" \
    -port "$PANEL_PORT" \
    -webBasePath "$PANEL_PATH" \
    || die "x-ui setting не применился"
fi

command -v sqlite3 >/dev/null && sqlite3 "$DB" "UPDATE settings SET value='$PANEL_PORT' WHERE key='webPort';"
command -v sqlite3 >/dev/null && sqlite3 "$DB" "UPDATE settings SET value='/${PANEL_PATH}/' WHERE key='webBasePath';"

create_api_token

upsert_install_result_kv XUI_USERNAME "$PANEL_USER"
upsert_install_result_kv XUI_PASSWORD "$PANEL_PASS"
upsert_install_result_kv XUI_PANEL_PORT "$PANEL_PORT"
upsert_install_result_kv XUI_WEB_BASE_PATH "/${PANEL_PATH%/}/"
persist_server_ip
url="$(build_panel_access_url 2>/dev/null || true)"
[[ -n "$url" ]] && upsert_install_result_kv XUI_ACCESS_URL "$url"

systemctl restart x-ui
sleep 2
say "Логин: $PANEL_USER"
say "Пароль: (${#PANEL_PASS} символов, см. install-result.env)"
[[ -n "${API_TOKEN:-}" ]] && say "API token: $API_TOKEN"
