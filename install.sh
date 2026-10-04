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
RAN_BASE=0

[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo -i" >&2; exit 1; }

say_plain() { printf '==> %s\n' "$*"; }

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  say_plain "Клонирование $REPO_URL → $INSTALL_DIR"
  apt-get update -qq
  apt-get install -y -qq git ca-certificates curl jq patch python3 python3-yaml qrencode >/dev/null
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  say_plain "Обновление репозитория в $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || true
fi

# curl | bash отдаёт старую копию в память — после pull всегда запускаем install.sh с диска.
LOCAL_INSTALL="$INSTALL_DIR/install.sh"
if [[ -f "$LOCAL_INSTALL" ]] && [[ "${ANTITSPU_REEXEC:-0}" != 1 ]]; then
  export ANTITSPU_REEXEC=1
  exec bash "$LOCAL_INSTALL" "$@"
fi

# shellcheck source=scripts/lib-ui.sh
. "$INSTALL_DIR/scripts/lib-ui.sh"

sub_proxy_ready() {
  [[ -f /usr/local/lib/kit-sub/kit_sub.py ]] && [[ -f /etc/kit-sub/config.json ]]
}

xui_present() {
  [[ -f /etc/x-ui/x-ui.db ]] || [[ -f /etc/x-ui/install-result.env ]]
}

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
  RAN_BASE=1
  bash "$INSTALL_DIR/scripts/base-install.sh" -- "${installer_args[@]}"
  if [[ -x /usr/local/bin/kit ]]; then
    /usr/local/bin/kit update --unattended 2>/dev/null || true
  fi
elif [[ "${#installer_args[@]}" -gt 0 ]]; then
  warn "Панель уже есть — аргументы установщика не применяются (только overlay)."
fi

if ! sub_proxy_ready && xui_present; then
  say "Сервис подписки не найден — bootstrap"
  bash "$INSTALL_DIR/scripts/bootstrap-sub.sh"
fi

bash "$INSTALL_DIR/scripts/apply.sh"

if [[ "$RAN_BASE" == 1 ]]; then
  bash "$INSTALL_DIR/scripts/finish-install.sh" compact
else
  bash "$INSTALL_DIR/scripts/finish-install.sh" full
fi
