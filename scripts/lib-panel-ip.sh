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
