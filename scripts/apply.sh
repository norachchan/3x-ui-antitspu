#!/usr/bin/env bash
# Anti-TSPU overlay на установленную панель 3X-UI.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
[ -f /etc/3x-ui-antitspu.env ] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env
ANTITSPU_DIR="${ANTITSPU_DIR:-$ROOT}"

if [[ -x "$ANTITSPU_DIR/scripts/configure-prompt.sh" ]] && [[ "${ANTITSPU_SKIP_PROMPT:-0}" != 1 ]]; then
  bash "$ANTITSPU_DIR/scripts/configure-prompt.sh"
fi

[[ $EUID -eq 0 ]] || { echo "Запустите от root." >&2; exit 1; }
[[ -f /etc/x-ui/x-ui.db ]] || [[ -f /etc/x-ui/install-result.env ]] || {
  echo "Сначала: bash install.sh на чистом VPS." >&2
  exit 1
}

say() { printf '==> %s\n' "$*"; }

SUB_PY=/usr/local/lib/kit-sub/kit_sub.py
OVERLAY="$ANTITSPU_DIR/overlay/sub_proxy.py"

if [[ ! -f "$SUB_PY" ]]; then
  say "Сервис подписки не найден — bootstrap"
  bash "$ANTITSPU_DIR/scripts/bootstrap-sub.sh"
fi
install -d -m 755 /usr/local/lib/kit-sub /etc/kit-sub

say "Подписка: overlay anti-TSPU"
export ANTITSPU_DIR
bash "$ANTITSPU_DIR/scripts/reapply-sub.sh"

install -m 644 "$OVERLAY" "$SUB_PY"
python3 -m py_compile "$SUB_PY"
systemctl restart kit-sub

CFG=/etc/kit-sub/config.json
if [[ -f "$CFG" ]] && command -v jq >/dev/null; then
  if [[ -n "${PUBLIC_HOST:-}" ]]; then
    say "Подписка: host=$PUBLIC_HOST"
    tmp=$(mktemp)
    jq --arg h "$PUBLIC_HOST" '.host = $h' "$CFG" >"$tmp" && mv "$tmp" "$CFG"
  fi
  if [[ -n "${LINK_DOMAIN:-}" ]]; then
    say "Подписка: link_domain=$LINK_DOMAIN"
    subs="${LINK_DOMAIN_SUBS:-[]}"
    tmp=$(mktemp)
    jq --arg d "$LINK_DOMAIN" --argjson s "$subs" \
      '.link_domain = $d | .link_domain_subs = $s' "$CFG" >"$tmp" && mv "$tmp" "$CFG"
  fi
  systemctl restart kit-sub 2>/dev/null || true
fi

if [[ -n "${NODE_REMARK:-}" ]] && [[ -x "$ANTITSPU_DIR/scripts/rename-inbounds.sh" ]]; then
  bash "$ANTITSPU_DIR/scripts/rename-inbounds.sh" || say "Предупреждение: remark не обновлён (см. выше)"
fi

if [[ -f "$ANTITSPU_DIR/scripts/ip-cert-sync.sh" ]]; then
  install -m 755 "$ANTITSPU_DIR/scripts/ip-cert-sync.sh" /usr/local/sbin/3x-ui-antitspu-ip-cert-sync.sh
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

