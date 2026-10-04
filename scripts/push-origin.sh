#!/usr/bin/env bash
# Отправить main на GitHub (remote github). Нужен: gh auth login
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
gh auth status -h github.com >/dev/null 2>&1 || { echo "Сначала: gh auth login"; exit 1; }
git remote get-url github &>/dev/null || git remote add github https://github.com/norachchan/3x-ui-antitspu.git
git push -u github main
echo "Готово: https://github.com/norachchan/3x-ui-antitspu"
