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

if [[ -f /etc/x-ui/install-result.env ]]; then
  read -r panel_port panel_path <<EOF
$(python3 - /etc/x-ui/x-ui.db <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
def s(k, d=""):
    r = con.execute("select value from settings where key=?", (k,)).fetchone()
    return r[0] if r and r[0] is not None else d
print(s("webPort", "2053"), s("webBasePath", "/"))
PY
)
EOF
  # Панель слушает webPort (у вас 40455), не 443 — в URL всегда с портом.
  access="https://${NEW}:${panel_port}/${panel_path#/}"
  access="${access%/}/"
  if grep -q '^XUI_ACCESS_URL=' /etc/x-ui/install-result.env; then
    sed -i "s|^XUI_ACCESS_URL=.*|XUI_ACCESS_URL=$access|" /etc/x-ui/install-result.env
  else
    echo "XUI_ACCESS_URL=$access" >>/etc/x-ui/install-result.env
  fi
  say "Панель в install-result: $access"
fi

systemctl restart x-ui 2>/dev/null || true
say "Публичный хост в панели: $NEW (перезапустите finish-install для экрана)"
