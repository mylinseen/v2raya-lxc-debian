#!/bin/bash
set -euo pipefail

# ====== 提示用户输入配置 ======
echo "请提供以下配置选项："

# 外网接口名称，默认 eth0
read -p "请输入外网接口名称 (例如 eth0): " LAN_IF
LAN_IF=${LAN_IF:-"eth0"}

# 局域网网段，默认 192.168.1.0/24
read -p "请输入局域网网段 (例如 192.168.1.0/24): " LAN_NET
LAN_NET=${LAN_NET:-"192.168.1.0/24"}

# 主路由网关，默认 192.168.1.1
read -p "请输入主路由网关 (例如 192.168.1.1): " GATEWAY
GATEWAY=${GATEWAY:-"192.168.1.1"}

# sing-box 透明代理端口，默认 12345
read -p "请输入 sing-box 透明代理端口 (默认 12345): " SINGBOX_TPROXY_PORT
SINGBOX_TPROXY_PORT=${SINGBOX_TPROXY_PORT:-12345}

# DNS 端口，默认 5353
read -p "请输入 DNS 端口 (默认 5353): " SINGBOX_DNS_PORT
SINGBOX_DNS_PORT=${SINGBOX_DNS_PORT:-5353}

log() { echo -e "[\033[1;32mINFO\033[0m] $*"; }

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] 请以 root 运行此脚本"
    exit 1
  fi
}

install_deps() {
  log "安装依赖..."
  apt update
  apt install -y curl wget jq iproute2 iptables iptables-persistent gnupg2
}

install_v2ray_core() {
  if ! command -v v2ray &>/dev/null; then
    log "安装 v2ray core..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
  else
    log "v2ray 已存在，跳过"
  fi
}

install_v2raya() {
  if dpkg -l | grep -q v2raya; then
    log "v2rayA 已安装，跳过"
    return
  fi

  V=$(curl -sSfL "https://api.github.com/repos/v2rayA/v2rayA/releases" | jq -r '.[0].tag_name')
  V=${V#v}
  DEB="installer_debian_x64_${V}.deb"
  URL="https://github.com/v2rayA/v2rayA/releases/download/v${V}/${DEB}"

  log "下载 v2rayA: ${URL}"

  cd /tmp
  curl -L --fail -o "${DEB}" "${URL}"
  dpkg -i "${DEB}" || apt -f install -y
  rm -f "${DEB}"
}

install_singbox() {
  if command -v sing-box &>/dev/null; then
    log "sing-box 已存在"
    return
  fi

  ARCH="sing-box-linux-amd64"

  TAG=$(curl -sSfL https://api.github.com/repos/SagerNet/sing-box/releases | jq -r '.[0].tag_name')
  URL="https://github.com/SagerNet/sing-box/releases/download/${TAG}/${ARCH}.tar.gz"

  cd /tmp
  curl -L -o sb.tar.gz "$URL"
  tar xzf sb.tar.gz
  install -m 0755 sing-box /usr/local/bin/sing-box
}

apply_iptables() {

  LOCAL_IP=$(hostname -I | awk '{print $1}')

  mkdir -p /opt/v2raya-singbox
  cat >/opt/v2raya-singbox/iptables.sh <<EOF
#!/bin/bash
set -e

LAN_IF="${LAN_IF}"
LAN_NET="${LAN_NET}"
GATEWAY="${GATEWAY}"
LOCAL_IP="${LOCAL_IP}"
TPORT=${SINGBOX_TPROXY_PORT}
DNS_PORT=${SINGBOX_DNS_PORT}

iptables -t nat -F
iptables -t mangle -F
iptables -F

ip rule del fwmark 1 2>/dev/null || true
ip route flush table 100 2>/dev/null || true

ip rule add fwmark 1 lookup 100
ip route add default via ${GATEWAY} dev ${LAN_IF} table 100

iptables -t mangle -N DIVERT 2>/dev/null || true
iptables -t mangle -F DIVERT

iptables -t mangle -A PREROUTING -i ${LAN_IF} -p udp -j MARK --set-mark 1

iptables -t mangle -A PREROUTING -i ${LAN_IF} -d ${GATEWAY} -j RETURN
iptables -t mangle -A PREROUTING -i ${LAN_IF} -d 127.0.0.1/8 -j RETURN
iptables -t mangle -A PREROUTING -i ${LAN_IF} -s ${LOCAL_IP} -j RETURN
iptables -t mangle -A PREROUTING -i ${LAN_IF} -d ${LAN_NET} -j RETURN

iptables -t mangle -A PREROUTING -i ${LAN_IF} -p tcp -j TPROXY --on-port ${TPORT} --on-ip 0.0.0.0 --tproxy-mark 0x1/0x1
iptables -t mangle -A PREROUTING -i ${LAN_IF} -p udp -j TPROXY --on-port ${TPORT} --on-ip 0.0.0.0 --tproxy-mark 0x1/0x1

iptables -t nat -A PREROUTING -i ${LAN_IF} -p udp --dport 53 -j REDIRECT --to-ports ${DNS_PORT}
iptables -t nat -A PREROUTING -i ${LAN_IF} -p tcp --dport 53 -j REDIRECT --to-ports ${DNS_PORT}

iptables -t nat -A POSTROUTING -o ${LAN_IF} -j MASQUERADE
EOF

  chmod +x /opt/v2raya-singbox/iptables.sh
}

enable_v2raya() {
  # 确保 v2raya 服务启动并设置为自动启动
  log "启用 v2raya 服务..."
  systemctl enable v2raya
}

check_ip_forward() {
  # 确保 IP 转发已启用
  if ! sysctl net.ipv4.ip_forward | grep -q "net.ipv4.ip_forward = 1"; then
    log "启用 IP 转发..."
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
  fi
}

main() {
  check_root
  check_network_mode
  install_deps
  install_v2ray_core
  install_v2raya
  install_singbox
  apply_iptables
  enable_v2raya
  check_ip_forward

  log "安装完成！请手动执行:"
  echo "  bash /opt/v2raya-singbox/iptables.sh"
  echo "访问 v2rayA: http://${LOCAL_IP}:2017"
}

main
