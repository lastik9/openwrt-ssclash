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

1. `apk update` and installs dependencies: `curl`, `kmod-nft-tproxy`, `kmod-tun`, `coreutils-base64`.
2. Resolves the latest **luci-app-ssclash** release via the GitHub API and installs it (`apk add --allow-untrusted`).
3. *(Optional, with confirmation)* detects the router's arch via `apk --print-arch`, finds the matching latest **Mihomo** core and unpacks it to `/opt/clash/bin/clash`.
4. Enables the service (`/etc/init.d/clash enable`).
5. *(Optional, with confirmation)* reboots the router.

If you skip the core in step 3, the panel installs it in one click: **Services → SSClash → Settings → Mihomo Kernel Management → Download Latest Kernel** (it detects the arch on its own too).

## Installation

Run the commands **on the router** (over SSH), not on your computer:

```
wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/setup-ssclash.sh
sh setup-ssclash.sh
```

After installation open **Services → SSClash** in LuCI, upload your Clash/Mihomo config and start the service.

Normally you don't need to set the arch — the script figures it out. The `ARCH=` prefix is only needed if autodetection got it wrong. It's set **at launch**, on the same line (it's an environment variable, not a separate step):

```
sh setup-ssclash.sh             # normal run — arch is detected automatically
ARCH=arm64 sh setup-ssclash.sh  # run with a forced arch
```

Possible `ARCH` values: `amd64-compatible`, `amd64`, `amd64-v3`, `386`, `arm64`, `armv7`, `armv6`, `armv5`, `mipsle-softfloat`, `mips-softfloat`, `mips64le`, `mips64`, `riscv64`, `loong64`.

## Uninstall

Remove everything the script installed. On the router:

```
wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/uninstall-ssclash.sh
sh uninstall-ssclash.sh
```

The script always removes SSClash itself, and at the end **asks separately** whether to also remove the system-wide dependencies. The difference:

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

The installed components are the property of their authors and are distributed under their own licenses. This license (MIT) covers only the code of this script.

## License

[MIT](LICENSE) © 2026 lastik9
