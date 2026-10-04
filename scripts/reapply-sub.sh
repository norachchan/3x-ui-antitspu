#!/bin/sh
# После обновления панели: вернуть overlay подписки.
set -u
ANTITSPU_DIR="${ANTITSPU_DIR:-/opt/3x-ui-antitspu}"
SUB_PY=/usr/local/lib/kit-sub/kit_sub.py
OVERLAY="$ANTITSPU_DIR/overlay/sub_proxy.py"

[ -f "$OVERLAY" ] || OVERLAY="$(cd "$(dirname "$0")/.." && pwd)/overlay/sub_proxy.py"
[ -f "$OVERLAY" ] || { logger -p user.warning -t 3x-ui-antitspu "overlay sub_proxy.py not found"; exit 0; }

if grep -q "def patch_xhttp_xmux" "$SUB_PY" 2>/dev/null && grep -q "def add_sni" "$SUB_PY" 2>/dev/null; then
  exit 0
fi

cp -a "$SUB_PY" "/tmp/sub_proxy.py.bak.$$" 2>/dev/null || true
install -m 644 "$OVERLAY" "$SUB_PY"
if python3 -m py_compile "$SUB_PY"; then
  systemctl restart kit-sub 2>/dev/null || true
  logger -t 3x-ui-antitspu "subscription overlay restored"
else
  [ -f "/tmp/sub_proxy.py.bak.$$" ] && cp -a "/tmp/sub_proxy.py.bak.$$" "$SUB_PY"
  logger -p user.warning -t 3x-ui-antitspu "subscription overlay py_compile failed, reverted"
  exit 1
fi
