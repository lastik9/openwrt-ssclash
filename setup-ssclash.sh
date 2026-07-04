#!/bin/sh
# setup-ssclash.sh — установка SSClash (ядро Mihomo/Clash.Meta) на OpenWrt 25 (apk)
# https://github.com/lastik9/openwrt-ssclash
#
# Ставит зависимости и luci-app-ssclash последней версии.
# Ядро Mihomo можно скачать сразу из CLI (спросит) или потом кнопкой в LuCI.
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
  curl -sL "https://api.github.com/repos/$1/releases/latest" \
    | grep -o "https://[^\"]*$2" | head -n1
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
  curl -L "$CORE_URL" -o /tmp/clash.gz || die "скачивание ядра не удалось"
  gunzip -c /tmp/clash.gz > "$CLASH_BIN" || die "распаковка ядра не удалась"
  chmod +x "$CLASH_BIN"
  rm -f /tmp/clash.gz
}

# --- установка -------------------------------------------------------------
msg "Обновляю список пакетов..."
apk update >/dev/null 2>&1 || die "apk update не удался"

msg "Ставлю зависимости: $DEPS"
apk add $DEPS >/dev/null 2>&1 || die "не удалось поставить зависимости"

# активируем свежеустановленные модули ядра, чтобы не требовать перезагрузку
modprobe tun 2>/dev/null
modprobe nft_tproxy 2>/dev/null

msg "Ищу последнюю версию luci-app-ssclash..."
APK_URL="$(gh_asset "$SSCLASH_REPO" "\.apk")"
[ -n "$APK_URL" ] || die "не нашёл .apk (лимит GitHub API?). Повторите позже."
msg "  $APK_URL"
curl -L "$APK_URL" -o /tmp/luci-app-ssclash.apk || die "скачивание .apk не удалось"
apk add --allow-untrusted /tmp/luci-app-ssclash.apk || die "установка .apk не удалась"
rm -f /tmp/luci-app-ssclash.apk

CORE_DONE=0
echo
if ask "Скачать ядро Mihomo сейчас через CLI? (иначе — кнопкой в LuCI)"; then
  install_core
  CORE_DONE=1
fi

echo
msg "Готово. luci-app-ssclash установлен: $APK_URL"
if [ "$CORE_DONE" = "1" ]; then
  msg "Ядро Mihomo: $CORE_URL"
else
  warn "Ядро не установлено. В LuCI: Services -> SSClash -> Settings ->"
  warn "  Mihomo Kernel Management -> \"Download Latest Kernel\""
  warn "  (приложение само определит арку и скачает последнее ядро)."
fi

echo
warn "Опция для обновлений «за белыми списками»: пускать трафик самого роутера"
warn "(apk/curl) через локальный прокси Mihomo, чтобы обновляться, когда провайдер"
warn "режет доступ к репозиториям OpenWrt/GitHub напрямую."
warn "Требует в конфиге Mihomo строки 'mixed-port: 7890' (подробности — в README)."
if ask "Настроить проксирование трафика роутера?"; then
  cat > /etc/profile.d/ssclash-proxy.sh << 'EOF'
# Добавлено openwrt-ssclash: трафик роутера (apk/curl) через локальный прокси Mihomo.
# Прокси включается ТОЛЬКО когда ядро запущено — иначе apk/curl не сломаются,
# если Mihomo не работает (упал или ещё грузится после перезагрузки).
if pidof clash >/dev/null 2>&1; then
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export no_proxy="127.0.0.1,localhost,::1"
fi
EOF
  chmod +x /etc/profile.d/ssclash-proxy.sh
  msg "Создан /etc/profile.d/ssclash-proxy.sh"
  warn "Проверь, что в конфиге Mihomo есть 'mixed-port: 7890' и правило для домена"
  warn "  обновлений, напр. 'DOMAIN-SUFFIX,openwrt.org,PROXY' (см. README)."
  warn "Настройка применится в НОВОЙ SSH-сессии или после перезагрузки."
fi

echo
msg "Установка завершена. Clash сейчас остановлен."
msg "Автозапуск при загрузке — по умолчанию включён (скрипт его не менял)."
warn "Дальнейшие шаги:"
warn "  1. LuCI -> Services -> SSClash: залей свой конфиг Clash/Mihomo."
warn "  2. Запусти сейчас: '/etc/init.d/clash start' (или кнопкой в панели),"
warn "     либо просто перезагрузи роутер — Clash поднимется сам."
