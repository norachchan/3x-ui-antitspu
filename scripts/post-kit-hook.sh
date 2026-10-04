#!/usr/bin/env bash
# После kit update: overlay подписки + единый NODE_REMARK на inbound'ах.
set -u
ANTITSPU_DIR="${ANTITSPU_DIR:-/opt/3x-ui-antitspu}"
bash "$ANTITSPU_DIR/scripts/reapply-sub.sh" || true
[[ -f /etc/3x-ui-antitspu.env ]] || exit 0
# shellcheck disable=SC1091
. /etc/3x-ui-antitspu.env
[[ -n "${NODE_REMARK:-}" ]] || exit 0
case "${NODE_REMARK_STYLE:-unified}" in
  unified|single)
    bash "$ANTITSPU_DIR/scripts/unify-inbound-remark.sh" || true
    ;;
esac
