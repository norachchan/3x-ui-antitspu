#!/usr/bin/env bash
# Брендинг vendored install.sh после sync-vendor (без смены системных путей на сервере).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/vendor/stack/3x-ui.sh"
[[ -f "$F" ]] || exit 0
if ! grep -q '^gen_alnum()' "$F"; then
  sed -i '/^rand_str()/{a\
gen_alnum() { local length="${1:-16}"; if command -v openssl >/dev/null 2>&1; then openssl rand -base64 $((length * 2)) | tr -dc '\''a-zA-Z0-9'\'' | head -c "$length"; else tr -dc '\''a-zA-Z0-9'\'' </dev/urandom | head -c "$length"; fi; }
};' "$F"
fi
sed -i \
  -e 's/panel_path=$(rand_str 18)/panel_path=$(gen_alnum 18)/' \
  -e 's/panel_user=$(rand_str 10)/panel_user=$(gen_alnum 12)/' \
  -e 's/panel_pass=$(rand_str 20)/panel_pass=$(gen_alnum 60)/' \
  -e 's/3X-UI KIT/3x-ui-antitspu/g' \
  -e 's/Description=kit-sub: подписка с учётом приложения (3x-ui-antitspu)/Description=3x-ui-antitspu subscription proxy/g' \
  -e 's/Ставлю подписку с учётом приложения (kit-sub)/Ставлю прокси подписки/g' \
  -e 's/kit-sub скачался/прокси подписки скачался/g' \
  -e 's/kit-sub не запустился/прокси подписки не запустился/g' \
  -e 's|https://github.com/itsnotkubrick/3X-UI_KIT|https://github.com/norachchan/3x-ui-antitspu|g' \
  "$F"
bash -n "$F"
