#!/usr/bin/env bash
# Финальный экран установки (как у базового установщика): панель, подписка, QR.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

MODE="${1:-full}"   # full | compact
RESULT=/root/3x-ui.txt
ENV=/etc/x-ui/install-result.env
DB=/etc/x-ui/x-ui.db

[[ -f "$DB" ]] || { warn "Панель не найдена."; exit 0; }

IFS=$'\t' read -r PANEL_URL USER PASS SUB_URL PROTO_COUNT PROTO_LIST NAME OVERLAY_OK API_TOKEN <<EOF
$(python3 - "$DB" "$ENV" <<'PY'
import json, os, sqlite3, sys, urllib.parse

db_path, env_path = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)

def setting(k, default=""):
    row = con.execute("select value from settings where key=?", (k,)).fetchone()
    return row[0] if row and row[0] is not None else default

def is_ip(h):
    if not h:
        return False
    parts = h.split(".")
    return len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts)

env = {}
panel = user = passwd = api_token = ""
if os.path.isfile(env_path):
    for line in open(env_path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip().strip("'").strip('"')
        env[k] = v
        if k == "XUI_ACCESS_URL":
            panel = v
        elif k == "XUI_USERNAME":
            user = v
        elif k == "XUI_PASSWORD":
            passwd = v
        elif k == "XUI_API_TOKEN":
            api_token = v

port = env.get("XUI_PANEL_PORT") or setting("webPort", "2053")
base = env.get("XUI_WEB_BASE_PATH") or setting("webBasePath", "/")
if base and not base.startswith("/"):
    base = "/" + base

def resolve_server_ip():
    ip = env.get("XUI_SERVER_IP", "")
    if ip:
        return ip
    cert = "/root/cert/ip/fullchain.pem"
    if os.path.isfile(cert):
        try:
            import re, subprocess
            out = subprocess.run(
                ["openssl", "x509", "-in", cert, "-noout", "-ext", "subjectAltName"],
                capture_output=True, text=True, timeout=5,
            )
            m = re.search(r"IP Address:([0-9.]+)", out.stdout or "")
            if m:
                return m.group(1)
        except (OSError, subprocess.SubprocessError):
            pass
    return ""

server_ip = resolve_server_ip()
listen = setting("webListen", "")
single_443 = False
if os.path.isfile("/etc/kit/kit.env"):
    for line in open("/etc/kit/kit.env"):
        line = line.strip()
        if line.startswith("SINGLE="):
            single_443 = line.split("=", 1)[1].strip().strip("'\"") == "yes"
            break
if not single_443 and listen in ("127.0.0.1", "localhost") and os.path.isfile("/etc/nginx/conf.d/kit.conf"):
    single_443 = True

public_host = os.environ.get("ANTITSPU_PUBLIC_HOST", "")
if not public_host and os.path.isfile("/etc/3x-ui-antitspu.env"):
    for line in open("/etc/3x-ui-antitspu.env"):
        if line.startswith("PUBLIC_HOST="):
            public_host = line.split("=", 1)[1].strip().strip("'\"")
            break
phost = (public_host if single_443 and public_host else server_ip) or server_ip

if single_443 and phost:
    panel = f"https://{phost}{base}"
elif panel:
    ph = urllib.parse.urlsplit(panel).hostname or ""
    if ph and not is_ip(ph) and server_ip and not single_443:
        panel = f"https://{server_ip}:{port}{base}"
elif server_ip:
    if listen in ("127.0.0.1", "localhost") and not single_443:
        panel = f"http://127.0.0.1:{port}{base}"
    else:
        panel = f"https://{server_ip}:{port}{base}"
else:
    if listen in ("127.0.0.1", "localhost"):
        panel = f"http://127.0.0.1:{port}{base}"
    else:
        panel = f"https://<IP>:{port}{base}"

sub_uri = setting("subURI", "").rstrip("/")
sub_path = setting("subPath", "/sub/")
row = None
try:
    row = con.execute(
        "select email, sub_id from clients where enable=1 "
        "order by case when email=? or email like ? then 0 else 1 end, id limit 1",
        (user or "admin", (user or "admin") + "-%"),
    ).fetchone()
except sqlite3.OperationalError:
    row = None
sub_id = row[1] if row else ""
if not sub_id:
    for (raw,) in con.execute("select settings from inbounds where enable=1"):
        try:
            data = json.loads(raw or "{}")
        except json.JSONDecodeError:
            continue
        for c in data.get("clients") or []:
            sid = c.get("subId") or c.get("sub_id")
            if sid:
                sub_id = sid
                break
        if sub_id:
            break
name = user or "admin"
sub_url = ""
if sub_id:
    if sub_uri and sub_uri.endswith(sub_path.rstrip("/")):
        sub_url = f"{sub_uri}/{sub_id}"
    elif sub_uri:
        sub_url = f"{sub_uri.rstrip('/')}/{sub_id}"
    else:
        sub_url = f"<sub-uri>/{sub_id}"

rows = con.execute(
    "select distinct remark, protocol from inbounds where enable=1 order by id"
).fetchall()
labels = []
for rm, proto in rows:
    labels.append(rm if rm else proto)
labels = list(dict.fromkeys(labels))
count = len(rows)
overlay = 0
try:
    txt = open("/usr/local/lib/kit-sub/kit_sub.py").read()
    overlay = 1 if "patch_xhttp_xmux" in txt and "add_sni" in txt else 0
except OSError:
    pass

print(panel, user, passwd, sub_url, count, ",".join(labels), name, overlay, api_token, sep="\t")
PY
)
EOF

# Дополнить из /root/3x-ui.txt, если env пустой
if [[ -f "$RESULT" ]]; then
  [[ -z "$USER" ]] && USER=$(grep -m1 '^Логин:' "$RESULT" 2>/dev/null | sed 's/^Логин:[[:space:]]*//')
  [[ -z "$PASS" ]] && PASS=$(grep -m1 '^Пароль:' "$RESULT" 2>/dev/null | sed 's/^Пароль:[[:space:]]*//')
  [[ -z "$PANEL_URL" ]] && PANEL_URL=$(grep -m1 '^Панель:' "$RESULT" 2>/dev/null | sed 's/^Панель:[[:space:]]*//')
  if [[ -z "$SUB_URL" || "$SUB_URL" == *'<'* ]]; then
    line=$(grep -m1 '^https://' "$RESULT" 2>/dev/null || true)
    [[ -n "$line" ]] && SUB_URL="$line"
  fi
fi

if [[ -f "$RESULT" ]]; then
  umask 077
  if ! grep -q '3x-ui-antitspu' "$RESULT" 2>/dev/null; then
    {
      echo
      echo "--- 3x-ui-antitspu overlay ---"
      [[ "$OVERLAY_OK" == 1 ]] && echo "Anti-TSPU: SNI, xmux ≤3 в подписке."
    } >>"$RESULT"
  fi
  if [[ -n "${API_TOKEN:-}" && "$API_TOKEN" != *$'\t'* && "$API_TOKEN" != *' '* ]]; then
    if grep -q '^API:' "$RESULT" 2>/dev/null; then
      sed -i "s|^API:.*|API:     $API_TOKEN|" "$RESULT"
    else
      echo "API:     $API_TOKEN" >>"$RESULT"
    fi
  fi
fi

if [[ "$MODE" == compact ]]; then
  echo
  say "Anti-TSPU overlay применён${OVERLAY_OK:+ (подписка: SNI, xmux ≤3)}."
  [[ -n "$SUB_URL" && "$SUB_URL" != *'<'* ]] && {
    echo
    echo "$SUB_URL"
    command -v qrencode >/dev/null && qrencode -t ANSIUTF8 -m 1 "$SUB_URL" || true
  }
  echo
  echo "Подробности: ${B}cat $RESULT${N}"
  exit 0
fi

antitspu_banner
echo "Ниже – данные для входа в панель и подключения."
echo
echo "${G}${B}Готово! Узел работает: ${PROTO_COUNT} подключений.${N}"
echo "${D}${PROTO_LIST}${N}"
[[ "$OVERLAY_OK" == 1 ]] && echo "${G}Anti-TSPU overlay:${N} SNI для WS/gRPC, xHTTP xmux ≤ 3."
echo
echo "Панель:  ${B}${PANEL_URL}${N}"
# shellcheck source=lib-panel-ip.sh
. "$ROOT/scripts/lib-panel-ip.sh"
if panel_on_443; then
  echo "${D}Панель снаружи только на порту 443 (без :40455).${N}"
else
  echo "${D}Панель — по IP (TLS на IP). Подписка может быть на домене.${N}"
fi
echo "Логин:   ${B}${USER}${N}"
echo "Пароль:  ${B}${PASS}${N}"
if [[ -n "${API_TOKEN:-}" ]]; then
  echo "API:     ${B}${API_TOKEN}${N}"
  echo "${D}Заголовок: Authorization: Bearer <API>${N}"
fi
echo
if [[ -n "$SUB_URL" && "$SUB_URL" != *'<'* ]]; then
  echo "Подписка для ${B}${NAME}${N} – все протоколы одной ссылкой. Вставьте в Hiddify, v2rayN, Happ,"
  echo "Clash Verge или FlClash: приложение само получит подходящий формат."
  echo
  echo "$SUB_URL"
  echo
  command -v qrencode >/dev/null && qrencode -t ANSIUTF8 -m 1 "$SUB_URL" || warn "qrencode не установлен – QR не показан."
else
  warn "URL подписки не определён – откройте панель или cat $RESULT"
fi
echo
echo "Всё сохранено в ${B}$RESULT${N}."
echo
if [[ -x /usr/local/bin/kit ]]; then
  echo "Дополнительные пользователи – одной командой:"
  echo "  ${B}kit user add sasha --gb 50 --days 30${N}"
  echo "  ${B}kit user list${N}"
fi
echo "Донастройка anti-TSPU: ${B}$ROOT/docs/PANEL-TUNING.md${N}"
