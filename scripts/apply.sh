#!/usr/bin/env bash
# Anti-TSPU overlay на установленную панель 3X-UI.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
if [[ -f /etc/3x-ui-antitspu.env ]]; then
  if grep -qE '^LINK_DOMAIN_SUBS=\*$' /etc/3x-ui-antitspu.env; then
    sed -i "s/^LINK_DOMAIN_SUBS=.*/LINK_DOMAIN_SUBS='*'/" /etc/3x-ui-antitspu.env
  fi
  # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env
  [[ "${LINK_DOMAIN_SUBS:-}" == "" && -n "${LINK_DOMAIN:-}" ]] && LINK_DOMAIN_SUBS='*'
fi
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
    tmp=$(mktemp)
    if [[ "${LINK_DOMAIN_SUBS:-*}" == "*" ]]; then
      jq --arg d "$LINK_DOMAIN" \
        '.link_domain = $d | .link_domain_subs = "*"' "$CFG" >"$tmp" && mv "$tmp" "$CFG"
    else
      jq --arg d "$LINK_DOMAIN" --arg s "${LINK_DOMAIN_SUBS:-}" \
        '.link_domain = $d | .link_domain_subs = (if $s == "" then [] else [$s] end)' \
        "$CFG" >"$tmp" && mv "$tmp" "$CFG"
    fi
  fi
  if [[ -n "${PUBLIC_HOST:-}" ]] && [[ -x "$ANTITSPU_DIR/scripts/sync-public-host.sh" ]]; then
    bash "$ANTITSPU_DIR/scripts/sync-public-host.sh" || warn "sync-public-host: частично (см. выше); overlay kit-sub применён"
  fi
  systemctl restart kit-sub 2>/dev/null || true
fi

if [[ -x "$ANTITSPU_DIR/scripts/fix-install-result-paths.sh" ]]; then
  bash "$ANTITSPU_DIR/scripts/fix-install-result-paths.sh" 2>/dev/null || true
fi
if [[ -x "$ANTITSPU_DIR/scripts/ensure-kit-inbounds.sh" ]]; then
  bash "$ANTITSPU_DIR/scripts/ensure-kit-inbounds.sh" || warn "KIT inbound'ы не восстановлены"
fi

if [[ -n "${NODE_REMARK:-}" ]]; then
  style="${NODE_REMARK_STYLE:-unified}"
  case "$style" in
    kit)
      [[ -x "$ANTITSPU_DIR/scripts/restore-kit-remarks.sh" ]] \
        && bash "$ANTITSPU_DIR/scripts/restore-kit-remarks.sh" || warn "remark kit не обновлён"
      ;;
    suffix|protocol)
      [[ -x "$ANTITSPU_DIR/scripts/rename-inbounds.sh" ]] \
        && bash "$ANTITSPU_DIR/scripts/rename-inbounds.sh" || warn "remark suffix не обновлён"
      ;;
    unified|single|*)
      [[ -x "$ANTITSPU_DIR/scripts/unify-inbound-remark.sh" ]] \
        && bash "$ANTITSPU_DIR/scripts/unify-inbound-remark.sh" || warn "remark unified не обновлён"
      ;;
  esac
fi

if [[ -f "$ANTITSPU_DIR/scripts/ip-cert-sync.sh" ]]; then
  install -m 755 "$ANTITSPU_DIR/scripts/ip-cert-sync.sh" /usr/local/sbin/3x-ui-antitspu-ip-cert-sync.sh
fi

install -m 755 "$ANTITSPU_DIR/scripts/post-kit-hook.sh" /usr/local/sbin/3x-ui-antitspu-reapply.sh
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
  cert_dir="${SELFSTEAL_CERT_DIR:-/root/cert/domain}"
  cert_crt="${SELFSTEAL_CERT_FILE:-$cert_dir/fullchain.pem}"
  cert_key="${SELFSTEAL_KEY_FILE:-$cert_dir/privkey.pem}"
  if [[ -f "$cert_crt" && -f "$cert_key" ]]; then
    say "nginx self-steal для $SELFSTEAL_DOMAIN"
    # shellcheck disable=SC1091
    . /etc/x-ui/install-result.env 2>/dev/null || true
    port="${SELFSTEAL_LISTEN_PORT:-10448}"
    sub_path="$(python3 -c "import sqlite3;print(sqlite3.connect('/etc/x-ui/x-ui.db').execute(\"select value from settings where key='subPath'\").fetchone()[0])" 2>/dev/null || echo '/sub/')"
    out=/etc/nginx/conf.d/zz-selfsteal.conf
    sed -e "s/@SELFSTEAL_DOMAIN@/$SELFSTEAL_DOMAIN/g" \
        -e "s|@LISTEN_PORT@|$port|g" \
        -e "s|@SUB_PATH@|${sub_path}|g" \
        -e "s|/root/cert/domain/fullchain.pem|$cert_crt|g" \
        -e "s|/root/cert/domain/privkey.pem|$cert_key|g" \
        "$ANTITSPU_DIR/templates/nginx-selfsteal.conf.template" >"$out"
    nginx -t && systemctl reload nginx
  else
    warn "Self-steal nginx пропущен: нет сертификата $cert_crt"
    warn "Выпуск: bash $ANTITSPU_DIR/scripts/issue-domain-cert.sh $SELFSTEAL_DOMAIN"
    if [[ -f /etc/nginx/conf.d/zz-selfsteal.conf ]]; then
      rm -f /etc/nginx/conf.d/zz-selfsteal.conf
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
      warn "Удалён старый zz-selfsteal.conf (без cert ломал nginx -t)"
    fi
  fi
fi

if [[ -n "${XRAY_VERSION:-}" ]] && [[ -x "$ANTITSPU_DIR/scripts/upgrade-xray.sh" ]]; then
  say "Xray $XRAY_VERSION"
  bash "$ANTITSPU_DIR/scripts/upgrade-xray.sh" "$XRAY_VERSION"
fi

if [[ -x "$ANTITSPU_DIR/scripts/ensure-api-token.sh" ]]; then
  bash "$ANTITSPU_DIR/scripts/ensure-api-token.sh" || true
fi

