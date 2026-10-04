#!/usr/bin/env bash
# Создать репозиторий на Cursor (origin) и отправить main. Нужен: origin auth login
set -Eeuo pipefail
export PATH="/root/.local/bin:${PATH}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
origin auth status | grep -qi logged || { echo "Сначала: origin auth login"; exit 1; }
if ! git remote get-url origin &>/dev/null; then
  url=$(origin repo create 3x-ui-antitspu --default-branch main 2>&1 | tee /tmp/origin-create.log | grep -oE 'https://[^ ]+origin\.cursor\.com[^ ]*\.git' | head -1)
  if [[ -z "$url" ]]; then
    echo "Не удалось получить URL. Лог: /tmp/origin-create.log"
    exit 1
  fi
  git remote add origin "$url"
fi
git push -u origin main
echo "Готово. Откройте репозиторий в Cursor → Codebase."
