#!/usr/bin/env bash
# Let's Encrypt для SELFSTEAL_DOMAIN / LINK_DOMAIN → /root/cert/domain (nginx self-steal).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-ui.sh
. "$ROOT/scripts/lib-ui.sh"
[[ -f /etc/3x-ui-antitspu.env ]] && # shellcheck disable=SC1091
  . /etc/3x-ui-antitspu.env

DOMAIN="${1:-${SELFSTEAL_DOMAIN:-${LINK_DOMAIN:-}}}"
CERT_DIR="${SELFSTEAL_CERT_DIR:-/root/cert/domain}"
[[ -n "$DOMAIN" ]] || { echo "Укажите домен: $0 image.example.com" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "root only" >&2; exit 1; }

acme=/root/.acme.sh/acme.sh
log=/var/log/3x-ui-antitspu-domain-cert.log
[[ -x $acme ]] || { warn "Нет $acme — сначала установите панель (acme.sh ставит 3X-UI)."; exit 1; }

if ss -H -ltn 'sport = :80' | grep -q .; then
  warn "Порт 80 занят. Остановите nginx на время выпуска или используйте webroot."
  ss -H -ltn 'sport = :80' || true
  exit 1
fi

say "Сертификат Let's Encrypt для $DOMAIN → $CERT_DIR"
install -d -m 700 "$CERT_DIR"
install -m 600 /dev/null "$log"
rc=0
"$acme" --issue -d "$DOMAIN" --standalone --httpport 80 --server letsencrypt --keylength ec-256 >>"$log" 2>&1 || rc=$?
[[ $rc == 0 || $rc == 2 ]] || { warn "Не выдалось. Лог: $log"; exit 1; }

(umask 077; "$acme" --install-cert -d "$DOMAIN" --ecc \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --key-file "$CERT_DIR/privkey.pem" \
  --reloadcmd "systemctl reload nginx >/dev/null 2>&1 || true" >>"$log" 2>&1) \
  || { warn "install-cert failed. Лог: $log"; exit 1; }
chmod 644 "$CERT_DIR/fullchain.pem"
chmod 600 "$CERT_DIR/privkey.pem"
say "Готово. Запустите: bash $ROOT/scripts/apply.sh"
