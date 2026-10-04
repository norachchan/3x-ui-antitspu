#!/usr/bin/env bash
# 3x-ui-antitspu — единый установщик: встроенный 3X-UI KIT + overlay против ТСПУ.
#
# Новый VPS (одна команда):
#   bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh)
#
# Только overlay (панель уже есть):
#   SKIP_BASE_INSTALL=1 bash <(curl -fsSL .../install.sh)
#
# Аргументы KIT после -- :
#   bash install.sh -- --domain stats.example.com -y
#
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/norachchan/3x-ui-antitspu.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/3x-ui-antitspu}"

[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo -i" >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }

kit_sub_ready() {
  [[ -f /usr/local/lib/kit-sub/kit_sub.py ]] && [[ -f /etc/kit-sub/config.json ]]
}

xui_present() {
  [[ -f /etc/x-ui/x-ui.db ]] || [[ -f /etc/x-ui/install-result.env ]]
}

# --- репозиторий (нужен vendor/kit) ---
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  say "Клонирование $REPO_URL → $INSTALL_DIR"
  apt-get update -qq
  apt-get install -y -qq git ca-certificates curl jq patch python3 >/dev/null
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  say "Обновление репозитория в $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || true
fi

export ANTITSPU_DIR="$INSTALL_DIR"

if [[ ! -f /etc/3x-ui-antitspu.env ]] && [[ -f "$INSTALL_DIR/config/antitspu.env.example" ]]; then
  cp "$INSTALL_DIR/config/antitspu.env.example" /etc/3x-ui-antitspu.env
fi
if [[ -x "$INSTALL_DIR/scripts/configure-prompt.sh" ]]; then
  bash "$INSTALL_DIR/scripts/configure-prompt.sh"
fi
export ANTITSPU_SKIP_PROMPT=1

# --- базовый стек KIT из vendor ---
kit_args=()
if [[ "${1:-}" == "--" ]]; then
  shift
  kit_args=("$@")
fi

if [[ "${SKIP_BASE_INSTALL:-0}" != "1" ]] && ! xui_present; then
  bash "$INSTALL_DIR/scripts/kit-install.sh" -- "${kit_args[@]}"
  if command -v kit >/dev/null; then
    say "Проверка обновлений kit CLI"
    kit update --unattended 2>/dev/null || true
  fi
elif [[ "${#kit_args[@]}" -gt 0 ]]; then
  say "Панель уже есть — флаги KIT игнорируются (overlay только). Для KIT: удалите SKIP_BASE_INSTALL или переустановите вручную."
fi

if ! kit_sub_ready && xui_present; then
  say "Панель есть, kit-sub нет — bootstrap"
  bash "$INSTALL_DIR/scripts/bootstrap-kit-sub.sh"
fi

bash "$INSTALL_DIR/scripts/apply.sh"

say ""
say "Готово. Каталог: $INSTALL_DIR"
say "Повтор overlay: ANTITSPU_DIR=$INSTALL_DIR bash $INSTALL_DIR/scripts/apply.sh"
say "Донастройка панели: $INSTALL_DIR/docs/PANEL-TUNING.md"
