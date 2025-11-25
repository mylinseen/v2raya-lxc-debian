# v2rayA LXC Debian 一键安装脚本

这个项目提供了在 Proxmox VE LXC 容器中安装 Debian 12 并配置 v2rayA 透明代理的一键安装脚本，适合用作旁路由。

## 特性

- ✅ 一键安装 v2rayA v2.2.7.4 和 V2Ray 核心
- ✅ 使用官方 .deb 包安装，稳定可靠
- ✅ 自动配置透明代理
- ✅ 支持 IPv4 转发
- ✅ 系统服务自启动
- ✅ 旁路由优化配置

## 快速开始

### 一键安装（推荐）

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mylinseen/v2raya-lxc-debian/main/install.sh)

