#!/usr/bin/env bash
# 云端一键安装入口（不再使用 apt.v2raya.org）：
# bash <(curl -Ls https://raw.githubusercontent.com/mylinseen/mylinseen-v2raya-lxc-installer/main/install.sh)

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 身份运行本脚本（sudo -i 后再执行）。"
  exit 1
fi

if ! grep -qi "debian" /etc/os-release || ! grep -qi "12" /etc/os-release; then
  echo "本脚本仅适用于 Debian 12。"
  exit 1
fi

if command -v systemd-detect-virt >/dev/null 2>&1; then
  if systemd-detect-virt | grep -qi "lxc"; then
    echo "检测到 LXC 容器环境，继续安装……"
  else
    echo "警告：未检测到 LXC，依然继续执行。"
  fi
fi

export DEBIAN_FRONTEND=noninteractive

echo "[Step] 更新系统并安装基础依赖..."
apt-get update
apt-get upgrade -y
apt-get install -y ca-certificates curl wget gnupg lsb-release iptables iproute2 sudo vim

echo "[Step] 启用 IPv4 转发..."
SYSCTL_CONF="/etc/sysctl.d/99-v2raya-ip-forward.conf"
cat > "${SYSCTL_CONF}" <<EOF
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null 2>&1 || true

echo "[Step] 使用 v2rayA 官方安装脚本安装（带 xray 内核）..."

# 官方 fallback 安装脚本仓库：v2rayA/v2rayA-installer
# 这里用 hubmirror / raw + curl -Ls 的方式执行，并带上 --with-xray 参数
# 文档中给的是 wget 版本，这里改成 curl 版本方便统一。[web:63]
bash <(curl -Ls https://hubmirror.v2raya.org/v2rayA/v2rayA-installer/raw/main/installer.sh) --with-xray

echo "[Step] 设置 v2raya 服务开机自启..."
systemctl daemon-reload || true
systemctl enable v2raya || true
systemctl start v2raya || true

sleep 2
if systemctl is-active --quiet v2raya; then
  echo "[OK] v2rayA 已成功启动。"
else
  echo "[WARN] v2rayA 未成功启动，请使用 'journalctl -u v2raya' 查看日志排错。"
fi

echo
echo "=================================================="
echo "安装完成：v2rayA + xray (Debian 12 LXC / IPv4)"
echo
echo "1. 在浏览器中访问： http://<容器IP>:2017"
echo "2. 在 v2rayA Web 面板中导入/添加你的节点。"
echo "3. 在设置中开启「全局透明代理 / TProxy」（IPv4）。"
echo "4. 如需确认：systemctl status v2raya"
echo "=================================================="
