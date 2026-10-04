#!/usr/bin/env bash
# После смены PUBLIC_HOST в env: subURI в панели, kit.env, externalProxy в inbound'ах.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"

[[ -f /etc/3x-ui-antitspu.env ]] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

NEW="${PUBLIC_HOST:-}"
[[ -n "$NEW" ]] || exit 0
[[ -f /etc/x-ui/x-ui.db ]] || exit 0

say() { printf '==> %s\n' "$*"; }

python3 - "$NEW" /etc/x-ui/x-ui.db <<'PY'
import json, sqlite3, sys, urllib.parse

new_host, db_path = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db_path)

def setting(k, default=""):
    row = con.execute("select value from settings where key=?", (k,)).fetchone()
    return row[0] if row and row[0] is not None else default

def set_setting(k, v):
    if con.execute("select 1 from settings where key=?", (k,)).fetchone():
        con.execute("update settings set value=? where key=?", (v, k))
    else:
        con.execute("insert into settings (key, value) values (?, ?)", (k, v))

old = ""
uri = setting("subURI", "").strip()
if uri:
    u = urllib.parse.urlsplit(uri)
    old = u.hostname or ""
    if old and old != new_host:
        netloc = new_host
        if u.port:
            netloc = f"{new_host}:{u.port}"
        new_uri = urllib.parse.urlunsplit((u.scheme, netloc, u.path, u.query, u.fragment))
        set_setting("subURI", new_uri)
        print(f"subURI: {old} -> {new_host}", file=sys.stderr)

dom = setting("subDomain", "").strip()
if dom != new_host and (not dom or dom == old or dom.replace(".", "").isdigit() is False):
    set_setting("subDomain", new_host)

# externalProxy.dest в stream_settings
rows = con.execute("select id, stream_settings from inbounds").fetchall()
for iid, raw in rows:
    if not raw:
        continue
    try:
        st = json.loads(raw)
    except json.JSONDecodeError:
        continue
    changed = False
    for ep in st.get("externalProxy") or []:
        if not isinstance(ep, dict):
            continue
        d = ep.get("dest")
        if old and d == old:
            ep["dest"] = new_host
            changed = True
    if changed:
        con.execute("update inbounds set stream_settings=? where id=?", (json.dumps(st, separators=(",", ":")), iid))

con.commit()
PY

if [[ -f /etc/kit/kit.env ]]; then
  old_host="$(grep -E '^HOST=' /etc/kit/kit.env | head -1 | cut -d= -f2- | tr -d "'\"" || true)"
  if [[ -n "$old_host" && "$old_host" != "$NEW" ]]; then
    sed -i "s|^HOST=.*|HOST=$(printf '%q' "$NEW")|" /etc/kit/kit.env
    if grep -q '^SUB_BASE=' /etc/kit/kit.env; then
      base="$(grep '^SUB_BASE=' /etc/kit/kit.env | cut -d= -f2- | tr -d "'")"
      new_base="${base//"$old_host"/"$NEW"}"
      sed -i "s|^SUB_BASE=.*|SUB_BASE=$(printf '%q' "$new_base")|" /etc/kit/kit.env
    fi
    say "kit.env: HOST=$NEW"
  fi
fi

# Панель: TLS обычно только на IP (/root/cert/ip). Домен в XUI_ACCESS_URL ломает вход в браузере.
fix_panel_access_url() {
  local envf=/etc/x-ui/install-result.env
  [[ -f "$envf" ]] || return 0
  local server_ip panel_port base_path
  server_ip="$(grep -m1 '^XUI_SERVER_IP=' "$envf" | cut -d= -f2- | tr -d '"'"'")"
  panel_port="$(grep -m1 '^XUI_PANEL_PORT=' "$envf" | cut -d= -f2- | tr -d '"'"'")"
  base_path="$(grep -m1 '^XUI_WEB_BASE_PATH=' "$envf" | cut -d= -f2- | tr -d '"'"'")"
  [[ -n "$server_ip" ]] || return 0
  [[ -n "$panel_port" ]] || panel_port="$(python3 -c "import sqlite3;print(sqlite3.connect('/etc/x-ui/x-ui.db').execute(\"select value from settings where key='webPort'\").fetchone()[0])" 2>/dev/null || echo 2053)"
  [[ -n "$base_path" ]] || base_path="/"
  local url="https://${server_ip}:${panel_port}/${base_path#/}"
  url="${url%/}/"
  if grep -q '^XUI_ACCESS_URL=' "$envf"; then
    sed -i "s|^XUI_ACCESS_URL=.*|XUI_ACCESS_URL=$url|" "$envf"
  else
    echo "XUI_ACCESS_URL=$url" >>"$envf"
  fi
  say "Панель (открывать по IP, сертификат на IP): $url"
}
fix_panel_access_url

systemctl restart x-ui 2>/dev/null || true
say "Подписка / ссылки: $NEW (finish-install.sh — актуальный URL)"
