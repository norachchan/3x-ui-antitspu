#!/usr/bin/env bash
# 3x-ui-antitspu — установка панели, протоколов и anti-TSPU overlay.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/norachchan/3x-ui-antitspu/main/install.sh)
#
# Только overlay:
#   SKIP_BASE_INSTALL=1 bash <(curl -fsSL .../install.sh)
#
# Флаги установщика после -- :
#   bash install.sh -- --domain stats.example.com -y
#
set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/norachchan/3x-ui-antitspu.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/3x-ui-antitspu}"

[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo -i" >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }

sub_proxy_ready() {
  [[ -f /usr/local/lib/kit-sub/kit_sub.py ]] && [[ -f /etc/kit-sub/config.json ]]
}

xui_present() {
  [[ -f /etc/x-ui/x-ui.db ]] || [[ -f /etc/x-ui/install-result.env ]]
}

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

installer_args=()
if [[ "${1:-}" == "--" ]]; then
  shift
  installer_args=("$@")
fi

if [[ "${SKIP_BASE_INSTALL:-0}" != "1" ]] && ! xui_present; then
  bash "$INSTALL_DIR/scripts/base-install.sh" -- "${installer_args[@]}"
  if [[ -x /usr/local/bin/kit ]]; then
    /usr/local/bin/kit update --unattended 2>/dev/null || true
  fi
elif [[ "${#installer_args[@]}" -gt 0 ]]; then
  say "Панель уже есть — аргументы установщика не применяются (только overlay)."
fi

if ! sub_proxy_ready && xui_present; then
  say "Сервис подписки не найден — bootstrap"
  bash "$INSTALL_DIR/scripts/bootstrap-sub.sh"
fi

bash "$INSTALL_DIR/scripts/apply.sh"

say ""
say "Готово. Каталог: $INSTALL_DIR"
say "Повтор overlay: ANTITSPU_DIR=$INSTALL_DIR bash $INSTALL_DIR/scripts/apply.sh"
say "Донастройка: $INSTALL_DIR/docs/PANEL-TUNING.md"
