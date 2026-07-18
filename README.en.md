# openwrt-ssclash

[Русский](https://github.com/lastik9/openwrt-ssclash/blob/main/README.md) · **English** · [中文](https://github.com/lastik9/openwrt-ssclash/blob/main/README.zh-CN.md)

Installer for **SSClash** — transparent censorship bypass on **OpenWrt 25 (apk)** via the **Mihomo (Clash.Meta)** core and the [luci-app-ssclash](https://github.com/zerolabnet/SSClash) web panel.

One run on a clean system: installs the dependencies and the latest version of the panel, and either pulls the Mihomo core straight from the console (on confirmation) or leaves it to the button in LuCI. A separate uninstaller is included for a clean removal.

## Why

[luci-app-ssclash](https://github.com/zerolabnet/SSClash) is a wrapper around the [Mihomo](https://github.com/MetaCubeX/mihomo) core that routes the router's traffic through a proxy (VLESS/Shadowsocks/Trojan, etc.) according to the rules in your config. Setting it up normally takes several manual steps with hardcoded package and core versions. This script removes the busywork: it grabs the **latest** versions of the panel and the core from GitHub and detects the router's architecture to pick the right Mihomo build.

## Requirements

- OpenWrt 25.x with the **apk** package manager (opkg-based builds are not supported).
- Internet access on the router at run time — packages, the panel and the core are downloaded from GitHub.
- A little free space in `/opt` for the Mihomo core (~15–30 MB unpacked).

## What the script does

1. `apk update`, installs dependencies (`curl`, `kmod-nft-tproxy`, `kmod-tun`, `coreutils-base64`) and loads the `tun`, `nft_tproxy` kernel modules — so no reboot is needed.
2. Resolves the latest **luci-app-ssclash** release via the GitHub API and installs it (`apk add --allow-untrusted`).
3. *(Optional, with confirmation)* detects the router's arch via `apk --print-arch`, finds the matching latest **Mihomo** core and unpacks it to `/opt/clash/bin/clash`.
4. Leaves the service **stopped** and does **not** reboot the router — so you first open the panel, upload the config, and then start Clash yourself. The script does **not** touch boot autostart (the package enables it by default).

If you skip the core in step 3, the panel installs it in one click: **Services → SSClash → Settings → Mihomo Kernel Management → Download Latest Kernel** (it detects the arch on its own too).

## Installation

Run the commands **on the router** (over SSH), not on your computer:

```
wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/setup-ssclash.sh
sh setup-ssclash.sh
```

This shows a menu:

```
  1) Full install: panel + core + proxying (asks)
  2) Panel + core only (install/update)
  3) Add "behind a whitelist" proxying
  4) Remove proxying
  0) Exit
```

For a first install pick **1**. Options **3/4** are handy later: if you installed without proxying, you can add it (or remove it) separately without reinstalling everything. The menu needs the script to be run as a file (`sh setup-ssclash.sh`); it won't work via `| sh` — in that case pass an action as an argument instead: `install`, `app`, `bypass`, `unbypass`.

After installation Clash is **stopped**. Open **Services → SSClash** in LuCI, upload your Clash/Mihomo config and start the service — from the panel or with:

```
/etc/init.d/clash start
```

Autostart on boot is already enabled by default, so after a reboot Clash comes up on its own.

Normally you don't need to set the arch — the script figures it out. The `ARCH=` prefix is only needed if autodetection got it wrong. It's set **at launch**, on the same line (it's an environment variable, not a separate step):

```
sh setup-ssclash.sh             # normal run — arch is detected automatically
ARCH=arm64 sh setup-ssclash.sh  # run with a forced arch
```

Possible `ARCH` values: `amd64-compatible`, `amd64`, `amd64-v3`, `386`, `arm64`, `armv7`, `armv6`, `armv5`, `mipsle-softfloat`, `mips-softfloat`, `mips64le`, `mips64`, `riscv64`, `loong64`.

## If GitHub is throttled (e.g. in Russia)

Since May 2026 GitHub access from Russia has been unstable — downloads may drop mid-transfer. The script already retries on its own (`curl --retry`), so re-running often just works. If it doesn't, two ways around it.

Via your own overseas server (no script changes — `curl` and `apk` honor `https_proxy`):

```
https_proxy=http://HOST:PORT sh setup-ssclash.sh app
```

Via a GitHub mirror — the `MIRROR` variable wraps both the API and release downloads:

```
MIRROR=https://gh-proxy.com/ sh setup-ssclash.sh app
```

Use a public GitHub proxy (the example above — check it's alive) or your own reverse-proxy; self-hosted is more reliable. Empty (default) means direct GitHub — nothing to do in unrestricted regions.

## Updating from behind a whitelist

If your ISP blocks direct access to the OpenWrt/GitHub repositories (e.g. mobile internet in "whitelist" mode), you can update the router's packages through the Mihomo proxy that's already running: the router's own traffic (`apk`, `curl`) is sent to the local proxy at `127.0.0.1:7890`.

It's set up in two places.

**1. Mihomo config** (uploaded via LuCI — you edit it yourself). Open the local port and add a rule sending the update domains through the proxy node:

```yaml
mixed-port: 7890

rules:
  - DOMAIN-SUFFIX,openwrt.org,PROXY
  # add github.com, githubusercontent.com, etc. if needed
```

Prefer binding the port to localhost only (`bind-address: 127.0.0.1`) so you don't turn the router into an open proxy on the LAN.

**2. The router's environment variables.** This is what `setup-ssclash.sh` does — during install it asks "Set up proxying of the router's traffic?" (menu option **1**). You can also add or remove it later via menu options **3/4** (or `sh setup-ssclash.sh bypass` / `unbypass`), without reinstalling everything. If you agree, it creates `/etc/profile.d/ssclash-proxy.sh`:

```sh
if pidof clash >/dev/null 2>&1; then
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  # the router's LAN address is resolved on the fly via uci — no hardcoded IP
  _lan="$(uci -q get network.lan.ipaddr 2>/dev/null)"
  export no_proxy="127.0.0.1,localhost,::1${_lan:+,$_lan}"
  unset _lan
fi
```

The `pidof clash` check matters: the proxy is enabled only while the core is running. If Mihomo is down (crashed or still starting after a reboot), the variables are not set — so `apk`/`curl` don't break trying to reach a dead port. The router's LAN address in `no_proxy` isn't hardcoded — it's resolved at each login via `uci`, so the file works the same on any router. The setting applies to new SSH sessions (the profile is read at login).

For a one-off test without touching the profile, do the same in the current session:

```
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
apk update
```

The `/etc/profile.d/ssclash-proxy.sh` file is removed automatically by the uninstaller.

## Uninstall

You can remove it two ways — both call the same logic:

- via menu option **5** in `setup-ssclash.sh`;
- via the standalone uninstaller (on the router):

```
wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/uninstall-ssclash.sh
sh uninstall-ssclash.sh
```

It first asks for confirmation, always removes SSClash itself, and at the end **asks separately** whether to also remove the system-wide dependencies. The difference:

**Basic uninstall** (always performed) removes what belongs to SSClash specifically: the `luci-app-ssclash` package, the entire `/opt/clash` directory (the Mihomo core and your configs) and the LuCI menu cache. After this SSClash is gone from the router — enough in 99% of cases.

**Full uninstall** (if you answer "yes" to the dependency prompt) additionally removes the system packages SSClash pulled in to work:

- `kmod-tun` — kernel module for TUN interfaces;
- `kmod-nft-tproxy` — nftables module for transparent proxying;
- `coreutils-base64` — the base64 utility.

The catch is that these are **shared** packages: other things on the router may use them too (VPNs like OpenVPN/WireGuard setups, other proxies, various scripts). Remove them while something else relies on them, and that something breaks. So by default the script **keeps** them: they take up next to nothing and bother no one. Agree to remove them only if the router is dedicated to SSClash and you are sure nothing else uses them. `curl` is never removed — too many things need it.

## Architecture mapping

| OpenWrt (`apk --print-arch`)   | Mihomo build          |
| ------------------------------ | --------------------- |
| `aarch64_*`                    | `arm64`               |
| `x86_64`                       | `amd64-compatible`    |
| `i386_*`                       | `386`                 |
| `arm_cortex-a7/a9/a15…`        | `armv7`               |
| `arm_arm1176*` (Pi1/Zero)      | `armv6`               |
| `arm_mpcore/fa526/xscale…`     | `armv5`               |
| `mipsel_24kc`                  | `mipsle-softfloat`    |
| `mips_24kc`                    | `mips-softfloat`      |
| `mips64el_*` / `mips64_*`      | `mips64le` / `mips64` |
| `riscv64_*`                    | `riscv64`             |
| `loongarch64_*`                | `loong64`             |

## Credits

This project is just an installer. All the real work is done upstream:

- [zerolabnet/SSClash](https://github.com/zerolabnet/SSClash) — the luci-app-ssclash panel
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) — the Clash.Meta core
- [fildunsky](https://github.com/fildunsky) — the "updating from behind a whitelist" idea (routing the router's own traffic through Mihomo)

The installed components are the property of their authors and are distributed under their own licenses. This license (MIT) covers only the code of this script.

## License

[MIT](LICENSE) © 2026 lastik9
