#!/usr/bin/env bash
# Базовая установка панели и протоколов из vendor/stack.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
STACK_SH="$ROOT/vendor/stack/3x-ui.sh"
SUB_BASE="$ROOT/vendor/stack/sub-proxy-base.py"

[[ -f "$STACK_SH" ]] || { echo "Нет $STACK_SH — git pull или scripts/sync-vendor.sh" >&2; exit 1; }

[ -f /etc/3x-ui-antitspu.env ] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

export KIT_SUB_SRC="$SUB_BASE"

args=(-y)
[[ -n "${PUBLIC_HOST:-}" ]] && args+=(--host "$PUBLIC_HOST")
if [[ -n "${LINK_DOMAIN:-}" ]]; then
  args+=(--domain "$LINK_DOMAIN")
else
  args+=(--sni dl.google.com)
fi
[[ -n "${INSTALLER_EXTRA_ARGS:-}" ]] && # shellcheck disable=SC2206
  args+=($INSTALLER_EXTRA_ARGS)

if [[ "${1:-}" == "--" ]]; then shift; fi
args+=("$@")

ver="$(cat "$ROOT/vendor/stack/VERSION" 2>/dev/null || echo '?')"
say "Базовый стек (vendor $ver): панель, протоколы, nginx"
exec bash "$STACK_SH" "${args[@]}"
