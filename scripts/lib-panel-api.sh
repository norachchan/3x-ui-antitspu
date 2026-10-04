#!/usr/bin/env bash
# URL panel API (источник правды — SQLite) и проверка токена.
panel_api_urls() {
  local db=/etc/x-ui/x-ui.db
  [[ -f "$db" ]] || return 1
  python3 - "$db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])

def s(k, d=""):
    r = c.execute("select value from settings where key=?", (k,)).fetchone()
    return r[0] if r and r[0] is not None else d

port = s("webPort", "") or s("port", "")
base = s("webBasePath", "/")
if not port:
    sys.exit(0)
bases = []
if base:
    b = base if base.startswith("/") else "/" + base
    bases.append(b.rstrip("/"))
    bases.append(b if b.endswith("/") else b + "/")
    bare = b.strip("/")
    if bare:
        bases.append(bare)
else:
    bases.append("")
seen = set()
hosts = ("127.0.0.1", "localhost")
for host in hosts:
    for b in bases:
        key = (host, port, b)
        if key in seen:
            continue
        seen.add(key)
        path = b.strip("/")
        if path:
            print(f"https://{host}:{port}/{path}/panel/api")
            print(f"http://{host}:{port}/{path}/panel/api")
        else:
            print(f"https://{host}:{port}/panel/api")
            print(f"http://{host}:{port}/panel/api")
PY
}

panel_api_url() {
  panel_api_urls | head -1
}

panel_api_check() {
  local token url
  [[ -f /etc/x-ui/install-result.env ]] || return 1
  # shellcheck disable=SC1091
  . /etc/x-ui/install-result.env
  token="${XUI_API_TOKEN:-}"
  [[ -n "$token" ]] || return 1
  while read -r url; do
    [[ -n "$url" ]] || continue
    if curl -fsk -m 15 -H "Authorization: Bearer $token" "$url/server/getNewUUID" >/dev/null 2>&1; then
      printf '%s' "$url"
      return 0
    fi
  done < <(panel_api_urls)
  return 1
}
