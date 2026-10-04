#!/usr/bin/env bash
# Запуск встроенного 3X-UI KIT из vendor/kit (без curl на чужой install.sh).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT_SH="$ROOT/vendor/kit/3x-ui.sh"
KIT_SUB_UPSTREAM="$ROOT/vendor/kit/kit-sub.py"

[[ -f "$KIT_SH" ]] || { echo "Нет $KIT_SH — обновите репозиторий или sync-kit-vendor.sh" >&2; exit 1; }

[ -f /etc/3x-ui-antitspu.env ] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

# Базовый kit-sub из vendor; overlay заменит файл в apply.sh
export KIT_SUB_SRC="$KIT_SUB_UPSTREAM"

args=()
[[ -n "${PUBLIC_HOST:-}" ]] && args+=(--host "$PUBLIC_HOST")
[[ -n "${LINK_DOMAIN:-}" ]] && args+=(--domain "$LINK_DOMAIN")
[[ -n "${KIT_EXTRA_ARGS:-}" ]] && # shellcheck disable=SC2206
  args+=($KIT_EXTRA_ARGS)

# Проброс: install.sh -- … или kit-install.sh -- --port 8443
if [[ "${1:-}" == "--" ]]; then shift; fi
args+=("$@")

ver="$(cat "$ROOT/vendor/kit/VERSION" 2>/dev/null || echo '?')"
printf '==> 3X-UI KIT (vendor %s) + anti-TSPU overlay\n' "$ver"
exec bash "$KIT_SH" "${args[@]}"
