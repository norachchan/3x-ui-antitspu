#!/usr/bin/env bash
# Публичный IP панели (TLS на /root/cert/ip), если в install-result нет XUI_SERVER_IP.
resolve_server_ip() {
  local ip="" envf=/etc/x-ui/install-result.env
  if [[ -f "$envf" ]]; then
    ip="$(grep -m1 '^XUI_SERVER_IP=' "$envf" 2>/dev/null | cut -d= -f2- | tr -d "'\"")"
    [[ -n "$ip" ]] && { printf '%s' "$ip"; return 0; }
  fi
  if [[ -s /root/cert/ip/fullchain.pem ]]; then
    ip="$(openssl x509 -in /root/cert/ip/fullchain.pem -noout -ext subjectAltName 2>/dev/null \
      | grep -oE 'IP Address:[0-9.]+' | head -1 | cut -d: -f2-)"
    [[ -n "$ip" ]] && { printf '%s' "$ip"; return 0; }
  fi
  curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

persist_server_ip() {
  local ip envf=/etc/x-ui/install-result.env
  ip="$(resolve_server_ip)"
  [[ -n "$ip" && -f "$envf" ]] || return 0
  if grep -q '^XUI_SERVER_IP=' "$envf"; then
    sed -i "s|^XUI_SERVER_IP=.*|XUI_SERVER_IP=$ip|" "$envf"
  else
    echo "XUI_SERVER_IP=$ip" >>"$envf"
  fi
}

# Режим «всё на 443»: x-ui на 127.0.0.1:webPort, снаружи только nginx:443 (порт 40455 с интернета закрыт).
panel_on_443() {
  if [[ -f /etc/kit/kit.env ]]; then
    local s
    s="$(grep -E '^SINGLE=' /etc/kit/kit.env 2>/dev/null | cut -d= -f2- | tr -d "'\"")"
    [[ "$s" == yes ]] && return 0
  fi
  if [[ -f /etc/x-ui/x-ui.db ]]; then
    local wl
    wl="$(python3 -c "import sqlite3;c=sqlite3.connect('/etc/x-ui/x-ui.db');r=c.execute(\"select value from settings where key='webListen'\").fetchone();print(r[0] if r else '')" 2>/dev/null || true)"
    [[ "$wl" == "127.0.0.1" && -f /etc/nginx/conf.d/kit.conf ]] && return 0
  fi
  return 1
}

panel_public_host() {
  if [[ -f /etc/3x-ui-antitspu.env ]]; then
    # shellcheck disable=SC1091
    . /etc/3x-ui-antitspu.env
  fi
  if panel_on_443 && [[ -n "${PUBLIC_HOST:-}" ]]; then
    printf '%s' "$PUBLIC_HOST"
    return 0
  fi
  resolve_server_ip
}

build_panel_access_url() {
  local envf=/etc/x-ui/install-result.env host port base url
  [[ -f "$envf" ]] || return 1
  host="$(panel_public_host)"
  if [[ -f /etc/x-ui/x-ui.db ]]; then
    read -r port base <<EOF
$(python3 -c "import sqlite3;c=sqlite3.connect('/etc/x-ui/x-ui.db');
def s(k,d=''):r=c.execute('select value from settings where key=?',(k,)).fetchone();return r[0] if r and r[0] is not None else d
p=s('webPort','');b=s('webBasePath','/');
print(p,b)" 2>/dev/null || echo " ")
EOF
  fi
  [[ -n "${port:-}" ]] || port="$(grep -m1 '^XUI_PANEL_PORT=' "$envf" 2>/dev/null | cut -d= -f2- | tr -d "'\"")"
  [[ -n "${base:-}" ]] || base="$(grep -m1 '^XUI_WEB_BASE_PATH=' "$envf" 2>/dev/null | cut -d= -f2- | tr -d "'\"")"
  [[ -n "$host" ]] || return 1
  [[ -n "$base" ]] || base="/"
  if panel_on_443; then
    url="https://${host}/${base#/}"
  else
    [[ -n "$port" ]] || port="$(python3 -c "import sqlite3;print(sqlite3.connect('/etc/x-ui/x-ui.db').execute(\"select value from settings where key='webPort'\").fetchone()[0])" 2>/dev/null || echo 2053)"
    url="https://${host}:${port}/${base#/}"
  fi
  printf '%s' "${url%/}/"
}
