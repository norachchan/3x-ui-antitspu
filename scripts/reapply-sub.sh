#!/bin/sh
# После обновления панели/kit-sub: вернуть overlay подписки (anti-TSPU).
set -u
ANTITSPU_DIR="${ANTITSPU_DIR:-/opt/3x-ui-antitspu}"
KIT_SUB=/usr/local/lib/kit-sub/kit_sub.py
OVERLAY="$ANTITSPU_DIR/overlay/kit_sub.py"

[ -f "$OVERLAY" ] || OVERLAY="$(cd "$(dirname "$0")/.." && pwd)/overlay/kit_sub.py"
[ -f "$OVERLAY" ] || { logger -p user.warning -t 3x-ui-antitspu "overlay kit_sub.py not found"; exit 0; }

if grep -q "def patch_xhttp_xmux" "$KIT_SUB" 2>/dev/null && grep -q "def add_sni" "$KIT_SUB" 2>/dev/null; then
  exit 0
fi

cp -a "$KIT_SUB" "/tmp/kit_sub.py.bak.$$" 2>/dev/null || true
install -m 644 "$OVERLAY" "$KIT_SUB"
if python3 -m py_compile "$KIT_SUB"; then
  systemctl restart kit-sub 2>/dev/null || true
  logger -t 3x-ui-antitspu "kit_sub overlay restored from $OVERLAY"
else
  [ -f "/tmp/kit_sub.py.bak.$$" ] && cp -a "/tmp/kit_sub.py.bak.$$" "$KIT_SUB"
  logger -p user.warning -t 3x-ui-antitspu "kit_sub overlay failed py_compile, reverted"
  exit 1
fi
