#!/usr/bin/env bash
# Скачать Xray-core release и положить в каталог панели (без смены конфига).
set -Eeuo pipefail
ver="${1:-26.7.28}"
ver="${ver#v}"
arch="$(uname -m)"
case "$arch" in
  x86_64) ziparch=64 ;;
  aarch64) ziparch=arm64-v8a ;;
  *) echo "Неподдерживаемая архитектура: $arch" >&2; exit 1 ;;
esac

bin=/usr/local/x-ui/bin/xray-linux-amd64
[[ "$arch" == "aarch64" ]] && bin=/usr/local/x-ui/bin/xray-linux-arm64
[[ -f "$bin" ]] || { echo "Не найден $bin" >&2; exit 1; }

url="https://github.com/XTLS/Xray-core/releases/download/v${ver}/Xray-linux-${ziparch}.zip"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

curl -fsSL "$url" -o "$tmpdir/x.zip"
unzip -q "$tmpdir/x.zip" -d "$tmpdir"
install -m 755 "$tmpdir/xray" "$bin"
systemctl restart x-ui
"$bin" version | head -1
