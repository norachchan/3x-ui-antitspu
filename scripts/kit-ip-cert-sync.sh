#!/bin/sh
# acme.sh reloadcmd for the IP certificate: nginx and the panel read /root/cert/custom,
# which KIT created as a one-off copy of /root/cert/ip and nothing else keeps in sync.
set -u
src=/root/cert/ip
dst=/root/cert/custom

if cmp -s "$src/fullchain.pem" "$dst/fullchain.pem" && cmp -s "$src/privkey.pem" "$dst/privkey.pem"; then
  exit 0
fi

install -d -m 755 "$dst"
install -m 644 "$src/fullchain.pem" "$dst/fullchain.pem"
install -m 600 "$src/privkey.pem" "$dst/privkey.pem"

nginx -t >/dev/null 2>&1 && systemctl reload nginx
systemctl restart x-ui 2>/dev/null || true
logger -t kit-ip-cert-sync "synced $src -> $dst, reloaded nginx, restarted x-ui"
