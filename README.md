# v2rayA LXC Debian 一键安装脚本

这个项目提供了在 Proxmox VE LXC 容器中安装 Debian 12 并配置 v2rayA 透明代理的一键安装脚本，适合用作旁路由。

## 特性

- ✅ 一键安装 v2rayA v2.2.7.4 和依赖组件
- ✅ 自动配置透明代理
- ✅ 支持 IPv4 转发
- ✅ 系统服务自启动
- ✅ 旁路由优化配置
- ✅ 多镜像源下载，提高成功率

## 前提条件

- Proxmox VE 环境下的 LXC 容器
- Debian 12 系统
- 容器需要以特权模式运行
- 确保网络连接正常

## 快速开始

### 一键安装（推荐）

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mylinseen/v2raya-lxc-debian/main/install.sh)
