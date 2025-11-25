#!/bin/bash
set -e

# ================================
# 颜色定义
# ================================
green(){ echo -e "\e[32m$1\e[0m"; }
red(){ echo -e "\e[31m$1\e[0m"; }

# ================================
# 检查容器网络配置
# ================================
check_network_mode() {
    if ip link show eth0 >/dev/null 2>&1; then
        green "检测到 eth0，继续安装..."
    else
        red "未找到 eth0，请检查你的 LXC 网络设置！"
        exit 1
    fi
}
check_network_mode

# ================================
# 用户输入
# ================================
read -rp "请输入外网接口名称 (例如 eth0): " WAN_IF
read -rp "请输入局域网网段 (例如 10.10.10.0/24): " LAN_NET
read -rp "请输入主路由网关 (例如 10.10.10.2): " LAN_GW
read -rp "请输入 sing-box 透明代理端口 (默认 12345): " SB_PORT
read -rp "请输入 DNS 端口 (默认 5353): " DNS_PORT

# 设置默认值
SB_PORT=${SB_PORT:-12345}
DNS_PORT=${DNS_PORT:-5353}

green "
=== 配置确认 ===
外网接口：$WAN_IF
局域网：$LAN_NET
主路由网关：$LAN_GW
透明代理端口：$SB_PORT
DNS 端口：$DNS_PORT
================
"

sleep 1

# ================================
# 安装依赖
# ================================
apt update
apt install -y curl wget sudo iptables iproute2 ca-certificates nano

# ================================
# 安装 V2RayA
# ================================
green "安装 V2RayA..."

bash <(curl -Ls https://mirrors.v2raya.org/go.sh)

# 修复 systemd 服务
cat > /etc/systemd/system/v2raya.service <<EOF
[Unit]
Description=V2RayA Panel
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/v2raya
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable v2raya
systemctl restart v2raya

green "V2RayA 安装完成，访问端口：2017"

# ================================
# 安装 sing-box
# ================================
green "安装 sing-box..."

bash <(curl -fsSL https://sing-box.app/install.sh)

mkdir -p /etc/sing-box

# 生成透明代理配置
cat > /etc/sing-box/config.json <<EOF
{
  "inbounds": [
    {
      "type": "tproxy",
      "listen": "::",
      "listen_port": $SB_PORT,
      "network": "tcp,udp"
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF

systemctl enable sing-box
systemctl restart sing-box

# ================================
# TPROXY 防火墙规则配置
# ================================
green "设置 TPROXY 防火墙规则..."

cat > /etc/iptables-tproxy.sh <<EOF
#!/bin/bash

# 清理旧规则
iptables -t mangle -F
iptables -t mangle -X V2RAY 2>/dev/null || true
iptables -t mangle -N V2RAY

# 对局域网入站流量进行 TPROXY
iptables -t mangle -A PREROUTING -s $LAN_NET -j V2RAY
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port $SB_PORT --tproxy-mark 1
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port $SB_PORT --tproxy-mark 1

# 路由表
ip rule add fwmark 1 lookup 100 || true
ip route add local 0.0.0.0/0 dev lo table 100 || true
EOF

chmod +x /etc/iptables-tproxy.sh
bash /etc/iptables-tproxy.sh

# systemd 服务
cat > /etc/systemd/system/tproxy.service <<EOF
[Unit]
Description=TPROXY Firewall Rules
After=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables-tproxy.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tproxy
systemctl start tproxy

# ================================
# DNS 设置
# ================================
green "配置 DNS 重定向..."

cat > /etc/dnsmasq.d/custom-dns.conf <<EOF
port=$DNS_PORT
server=8.8.8.8
server=223.5.5.5
cache-size=1000
EOF

apt install -y dnsmasq
systemctl enable dnsmasq
systemctl restart dnsmasq

green "===================================="
green "透明代理 + V2RayA + sing-box 安装完成！"
green "===================================="

echo "
下一步：
1️⃣ 浏览器打开 V2RayA 面板： http://你的IP:2017  
2️⃣ 在 V2RayA 选择“透明代理模式（TProxy）”
3️⃣ 设置好节点即可工作
"
