#!/usr/bin/env bash
# Наложить anti-TSPU overlay на уже установленную панель 3X-UI (+ kit-sub).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f /etc/3x-ui-antitspu.env ] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env
ANTITSPU_DIR="${ANTITSPU_DIR:-$ROOT}"

[[ $EUID -eq 0 ]] || { echo "Запустите от root." >&2; exit 1; }
[[ -f /etc/x-ui/install-result.env ]] || { echo "Сначала установите 3X-UI (базовый install.sh)." >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }

say "Подписка: overlay kit_sub.py"
export ANTITSPU_DIR
bash "$ANTITSPU_DIR/scripts/reapply-sub.sh"

# Принудительно обновить overlay (всегда синхронизировать с репозиторием)
install -m 644 "$ANTITSPU_DIR/overlay/kit_sub.py" /usr/local/lib/kit-sub/kit_sub.py
python3 -m py_compile /usr/local/lib/kit-sub/kit_sub.py
systemctl restart kit-sub

if [[ -n "${LINK_DOMAIN:-}" ]]; then
  say "kit-sub config: link_domain=$LINK_DOMAIN"
  CFG=/etc/kit-sub/config.json
  if [[ -f "$CFG" ]] && command -v jq >/dev/null; then
    subs="${LINK_DOMAIN_SUBS:-[]}"
    tmp=$(mktemp)
    jq --arg d "$LINK_DOMAIN" --argjson s "$subs" \
      '.link_domain = $d | .link_domain_subs = $s' "$CFG" >"$tmp" && mv "$tmp" "$CFG"
    systemctl restart kit-sub
  fi
fi

if [[ -f "$ANTITSPU_DIR/scripts/kit-ip-cert-sync.sh" ]]; then
  install -m 755 "$ANTITSPU_DIR/scripts/kit-ip-cert-sync.sh" /usr/local/sbin/kit-ip-cert-sync.sh
fi

install -m 755 "$ANTITSPU_DIR/scripts/reapply-sub.sh" /usr/local/sbin/3x-ui-antitspu-reapply.sh
mkdir -p /etc/systemd/system/kit-update.service.d
cat > /etc/systemd/system/kit-update.service.d/antitspu.conf <<EOF
[Service]
ExecStartPost=/usr/local/sbin/3x-ui-antitspu-reapply.sh
EOF
systemctl daemon-reload

if [[ -f "$ANTITSPU_DIR/systemd/nginx-limits.conf" ]]; then
  mkdir -p /etc/systemd/system/nginx.service.d
  install -m 644 "$ANTITSPU_DIR/systemd/nginx-limits.conf" \
    /etc/systemd/system/nginx.service.d/limits.conf
  systemctl daemon-reload
fi

if [[ -n "${SELFSTEAL_DOMAIN:-}" ]] && [[ -f "$ANTITSPU_DIR/templates/nginx-selfsteal.conf.template" ]]; then
  say "nginx self-steal для $SELFSTEAL_DOMAIN"
  # shellcheck disable=SC1091
  . /etc/x-ui/install-result.env 2>/dev/null || true
  port="${SELFSTEAL_LISTEN_PORT:-10448}"
  out=/etc/nginx/conf.d/zz-selfsteal.conf
  sed -e "s/@SELFSTEAL_DOMAIN@/$SELFSTEAL_DOMAIN/g" \
      -e "s/@LISTEN_PORT@/$port/g" \
      -e "s|@SUB_PATH@|${XUI_SUB_PATH:-/sub/}|g" \
      "$ANTITSPU_DIR/templates/nginx-selfsteal.conf.template" >"$out"
  nginx -t && systemctl reload nginx
fi

if [[ -n "${XRAY_VERSION:-}" ]] && [[ -x "$ANTITSPU_DIR/scripts/upgrade-xray.sh" ]]; then
  say "Xray $XRAY_VERSION"
  bash "$ANTITSPU_DIR/scripts/upgrade-xray.sh" "$XRAY_VERSION"
fi

say "Готово. Проверка: curl -sk https://<ваш-ip>/<sub-path>/<subId> | base64 -d | head"
