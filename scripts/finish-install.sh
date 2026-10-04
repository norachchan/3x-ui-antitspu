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

read -r PANEL_URL USER PASS SUB_URL PROTO_COUNT PROTO_LIST NAME OVERLAY_OK <<EOF
$(python3 - "$DB" "$ENV" <<'PY'
import json, os, sqlite3, sys, urllib.parse

db_path, env_path = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)

def setting(k, default=""):
    row = con.execute("select value from settings where key=?", (k,)).fetchone()
    return row[0] if row and row[0] is not None else default

panel = user = passwd = ""
if os.path.isfile(env_path):
    for line in open(env_path):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == "XUI_ACCESS_URL":
            panel = v
        elif k == "XUI_USERNAME":
            user = v
        elif k == "XUI_PASSWORD":
            passwd = v

if not panel:
    port = setting("webPort", "2053")
    base = setting("webBasePath", "/")
    listen = setting("webListen", "")
    if listen in ("127.0.0.1", "localhost"):
        panel = f"http://127.0.0.1:{port}{base}"
    else:
        host = setting("subDomain") or ""
        if not host:
            sub_uri = setting("subURI", "")
            if sub_uri:
                host = urllib.parse.urlsplit(sub_uri).hostname or ""
        panel = f"https://{host}:{port}{base}" if host else f"https://<IP>:{port}{base}"

sub_uri = setting("subURI", "").rstrip("/")
sub_path = setting("subPath", "/sub/")
row = con.execute(
    "select email, sub_id from clients where enable=1 "
    "order by case when email='admin' then 0 else 1 end, id limit 1"
).fetchone()
name, sub_id = (row[0], row[1]) if row else ("admin", "")
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
count = len(rows)
overlay = 0
try:
    txt = open("/usr/local/lib/kit-sub/kit_sub.py").read()
    overlay = 1 if "patch_xhttp_xmux" in txt and "add_sni" in txt else 0
except OSError:
    pass

print(panel, user, passwd, sub_url, count, " ".join(labels), name, overlay, sep="\t")
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

if [[ -f "$RESULT" ]] && ! grep -q '3x-ui-antitspu' "$RESULT" 2>/dev/null; then
  umask 077
  {
    echo
    echo "--- 3x-ui-antitspu overlay ---"
    [[ "$OVERLAY_OK" == 1 ]] && echo "Anti-TSPU: SNI, xmux ≤3 в подписке."
  } >>"$RESULT"
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
echo "Логин:   ${B}${USER}${N}"
echo "Пароль:  ${B}${PASS}${N}"
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
