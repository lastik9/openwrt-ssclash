#!/bin/sh
# uninstall-ssclash.sh — полное удаление SSClash с OpenWrt 25 (apk)
# https://github.com/lastik9/openwrt-ssclash
set -u

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; NC='\033[0m'
msg()  { printf "%b>>%b %s\n" "$GRN" "$NC" "$1"; }
warn() { printf "%b!!%b %s\n" "$YLW" "$NC" "$1"; }
die()  { printf "%b##%b %s\n" "$RED" "$NC" "$1" >&2; exit 1; }
ask()  { printf "%b??%b %s [y/N]: " "$YLW" "$NC" "$1"; read -r _a; case "$_a" in [Yy]*) return 0 ;; *) return 1 ;; esac; }

CLASH_DIR="/opt/clash"

command -v apk >/dev/null 2>&1 || die "apk не найден. Скрипт для OpenWrt >= 25 (apk)."

msg "Останавливаю и выключаю сервис..."
if [ -x /etc/init.d/clash ]; then
  /etc/init.d/clash stop 2>/dev/null
  /etc/init.d/clash disable 2>/dev/null
fi

msg "Удаляю пакет luci-app-ssclash..."
apk del luci-app-ssclash 2>/dev/null || warn "пакет не был установлен"

msg "Удаляю каталог $CLASH_DIR (конфиги и ядро)..."
rm -rf "$CLASH_DIR"

# сброс кэша меню LuCI
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

echo
warn "Дальше — общесистемные зависимости. Их могли ставить и другие сервисы"
warn "(VPN, другие прокси, скрипты), поэтому по умолчанию я их НЕ трогаю:"
warn "  kmod-nft-tproxy, kmod-tun, coreutils-base64  (curl оставлю в любом случае)"
if ask "Удалить эти зависимости тоже? Соглашайся, только если роутер выделен под SSClash"; then
  apk del kmod-nft-tproxy kmod-tun coreutils-base64 2>/dev/null
  msg "Зависимости удалены."
fi

echo
msg "SSClash полностью удалён."
if ask "Перезагрузить роутер сейчас?"; then
  reboot
fi
