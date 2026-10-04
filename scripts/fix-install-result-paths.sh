#!/usr/bin/env bash
# Синхронизировать install-result.env с SQLite (webPort, webBasePath).
set -Eeuo pipefail
ENVF=/etc/x-ui/install-result.env
DB=/etc/x-ui/x-ui.db
[[ -f "$DB" ]] || exit 0

read -r port base <<EOF
$(python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
def s(k, d=""):
    r = c.execute("select value from settings where key=?", (k,)).fetchone()
    return r[0] if r and r[0] is not None else d
port = s("webPort", "")
base = s("webBasePath", "")
if base and not base.startswith("/"):
    base = "/" + base
if base and not base.endswith("/"):
    base = base + "/"
print(port, base)
PY
)
EOF

[[ -n "$port" ]] || exit 0
[[ -f "$ENVF" ]] || install -m 600 /dev/null "$ENVF"

upsert() {
  local k="$1" v="$2"
  if grep -q "^${k}=" "$ENVF"; then
    sed -i "s|^${k}=.*|${k}=$(printf '%q' "$v")|" "$ENVF"
  else
    printf '%s=%q\n' "$k" "$v" >>"$ENVF"
  fi
}

upsert XUI_PANEL_PORT "$port"
[[ -n "$base" ]] && upsert XUI_WEB_BASE_PATH "$base"
