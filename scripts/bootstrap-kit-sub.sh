#!/usr/bin/env bash
# Установить kit-sub, если панель 3X-UI уже есть, а KIT не ставил подписку (нет /usr/local/lib/kit-sub).
set -Eeuo pipefail

ANTITSPU_DIR="${ANTITSPU_DIR:-/opt/3x-ui-antitspu}"
VENDOR_PY="$ANTITSPU_DIR/vendor/kit/kit-sub.py"
KIT_VERSION="${KIT_VERSION:-$(cat "$ANTITSPU_DIR/vendor/kit/VERSION" 2>/dev/null || echo 1.1.2)}"
KIT_RAW="https://raw.githubusercontent.com/itsnotkubrick/3X-UI_KIT/v${KIT_VERSION}"
DB=/etc/x-ui/x-ui.db

[[ $EUID -eq 0 ]] || { echo "Запустите от root." >&2; exit 1; }
[[ -f "$DB" ]] || { echo "Нет $DB — сначала установите 3X-UI (install.sh без SKIP_BASE_INSTALL)." >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }

if [[ -f /usr/local/lib/kit-sub/kit_sub.py ]] && [[ -f /etc/kit-sub/config.json ]]; then
  say "kit-sub уже установлен"
  exit 0
fi

say "Ставлю kit-sub (база из 3X-UI KIT v${KIT_VERSION})"
apt-get update -qq
apt-get install -y -qq python3 python3-yaml jq curl ca-certificates >/dev/null

install -d -m 755 /usr/local/lib/kit-sub /etc/kit-sub
if [[ -f "$VENDOR_PY" ]]; then
  install -m 644 "$VENDOR_PY" /usr/local/lib/kit-sub/kit_sub.py
else
  curl -fsSL --retry 3 -o /usr/local/lib/kit-sub/kit_sub.py "${KIT_RAW}/scripts/kit-sub.py"
fi
python3 -m py_compile /usr/local/lib/kit-sub/kit_sub.py

read -r SUB_PATH SUB_PORT SUB_URI SUB_LISTEN PUBLIC_HOST KIT_PORT <<EOF
$(python3 - "$DB" <<'PY'
import sqlite3, sys, urllib.parse, json

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

if not host and sub_uri:
    u = urllib.parse.urlsplit(sub_uri)
    host = u.hostname or ""

kit_port = 10460
if sub_uri:
    u = urllib.parse.urlsplit(sub_uri)
    if u.scheme in ("http", "https") and u.port in (None, 80, 443):
        kit_port = 10460
    elif u.port:
        kit_port = u.port

print(sub_path, sub_port, sub_uri, sub_listen, host, kit_port)
PY
)
EOF

if [[ -z "$PUBLIC_HOST" ]]; then
  PUBLIC_HOST="$(curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
fi

CFG=/etc/kit-sub/config.json
if [[ "$SUB_URI" =~ ^https?://[^:/]+([:/]|/|$) ]] && [[ ! "$SUB_URI" =~ :[0-9]+/ ]]; then
  # Подписка за nginx на 443 (как KIT SINGLE / trusted)
  jq -n \
    --arg path "$SUB_PATH" \
    --argjson port "$KIT_PORT" \
    --arg up "http://127.0.0.1:${SUB_PORT}" \
    --arg host "$PUBLIC_HOST" \
    '{listen: "127.0.0.1", port: $port, path: $path, upstream: $up, host: $host, link_domain: "", link_domain_subs: []}' \
    >"$CFG"
  UNIT_MODE=localhost
else
  say "Внимание: subURI не похож на HTTPS без отдельного порта — kit-sub слушает 0.0.0.0:${KIT_PORT}"
  # fallback: panel paths often empty when behind nginx
  jq -n \
    --arg path "$SUB_PATH" \
    --argjson port "$KIT_PORT" \
    --arg up "http://127.0.0.1:${SUB_PORT}" \
    --arg host "$PUBLIC_HOST" \
    --arg cert "" --arg key "" \
    '{listen: "0.0.0.0", port: $port, path: $path, upstream: $up, host: $host, cert: $cert, key: $key, link_domain: "", link_domain_subs: []}' \
    >"$CFG"
  UNIT_MODE=public
fi
chmod 600 "$CFG"

if [[ "${UNIT_MODE:-localhost}" == localhost ]]; then
  cat >/etc/systemd/system/kit-sub.service <<'UNIT'
[Unit]
Description=kit-sub: подписка с учётом приложения (3X-UI KIT)
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
else
  say "Для TLS на отдельном порту пропишите cert/key в $CFG и перезапустите kit-sub"
  cat >/etc/systemd/system/kit-sub.service <<'UNIT'
[Unit]
Description=kit-sub: подписка с учётом приложения (3X-UI KIT)
After=network-online.target x-ui.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/kit-sub/kit_sub.py
Restart=on-failure
RestartSec=5
DynamicUser=yes
LoadCredential=config.json:/etc/kit-sub/config.json
MemoryMax=64M

[Install]
WantedBy=multi-user.target
UNIT
fi

systemctl daemon-reload
systemctl enable kit-sub >/dev/null 2>&1
systemctl restart kit-sub

if ! systemctl is-active --quiet kit-sub; then
  echo "kit-sub не запустился: journalctl -u kit-sub -n 30" >&2
  exit 1
fi

say "kit-sub активен (порт $(jq -r '.port' "$CFG"), upstream 127.0.0.1:${SUB_PORT})"
if [[ "${UNIT_MODE:-localhost}" == localhost ]] && ! grep -rq "${KIT_PORT}\|kit-sub\|proxy_pass.*sub" /etc/nginx/ 2>/dev/null; then
  say "Проверьте nginx: HTTPS должен проксировать ${SUB_PATH} → 127.0.0.1:${KIT_PORT}"
  say "Если nginx ещё не настроен — установите полный стек: bash install.sh (без SKIP_BASE_INSTALL) на чистом VPS"
fi
