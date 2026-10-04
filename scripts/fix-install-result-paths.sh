#!/usr/bin/env bash
# webBasePath в install-result.env — всегда /path/ (для API и x-ui CLI).
set -Eeuo pipefail
ENVF=/etc/x-ui/install-result.env
[[ -f "$ENVF" ]] || exit 0
grep -q '^XUI_WEB_BASE_PATH=' "$ENVF" || exit 0
val="$(grep -m1 '^XUI_WEB_BASE_PATH=' "$ENVF" | cut -d= -f2- | tr -d "'\"")"
[[ -n "$val" ]] || exit 0
norm="/${val#/}"
norm="${norm%/}/"
[[ "$val" == "$norm" ]] && exit 0
if grep -q '^XUI_WEB_BASE_PATH=' "$ENVF"; then
  sed -i "s|^XUI_WEB_BASE_PATH=.*|XUI_WEB_BASE_PATH=$(printf '%q' "$norm")|" "$ENVF"
fi
