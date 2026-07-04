# openwrt-ssclash

[Русский](https://github.com/lastik9/openwrt-ssclash/blob/main/README.md) · [English](https://github.com/lastik9/openwrt-ssclash/blob/main/README.en.md) · **中文**

**SSClash** 安装脚本 —— 在 **OpenWrt 25 (apk)** 上通过 **Mihomo (Clash.Meta)** 内核与 [luci-app-ssclash](https://github.com/zerolabnet/SSClash) 网页面板实现透明的翻墙分流。

在干净系统上一次运行即可：安装依赖和最新版面板，Mihomo 内核既可以直接在命令行中下载（需确认），也可以留给 LuCI 里的按钮完成。另附独立的卸载脚本，用于干净地移除。

## 为什么

[luci-app-ssclash](https://github.com/zerolabnet/SSClash) 是 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核的封装，它按照你配置中的规则，将路由器流量经代理（VLESS/Shadowsocks/Trojan 等）转发。常规安装需要多个手动步骤，且写死了软件包和内核版本。本脚本省去这些琐事：自动从 GitHub 获取面板与内核的**最新**版本，并自动识别路由器架构以选择正确的 Mihomo 构建。

## 环境要求

- 使用 **apk** 包管理器的 OpenWrt 25.x（不支持基于 opkg 的固件）。
- 运行时路由器需能访问互联网 —— 软件包、面板和内核均从 GitHub 下载。
- `/opt` 需有少量空闲空间以存放 Mihomo 内核（解压后约 15–30 MB）。

## 脚本做了什么

1. 执行 `apk update`，安装依赖（`curl`、`kmod-nft-tproxy`、`kmod-tun`、`coreutils-base64`）并加载 `tun`、`nft_tproxy` 内核模块 —— 从而无需重启。
2. 通过 GitHub API 解析 **luci-app-ssclash** 的最新版本并安装（`apk add --allow-untrusted`）。
3. *（可选，需确认）* 通过 `apk --print-arch` 识别路由器架构，找到对应的最新 **Mihomo** 内核并解压到 `/opt/clash/bin/clash`。
4. 让服务保持**停止**，且**不重启**路由器 —— 以便你先进入面板、上传配置，然后自行启动 Clash。脚本**不改动**开机自启（软件包默认已启用）。

如果在第 3 步跳过了内核，面板可一键安装：**Services → SSClash → Settings → Mihomo Kernel Management → Download Latest Kernel**（它同样会自动识别架构）。

## 安装

命令需在**路由器上**（通过 SSH）执行，而不是在电脑上：

```
wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/setup-ssclash.sh
sh setup-ssclash.sh
```

安装完成后，Clash 处于**停止**状态。在 LuCI 中打开 **Services → SSClash**，上传你的 Clash/Mihomo 配置并启动服务 —— 用面板按钮或命令：

```
/etc/init.d/clash start
```

开机自启默认已启用，因此重启后 Clash 会自动启动。

通常无需指定架构 —— 脚本会自动识别。只有当自动识别有误时才需要 `ARCH=` 前缀。它在**启动时**、在同一行中设置（这是环境变量，而非单独的步骤）：

```
sh setup-ssclash.sh             # 普通运行 —— 自动识别架构
ARCH=arm64 sh setup-ssclash.sh  # 以强制指定的架构运行
```

`ARCH` 可选值：`amd64-compatible`、`amd64`、`amd64-v3`、`386`、`arm64`、`armv7`、`armv6`、`armv5`、`mipsle-softfloat`、`mips-softfloat`、`mips64le`、`mips64`、`riscv64`、`loong64`。

## 在白名单限制下更新

如果运营商屏蔽了对 OpenWrt/GitHub 软件源的直接访问（例如处于“白名单”模式的移动网络），可以通过已经在运行的 Mihomo 代理来更新路由器的软件包：把路由器自身的流量（`apk`、`curl`）发送到本地代理 `127.0.0.1:7890`。

需要在两处进行设置。

**1. Mihomo 配置**（通过 LuCI 上传，由你自己编辑）。开放本地端口，并添加一条把更新域名经代理节点转发的规则：

```yaml
mixed-port: 7890

rules:
  - DOMAIN-SUFFIX,openwrt.org,PROXY
  # 如有需要可加入 github.com、githubusercontent.com 等
```

建议只将该端口绑定到本地（`bind-address: 127.0.0.1`），以免把路由器变成局域网中的开放代理。

**2. 路由器的环境变量。** 这一步由 `setup-ssclash.sh` 完成 —— 安装时它会询问“是否设置路由器流量代理？”。若同意，则创建 `/etc/profile.d/ssclash-proxy.sh`：

```sh
if pidof clash >/dev/null 2>&1; then
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export no_proxy="127.0.0.1,localhost,::1"
fi
```

`pidof clash` 检查很重要：仅当内核正在运行时才启用代理。如果 Mihomo 未运行（崩溃，或重启后仍在启动中），这些变量不会被设置 —— 这样 `apk`/`curl` 就不会因试图连接一个失效端口而中断。该设置在新的 SSH 会话中生效（登录时读取该配置）。

若想一次性测试而不改动配置文件，可在当前会话中执行相同操作：

```
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
apk update
```

`/etc/profile.d/ssclash-proxy.sh` 文件会由卸载脚本自动删除。

## 卸载

移除脚本安装的所有内容。在路由器上：

```
wget https://raw.githubusercontent.com/lastik9/openwrt-ssclash/main/uninstall-ssclash.sh
sh uninstall-ssclash.sh
```

脚本总是会移除 SSClash 本身，并在最后**单独询问**是否连同系统级依赖一起移除。区别如下：

**普通卸载**（始终执行）移除专属于 SSClash 的内容：`luci-app-ssclash` 软件包、整个 `/opt/clash` 目录（Mihomo 内核和你的配置）以及 LuCI 菜单缓存。之后 SSClash 便从路由器上消失了 —— 99% 的情况下这已足够。

**彻底卸载**（若对依赖提示回答“是”）会额外移除 SSClash 为运行而安装的系统软件包：

- `kmod-tun` —— TUN 接口的内核模块；
- `kmod-nft-tproxy` —— 用于透明代理的 nftables 模块；
- `coreutils-base64` —— base64 工具。

问题在于这些是**共享**软件包：路由器上的其他组件也可能用到它们（OpenVPN/WireGuard 之类的 VPN、其他代理、各种脚本）。若在其他组件仍依赖它们时将其移除，那些组件就会出问题。因此脚本默认**保留**它们：占用空间微乎其微，也不妨碍任何东西。只有当路由器专用于 SSClash、且你确定再无他用时，才同意移除。`curl` 在任何情况下都不会被移除 —— 太多东西需要它。

## 架构对照

| OpenWrt (`apk --print-arch`)   | Mihomo 构建           |
| ------------------------------ | --------------------- |
| `aarch64_*`                    | `arm64`               |
| `x86_64`                       | `amd64-compatible`    |
| `i386_*`                       | `386`                 |
| `arm_cortex-a7/a9/a15…`        | `armv7`               |
| `arm_arm1176*`（Pi1/Zero）     | `armv6`               |
| `arm_mpcore/fa526/xscale…`     | `armv5`               |
| `mipsel_24kc`                  | `mipsle-softfloat`    |
| `mips_24kc`                    | `mips-softfloat`      |
| `mips64el_*` / `mips64_*`      | `mips64le` / `mips64` |
| `riscv64_*`                    | `riscv64`             |
| `loongarch64_*`                | `loong64`             |

## 致谢

本项目只是一个安装器。真正的工作都在上游完成：

- [zerolabnet/SSClash](https://github.com/zerolabnet/SSClash) —— luci-app-ssclash 面板
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) —— Clash.Meta 内核

所安装的组件归各自作者所有，并按其各自的许可证分发。本许可证（MIT）仅涵盖本脚本的代码。

## 许可证

[MIT](LICENSE) © 2026 lastik9
