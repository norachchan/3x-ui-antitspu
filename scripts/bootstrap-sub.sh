#!/usr/bin/env bash
# Прокси подписки, если панель есть, а сервис подписки не установлен.
set -Eeuo pipefail

ANTITSPU_DIR="${ANTITSPU_DIR:-/opt/3x-ui-antitspu}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
VENDOR_PY="$ANTITSPU_DIR/vendor/stack/sub-proxy-base.py"
STACK_VERSION="${STACK_VERSION:-$(cat "$ANTITSPU_DIR/vendor/stack/VERSION" 2>/dev/null || echo 1.1.2)}"
UPSTREAM_RAW="https://raw.githubusercontent.com/itsnotkubrick/3X-UI_KIT/v${STACK_VERSION}"
DB=/etc/x-ui/x-ui.db

[[ $EUID -eq 0 ]] || { echo "Запустите от root." >&2; exit 1; }
[[ -f "$DB" ]] || { echo "Нет $DB — сначала bash install.sh." >&2; exit 1; }

if [[ -f /usr/local/lib/kit-sub/kit_sub.py ]] && [[ -f /etc/kit-sub/config.json ]]; then
  say "Прокси подписки уже установлен"
  exit 0
fi

say "Ставлю прокси подписки (база vendor ${STACK_VERSION})"
apt-get update -qq
apt-get install -y -qq python3 python3-yaml jq curl ca-certificates >/dev/null

install -d -m 755 /usr/local/lib/kit-sub /etc/kit-sub
if [[ -f "$VENDOR_PY" ]]; then
  install -m 644 "$VENDOR_PY" /usr/local/lib/kit-sub/kit_sub.py
else
  curl -fsSL --retry 3 -o /usr/local/lib/kit-sub/kit_sub.py "${UPSTREAM_RAW}/scripts/kit-sub.py"
fi
python3 -m py_compile /usr/local/lib/kit-sub/kit_sub.py

read -r SUB_PATH SUB_PORT SUB_URI SUB_LISTEN PUBLIC_HOST PROXY_PORT <<EOF
$(python3 - "$DB" <<'PY'
import sqlite3, sys, urllib.parse

db = sqlite3.connect(sys.argv[1])

def setting(key, default=""):
    row = db.execute("select value from settings where key=?", (key,)).fetchone()
    return row[0] if row and row[0] is not None else default

sub_path = setting("subPath", "/sub/")
if not sub_path.endswith("/"):
    sub_path += "/"
sub_port = int(setting("subPort", "2097") or "2097")
sub_listen = setting("subListen", "127.0.0.1") or "127.0.0.1"
sub_uri = setting("subURI", "").strip()
host = setting("subDomain", "").strip()

proxy_port = 10460
if sub_uri:
    u = urllib.parse.urlsplit(sub_uri)
    if u.scheme in ("http", "https") and u.port in (None, 80, 443):
        proxy_port = 10460
    elif u.port:
        proxy_port = u.port
    if not host:
        host = u.hostname or ""

print(sub_path, sub_port, sub_uri, sub_listen, host, proxy_port)
PY
)
EOF

if [[ -z "$PUBLIC_HOST" ]]; then
  PUBLIC_HOST="$(curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
fi

CFG=/etc/kit-sub/config.json
if [[ "$SUB_URI" =~ ^https?://[^:/]+([:/]|/|$) ]] && [[ ! "$SUB_URI" =~ :[0-9]+/ ]]; then
  jq -n \
    --arg path "$SUB_PATH" \
    --argjson port "$PROXY_PORT" \
    --arg up "http://127.0.0.1:${SUB_PORT}" \
    --arg host "$PUBLIC_HOST" \
    '{listen: "127.0.0.1", port: $port, path: $path, upstream: $up, host: $host, link_domain: "", link_domain_subs: []}' \
    >"$CFG"
  UNIT_MODE=localhost
else
  say "subURI с отдельным портом — прокси слушает 0.0.0.0:${PROXY_PORT}"
  jq -n \
    --arg path "$SUB_PATH" \
    --argjson port "$PROXY_PORT" \
    --arg up "http://127.0.0.1:${SUB_PORT}" \
    --arg host "$PUBLIC_HOST" \
    '{listen: "0.0.0.0", port: $port, path: $path, upstream: $up, host: $host, cert: "", key: "", link_domain: "", link_domain_subs: []}' \
    >"$CFG"
  UNIT_MODE=public
fi
chmod 600 "$CFG"

cat >/etc/systemd/system/kit-sub.service <<'UNIT'
[Unit]
Description=3x-ui-antitspu subscription proxy
After=network-online.target x-ui.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/kit-sub/kit_sub.py
Restart=on-failure
RestartSec=5
DynamicUser=yes
LoadCredential=config.json:/etc/kit-sub/config.json
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=true
MemoryMax=64M

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable kit-sub >/dev/null 2>&1
systemctl restart kit-sub

if ! systemctl is-active --quiet kit-sub; then
  echo "Прокси подписки не запустился: journalctl -u kit-sub -n 30" >&2
  exit 1
fi

say "Прокси подписки активен (порт $(jq -r '.port' "$CFG"), upstream 127.0.0.1:${SUB_PORT})"
if [[ "${UNIT_MODE:-localhost}" == localhost ]] && ! grep -rq "${PROXY_PORT}\|proxy_pass.*sub" /etc/nginx/ 2>/dev/null; then
  say "Проверьте nginx: HTTPS должен проксировать ${SUB_PATH} → 127.0.0.1:${PROXY_PORT}"
fi
