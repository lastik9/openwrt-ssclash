#!/bin/sh
# uninstall-ssclash.sh — удаление SSClash с OpenWrt 25 (apk)
# https://github.com/lastik9/openwrt-ssclash
#
# Тонкая обёртка: вся логика удаления живёт в setup-ssclash.sh (действие
# `uninstall`), чтобы код не дублировался. Скрипт можно запускать сам по себе —
# если setup-ssclash.sh лежит рядом, используется он (без сети), иначе качается.
set -u

SETUP_URL="https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/setup-ssclash.sh"

# 1) локальная копия рядом — работает офлайн
if [ -f ./setup-ssclash.sh ]; then
  exec sh ./setup-ssclash.sh uninstall
fi

# 2) иначе скачиваем setup и запускаем его в режиме uninstall
TMP=/tmp/setup-ssclash.sh
if command -v curl >/dev/null 2>&1 && curl -fsSL "$SETUP_URL" -o "$TMP" 2>/dev/null; then
  exec sh "$TMP" uninstall
elif command -v wget >/dev/null 2>&1 && wget -qO "$TMP" "$SETUP_URL" 2>/dev/null; then
  exec sh "$TMP" uninstall
else
  echo "Не удалось получить setup-ssclash.sh (нет сети?)." >&2
  echo "Скачай его рядом и запусти:  sh setup-ssclash.sh uninstall" >&2
  exit 1
fi
