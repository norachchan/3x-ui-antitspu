#!/usr/bin/env bash
# URL panel API и проверка токена (127.0.0.1).
panel_api_url() {
  local envf=/etc/x-ui/install-result.env port base
  [[ -f "$envf" ]] || return 1
  # shellcheck disable=SC1091
  . "$envf"
  port="${XUI_PANEL_PORT:-}"
  base="${XUI_WEB_BASE_PATH:-/}"
  base="${base#/}"
  base="${base%/}"
  [[ -n "$port" && -n "$base" ]] || return 1
  printf 'https://127.0.0.1:%s/%s/panel/api' "$port" "$base"
}

panel_api_check() {
  local api token
  api="$(panel_api_url)" || return 1
  # shellcheck disable=SC1091
  . /etc/x-ui/install-result.env
  token="${XUI_API_TOKEN:-}"
  [[ -n "$token" ]] || return 1
  curl -fsk -m 15 -H "Authorization: Bearer $token" "$api/server/getNewUUID" >/dev/null
}
