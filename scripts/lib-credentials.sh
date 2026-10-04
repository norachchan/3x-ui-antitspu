#!/usr/bin/env bash
# Как norachchan/bootstrap-xui: gen_alnum, x-ui CLI, API token.
gen_alnum() {
  local length="${1:-16}"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 $((length * 2)) | tr -dc 'a-zA-Z0-9' | head -c "$length"
  else
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
  fi
}

xui_bin() {
  if [[ -x /usr/local/x-ui/x-ui ]]; then
    echo /usr/local/x-ui/x-ui
  elif command -v x-ui >/dev/null 2>&1; then
    command -v x-ui
  else
    return 1
  fi
}

xui_cli() {
  local bin
  bin=$(xui_bin) || return 1
  XUI_DB_TYPE=sqlite env -u XUI_DB_DSN "$bin" "$@"
}

create_api_token() {
  local out tok
  API_TOKEN=""
  out=$(xui_cli setting -getApiToken -tokenName antitspu 2>&1) || true
  tok=$(printf '%s\n' "$out" | grep -Eo 'apiToken: .+' | head -1 | awk '{print $2}' | tr -d '[:space:]' || true)
  if [[ -z "$tok" ]]; then
    out=$(xui_cli setting -getApiToken 2>&1) || true
    tok=$(printf '%s\n' "$out" | grep -Eo 'apiToken: .+' | head -1 | awk '{print $2}' | tr -d '[:space:]' || true)
  fi
  [[ -n "$tok" ]] && API_TOKEN="$tok"
}

upsert_install_result_kv() {
  local key="$1" val="$2" envf=/etc/x-ui/install-result.env
  [[ -f "$envf" ]] || touch "$envf"
  chmod 600 "$envf"
  if grep -q "^${key}=" "$envf"; then
    sed -i "s|^${key}=.*|${key}=$(printf '%q' "$val")|" "$envf"
  else
    printf '%s=%q\n' "$key" "$val" >>"$envf"
  fi
}
