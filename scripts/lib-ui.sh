# shellcheck shell=bash
# Оформление как у базового установщика (цвета, баннер).
if [[ -t 1 ]]; then
  G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  G=; Y=; R=; B=; D=; N=
fi

say()  { printf '%s\n' "${G}==>${N} $*"; }
warn() { printf '%s\n' "${Y}!${N}  $*" >&2; }
die()  { printf '%s\n' "${R}✗${N}  $*" >&2; exit 1; }

antitspu_banner() {
  echo
  printf '%s' "$G"
  cat <<'ART'
  _ _                   _   _          _          _      _
 (_) |_ ___ _ __   ___ | |_| | ___   _| |__  _ __(_) ___| | __
 | | __/ __| '_ \ / _ \| __| |/ / | | | '_ \| '__| |/ __| |/ /
 | | |_\__ \ | | | (_) | |_|   <| |_| | |_) | |  | | (__|   <
 |_|\__|___/_| |_|\___/ \__|_|\_\\__,_|_.__/|_|  |_|\___|_|\_\
ART
  printf '%s' "$N"
  echo
  echo "${B}3x-ui-antitspu${N} — панель 3X-UI, Xray, anti-TSPU overlay"
  echo
  echo "  https://github.com/norachchan/3x-ui-antitspu"
  echo "  ${D}it's not Kubrick. it's just a VPN.${N}"
  echo
}
