#!/bin/sh
# setup-ssclash.sh — установщик SSClash (ядро Mihomo/Clash.Meta) на OpenWrt 25 (apk)
# https://github.com/lastik9/openwrt-ssclash
#
# Запуск без аргументов показывает меню. Пункты:
#   1) Полная установка: панель + ядро + (спросит) проксирование «за белыми списками»
#   2) Только панель + ядро (установка/обновление до последних версий)
#   3) Доустановить проксирование «за белыми списками»
#   4) Убрать проксирование
#   5) Удалить SSClash (панель + ядро + конфиги)
#   0) Выход
#
# Можно и без меню, аргументом: install | app | bypass | unbypass | uninstall
# Меню требует запуска файлом (sh setup-ssclash.sh), а не через '| sh'.
set -u

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; NC='\033[0m'
msg()  { printf "%b>>%b %s\n" "$GRN" "$NC" "$1"; }
warn() { printf "%b!!%b %s\n" "$YLW" "$NC" "$1"; }
die()  { printf "%b##%b %s\n" "$RED" "$NC" "$1" >&2; exit 1; }
ask()  { printf "%b??%b %s [y/N]: " "$YLW" "$NC" "$1"; read -r _a; case "$_a" in [Yy]*) return 0 ;; *) return 1 ;; esac; }

SSCLASH_REPO="zerolabnet/SSClash"
MIHOMO_REPO="MetaCubeX/mihomo"
CLASH_DIR="/opt/clash"
CLASH_BIN="$CLASH_DIR/bin/clash"
DEPS="curl kmod-nft-tproxy kmod-tun coreutils-base64"
BYPASS_FILE="/etc/profile.d/ssclash-proxy.sh"

# MIRROR: префикс-зеркало для GitHub на случай, когда провайдер режет github.com
# (в РФ доступность падает — выборочные обрывы CDN). Пусто = прямой GitHub.
# Оборачивает И api.github.com, И скачивание релизов. Примеры:
#   MIRROR=https://gh-proxy.com/ sh setup-ssclash.sh app      # публичный прокси
#   MIRROR=https://mirror.my.srv/ sh setup-ssclash.sh app     # свой reverse-proxy
# Альтернатива без правок скрипта — прогнать всё через свой заграничный сервер:
#   https_proxy=http://ЗАГРАН:PORT sh setup-ssclash.sh app
MIRROR="${MIRROR:-}"

# mirror_url: применить префикс-зеркало к ссылке (или вернуть как есть)
mirror_url() {
  case "$MIRROR" in
    "") echo "$1" ;;
    */) echo "${MIRROR}$1" ;;
    *)  echo "${MIRROR}/$1" ;;
  esac
}

# fetch: скачать с ретраями (гасит выборочные обрывы GitHub). $1=url $2=выходной файл
# --retry-all-errors: повтор даже при TLS-ресетах/HTTP-ошибках, типичных для троттлинга.
fetch() {
  curl -fL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors \
    "$(mirror_url "$1")" -o "$2"
}

command -v apk >/dev/null 2>&1 || \
  die "apk не найден. Скрипт для OpenWrt >= 25 (apk). Для сборок на opkg он не предназначен."

# --- определение архитектуры для ядра Mihomo -------------------------------
# raw_arch: арка пакетов OpenWrt (aarch64_cortex-a53, mipsel_24kc, x86_64, ...)
raw_arch() {
  a="$(apk --print-arch 2>/dev/null)"
  [ -z "$a" ] && a="$(sed -n "s/^DISTRIB_ARCH='\(.*\)'/\1/p" /etc/openwrt_release 2>/dev/null)"
  [ -z "$a" ] && a="$(uname -m)"
  echo "$a"
}

# map_arch: OpenWrt-арка ($1) -> имя сборки ядра Mihomo
map_arch() {
  case "$1" in
    aarch64*|arm64*)                                echo "arm64" ;;
    x86_64*)                                        echo "amd64-compatible" ;;  # безопасно для любого x86
    i386*|i486*|i686*|x86*)                         echo "386" ;;
    arm_cortex-a5*|arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9*|arm_cortex-a15*|arm_cortex-a17*|armv7*|armhf*)
                                                    echo "armv7" ;;
    arm_arm1176*|arm_bcm2708*|armv6*)               echo "armv6" ;;
    arm_arm926*|arm_fa526*|arm_mpcore*|arm_xscale*|arm_arm920*|armv5*|armel*|arm*)
                                                    echo "armv5" ;;
    mips64el*|mips64le*)                             echo "mips64le" ;;
    mips64*)                                        echo "mips64" ;;
    mipsel*|mipsle*)                                echo "mipsle-softfloat" ;;  # OpenWrt mips = softfloat
    mips*)                                          echo "mips-softfloat" ;;
    riscv64*)                                       echo "riscv64" ;;
    loongarch64*|loong64*)                          echo "loong64" ;;
    *) die "Не знаю арку '$1'. Задайте вручную: ARCH=arm64 sh setup-ssclash.sh" ;;
  esac
}

detect_arch() {
  if [ -n "${ARCH:-}" ]; then echo "$ARCH"; return; fi
  map_arch "$(raw_arch)"
}

# gh_asset: ссылка на ассет последнего релиза. $1 = repo, $2 = grep-шаблон
gh_asset() {
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
    "$(mirror_url "https://api.github.com/repos/$1/releases/latest")" \
    | grep -o "https://[^\"]*$2" | head -n1
}

# --- шаги установки --------------------------------------------------------
install_app() {
  msg "Обновляю список пакетов..."
  apk update </dev/null >/dev/null 2>&1 || die "apk update не удался"

  msg "Ставлю зависимости: $DEPS"
  apk add $DEPS </dev/null >/dev/null 2>&1 || die "не удалось поставить зависимости"

  # активируем свежеустановленные модули ядра, чтобы не требовать перезагрузку
  modprobe tun 2>/dev/null
  modprobe nft_tproxy 2>/dev/null

  msg "Ищу последнюю версию luci-app-ssclash..."
  APK_URL="$(gh_asset "$SSCLASH_REPO" "\.apk")"
  [ -n "$APK_URL" ] || die "не нашёл .apk (лимит GitHub API?). Повторите позже."
  msg "  $APK_URL"
  fetch "$APK_URL" /tmp/luci-app-ssclash.apk || die "скачивание .apk не удалось"
  apk add --allow-untrusted /tmp/luci-app-ssclash.apk </dev/null || die "установка .apk не удалась"
  rm -f /tmp/luci-app-ssclash.apk
  msg "luci-app-ssclash установлен."
}

install_core() {
  MARCH="$(detect_arch)"
  if [ -n "${ARCH:-}" ]; then
    msg "Арка ядра (задана вручную ARCH): $MARCH"
  else
    msg "Арка OpenWrt: $(raw_arch)  ->  сборка Mihomo: $MARCH"
  fi
  msg "Ищу последнюю версию ядра Mihomo..."
  CORE_URL="$(gh_asset "$MIHOMO_REPO" "mihomo-linux-${MARCH}-v[0-9][^\"]*\.gz")"
  [ -n "$CORE_URL" ] || die "не нашёл ядро Mihomo для '$MARCH'"
  msg "  $CORE_URL"
  mkdir -p "$CLASH_DIR/bin"
  fetch "$CORE_URL" /tmp/clash.gz || die "скачивание ядра не удалось"
  gunzip -c /tmp/clash.gz > "$CLASH_BIN" || die "распаковка ядра не удалась"
  chmod +x "$CLASH_BIN"
  rm -f /tmp/clash.gz
  msg "Ядро Mihomo установлено: $CORE_URL"
}

enable_bypass() {
  cat > "$BYPASS_FILE" << 'EOF'
# Добавлено openwrt-ssclash: трафик роутера (apk/curl) через локальный прокси Mihomo.
# Прокси включается ТОЛЬКО когда ядро запущено — иначе apk/curl не сломаются,
# если Mihomo не работает (упал или ещё грузится после перезагрузки).
if pidof clash >/dev/null 2>&1; then
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  # LAN-адрес роутера берётся на лету через uci — без привязки к конкретному IP
  _lan="$(uci -q get network.lan.ipaddr 2>/dev/null)"
  export no_proxy="127.0.0.1,localhost,::1${_lan:+,$_lan}"
  unset _lan
fi
EOF
  chmod +x "$BYPASS_FILE"
  msg "Проксирование включено: создан $BYPASS_FILE"
  [ -x "$CLASH_BIN" ] || warn "Ядро ещё не установлено — пункт заработает после установки ядра и запуска Clash."
  warn "В конфиге Mihomo нужна строка 'mixed-port: 7890' и правило для домена"
  warn "  обновлений, напр. 'DOMAIN-SUFFIX,openwrt.org,PROXY' (см. README)."
  warn "Применится в НОВОЙ SSH-сессии или после перезагрузки."
}

disable_bypass() {
  if [ -f "$BYPASS_FILE" ]; then
    rm -f "$BYPASS_FILE"
    msg "Проксирование выключено: $BYPASS_FILE удалён."
    warn "Переменные пропадут в НОВОЙ SSH-сессии (в текущей ещё живут)."
  else
    warn "Проксирование не было настроено ($BYPASS_FILE отсутствует)."
  fi
}

final_hint() {
  echo
  msg "Готово. Clash сейчас остановлен."
  msg "Автозапуск при загрузке — по умолчанию включён (скрипт его не менял)."
  warn "Дальнейшие шаги:"
  warn "  1. LuCI -> Services -> SSClash: залей свой конфиг Clash/Mihomo."
  warn "  2. Запусти: '/etc/init.d/clash start' (или кнопкой в панели),"
  warn "     либо перезагрузи роутер — Clash поднимется сам."
}

# --- действия (пункты меню) ------------------------------------------------
act_full() {
  install_app
  echo
  if ask "Скачать ядро Mihomo сейчас через CLI? (иначе — кнопкой в LuCI)"; then
    install_core
  else
    warn "Ядро не установлено. В LuCI: Services -> SSClash -> Settings ->"
    warn "  Mihomo Kernel Management -> \"Download Latest Kernel\"."
  fi
  echo
  warn "Обновления «за белыми списками»: трафик роутера (apk/curl) через прокси Mihomo,"
  warn "чтобы обновляться, когда провайдер режет OpenWrt/GitHub напрямую."
  if ask "Настроить проксирование трафика роутера?"; then
    enable_bypass
  fi
  final_hint
}

act_app() {
  install_app
  echo
  if ask "Скачать ядро Mihomo сейчас через CLI? (иначе — кнопкой в LuCI)"; then
    install_core
  else
    warn "Ядро не установлено. В LuCI: Services -> SSClash -> Settings ->"
    warn "  Mihomo Kernel Management -> \"Download Latest Kernel\"."
  fi
  final_hint
}

act_bypass()   { enable_bypass; }
act_unbypass() { disable_bypass; }

do_uninstall() {
  warn "Удаление SSClash: пакет luci-app-ssclash и каталог /opt/clash (конфиги и ядро)."
  ask "Точно удалить?" || { msg "Отменено."; return 0; }

  msg "Останавливаю и выключаю сервис..."
  if [ -x /etc/init.d/clash ]; then
    /etc/init.d/clash stop 2>/dev/null
    /etc/init.d/clash disable 2>/dev/null
  fi

  msg "Удаляю пакет luci-app-ssclash..."
  apk del luci-app-ssclash 2>/dev/null || warn "пакет не был установлен"

  msg "Удаляю каталог $CLASH_DIR (конфиги и ядро)..."
  rm -rf "$CLASH_DIR"

  if [ -f "$BYPASS_FILE" ]; then
    msg "Удаляю $BYPASS_FILE (проксирование трафика роутера)..."
    rm -f "$BYPASS_FILE"
  fi

  # сброс кэша меню LuCI
  rm -f /tmp/luci-indexcache* 2>/dev/null
  rm -rf /tmp/luci-modulecache 2>/dev/null

  echo
  warn "Общесистемные зависимости могли ставить и другие сервисы, поэтому по умолчанию НЕ трогаю:"
  warn "  kmod-nft-tproxy, kmod-tun, coreutils-base64  (curl оставлю в любом случае)"
  if ask "Удалить эти зависимости тоже? Только если роутер выделен под SSClash"; then
    apk del kmod-nft-tproxy kmod-tun coreutils-base64 2>/dev/null
    msg "Зависимости удалены."
  fi

  echo
  msg "SSClash полностью удалён."
  if ask "Перезагрузить роутер сейчас?"; then
    reboot
  fi
}

# --- меню ------------------------------------------------------------------
menu() {
  while :; do
    if [ -f "$BYPASS_FILE" ]; then _bs="включено"; else _bs="выключено"; fi
    printf "\n"
    printf "  %bSSClash — установщик%b  (%s)\n" "$GRN" "$NC" "lastik9/openwrt-ssclash"
    printf "  проксирование «за белыми списками»: %s\n\n" "$_bs"
    echo   "  1) Полная установка: панель + ядро + проксирование (спросит)"
    echo   "  2) Только панель + ядро (установка/обновление)"
    echo   "  3) Доустановить проксирование «за белыми списками»"
    echo   "  4) Убрать проксирование"
    echo   "  5) Удалить SSClash (панель + ядро + конфиги)"
    echo   "  0) Выход"
    printf "  Выбор: "
    read -r _ch
    case "$_ch" in
      1) act_full ;;
      2) act_app ;;
      3) act_bypass ;;
      4) act_unbypass ;;
      5) do_uninstall ;;
      0|q|Q|"") exit 0 ;;
      *) warn "Нет такого пункта: '$_ch'." ;;
    esac
  done
}

# --- разбор аргументов -----------------------------------------------------
case "${1:-menu}" in
  menu)
    if [ -t 0 ]; then
      menu
    else
      warn "Меню требует интерактивного ввода, а скрипт запущен через пайп."
      warn "Скачай файл и запусти его:"
      warn "  wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/setup-ssclash.sh"
      warn "  sh setup-ssclash.sh"
      warn "Либо укажи действие аргументом: install | app | bypass | unbypass"
      exit 1
    fi ;;
  install)  act_full ;;
  app)      act_app ;;
  bypass)   act_bypass ;;
  unbypass) act_unbypass ;;
  uninstall|remove) do_uninstall ;;
  *) die "Неизвестно: '$1'. Используй: (без аргумента) | install | app | bypass | unbypass | uninstall" ;;
esac
