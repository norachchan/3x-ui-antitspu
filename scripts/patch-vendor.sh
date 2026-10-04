#!/usr/bin/env bash
# Брендинг vendored install.sh после sync-vendor (без смены системных путей на сервере).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/vendor/stack/3x-ui.sh"
[[ -f "$F" ]] || exit 0
sed -i \
  -e 's/3X-UI KIT/3x-ui-antitspu/g' \
  -e 's/Description=kit-sub: подписка с учётом приложения (3x-ui-antitspu)/Description=3x-ui-antitspu subscription proxy/g' \
  -e 's/Ставлю подписку с учётом приложения (kit-sub)/Ставлю прокси подписки/g' \
  -e 's/kit-sub скачался/прокси подписки скачался/g' \
  -e 's/kit-sub не запустился/прокси подписки не запустился/g' \
  -e 's|https://github.com/itsnotkubrick/3X-UI_KIT|https://github.com/norachchan/3x-ui-antitspu|g' \
  "$F"
bash -n "$F"
