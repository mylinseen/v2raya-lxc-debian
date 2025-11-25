# V2rayA + Sing-Box LXC 透明代理旁路由

本项目用于在 **Proxmox LXC（Debian 12）** 中快速部署 **V2rayA + Sing-box**，实现旁路由透明代理（支持 TProxy）。

项目地址：
**[https://github.com/mylinseen/v2raya-lxc-debian](https://github.com/mylinseen/v2raya-lxc-debian)**

---

## 🚀 一键安装（推荐）

在你的 LXC 容器中执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mylinseen/v2raya-lxc-debian/main/install.sh)
```

脚本将自动：

* 检测并安装依赖
* 安装 V2rayA
* 安装最新 Sing-box 核心
* 配置 TProxy、DNS、路由规则
* 自动生成 /etc/sing-box/config.json 示例
* 设置开机启动
* 一键应用 iptables 透明代理

---

## 🧩 功能说明

* **完整旁路由模式（支持 IPv4）**
* **TProxy 全局透明代理**（tcp + udp）
* **自建 DNS（5353）+ 分流规则**
* 自动放行局域网、保留国内直连
* 支持旁路由自身走代理 / 不走代理
* 支持 V2rayA 导入订阅并写入 sing-box

---

## 📌 使用前准备

### 1️⃣ PVE / LXC 容器配置

在 `/etc/pve/lxc/<ID>.conf` 添加：

```
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
lxc.cap.drop:
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

重启容器：

```
pct restart <ID>
```

### 2️⃣ 网络拓扑

示例：

| 设备           | 地址            |
| ------------ | ------------- |
| 主路由（爱快）      | 10.10.10.2    |
| 旁路由 LXC（本项目） | 10.10.10.20   |
| 局域网网段        | 10.10.10.0/24 |

使用代理的电脑 → 将 **网关改为旁路由 IP（例如 10.10.10.20）**
无需代理的电脑 → 保持使用主路由网关（10.10.10.2）

---

## 🛠 安装完成后使用说明

### 启动 / 停止服务

```bash
systemctl start v2raya
systemctl restart v2raya

systemctl start sing-box
systemctl restart sing-box
```

### 访问面板

V2rayA 管理面板：

```
http://<旁路由IP>:2017
```

默认不会占用公网端口。

---

## 🔧 Sing-box 配置路径

```
/etc/sing-box/config.json
```

你可直接将 V2rayA 的 outbound 写入该文件。

---

## ♻️ 透明代理规则（iptables）

脚本会自动生成：

```
/usr/local/singbox/tproxy-iptables.sh
```

应用方式：

```bash
bash /usr/local/singbox/tproxy-iptables.sh
```

---

## 🔄 卸载

```bash
systemctl disable --now v2raya
systemctl disable --now sing-box
rm -rf /etc/sing-box
rm -rf /usr/local/singbox
```

---

## 📬 反馈与建议

欢迎提交 issue 或 PR：

👉 [https://github.com/mylinseen/v2raya-lxc-debian](https://github.com/mylinseen/v2raya-lxc-debian)

如果你遇到任何安装失败、规则无效、DNS 不工作，请把日志贴出来，我会帮你排查。

---

感谢使用本项目！🎉
