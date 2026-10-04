#!/usr/bin/env bash
# 3x-ui-antitspu — базовая панель 3X-UI + overlay против ТСПУ.
#
# Новый VPS:
#   bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh)
#
# Только overlay (панель уже стоит):
#   SKIP_BASE_INSTALL=1 bash <(curl -fsSL .../install.sh)
#
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/norachchan/3x-ui-antitspu.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/3x-ui-antitspu}"
KIT_INSTALL_URL="${KIT_INSTALL_URL:-https://raw.githubusercontent.com/itsnotkubrick/3X-UI_KIT/main/scripts/3x-ui.sh}"

[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo -i" >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }

if [[ "${SKIP_BASE_INSTALL:-0}" != "1" ]] && [[ ! -f /etc/x-ui/install-result.env ]]; then
  say "Установка базового стека 3X-UI (официальный установщик)"
  bash <(curl -fsSL "$KIT_INSTALL_URL")
  if command -v kit >/dev/null; then
    say "Обновление CLI до последней версии"
    kit update --unattended 2>/dev/null || kit update 2>/dev/null || true
  fi
fi

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  say "Клонирование $REPO_URL → $INSTALL_DIR"
  apt-get update -qq
  apt-get install -y -qq git ca-certificates curl jq patch python3 >/dev/null
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  say "Обновление репозитория в $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
fi

if [[ ! -f /etc/3x-ui-antitspu.env ]] && [[ -f "$INSTALL_DIR/config/antitspu.env.example" ]]; then
  cp "$INSTALL_DIR/config/antitspu.env.example" /etc/3x-ui-antitspu.env
  say "Создан /etc/3x-ui-antitspu.env — отредактируйте домен и опции"
fi

export ANTITSPU_DIR="$INSTALL_DIR"
bash "$INSTALL_DIR/scripts/apply.sh"

say "Установка завершена. Репозиторий: $INSTALL_DIR"
say "Повторно наложить overlay: ANTITSPU_DIR=$INSTALL_DIR bash $INSTALL_DIR/scripts/apply.sh"
