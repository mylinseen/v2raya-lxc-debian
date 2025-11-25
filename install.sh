#!/bin/bash
set -euo pipefail

# ====== 提示用户输入配置 ======
echo "请提供以下配置选项："

# 询问外网接口（网卡名）
read -p "请输入外网接口名称 (例如 eth0): " LAN_IF
LAN_IF=${LAN_IF:-"eth0"}  # 默认值 eth0

# 询问局域网网段
read -p "请输入局域网网段 (例如 10.10.10.0/24): " LAN_NET
LAN_NET=${LAN_NET:-"10.10.10.0/24"}  # 默认值 10.10.10.0/24

# 询问主路由网关
read -p "请输入主路由网关 (例如 10.10.10.2): " GATEWAY
GATEWAY=${GATEWAY:-"10.10.10.2"}  # 默认值 10.10.10.2

# 询问 sing-box 透明代理端口
read -p "请输入 sing-box 透明代理端口 (默认 12345): " SINGBOX_TPROXY_PORT
SINGBOX_TPROXY_PORT=${SINGBOX_TPROXY_PORT:-12345}  # 默认值 12345

# 询问 DNS 端口
read -p "请输入 DNS 端口 (默认 5353): " SINGBOX_DNS_PORT
SINGBOX_DNS_PORT=${SINGBOX_DNS_PORT:-5353}  # 默认值 5353

# ====== 函数定义 ======
log() { echo -e "[\033[1;32mINFO\033[0m] $*"; }
warn() { echo -e "[\033[1;33mWARN\033[0m] $*"; }
err() { echo -e "[\033[1;31mERROR\033[0m] $*"; }

check_root() {
  if [[ $EUID -ne 0 ]]; then
    err "请以 root 运行此脚本"
    exit 1
  fi
}

install_deps() {
  log "更新 apt 并安装依赖..."
  apt update
  apt install -y curl wget gnupg2 ca-certificates lsb-release apt-transport-https jq iproute2 iptables iptables-persistent
}

install_v2ray_core() {
  # 安装 v2ray core（兼容性保留）
  if ! command -v v2ray &>/dev/null; then
    log "正在安装 v2ray core..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    systemctl enable v2ray || true
    systemctl start v2ray || true
  else
    log "v2ray 已存在，跳过"
  fi
}

install_v2raya() {
  if dpkg -l | grep -q v2raya || command -v v2raya &>/dev/null; then
    log "v2rayA 已安装，跳过"
    return
  fi

  # 以 v2rayA Releases 的一个近似版本为例，脚本将尝试下载最新 release
  V=$(curl -sSfL "https://api.github.com/repos/v2rayA/v2rayA/releases" | jq -r '.[0].tag_name' 2>/dev/null || echo "v2.2.7.4")
  V=${V#v}
  DEB="installer_debian_x64_${V}.deb"
  URL="https://github.com/v2rayA/v2rayA/releases/download/v${V}/${DEB}"

  log "尝试从 ${URL} 下载 v2rayA .deb（若失败请手动检查网络或版本）"
  cd /tmp
  if curl -L --fail -o "${DEB}" "${URL}"; then
    dpkg -i "${DEB}" || apt -f install -y
    rm -f "${DEB}"
    systemctl enable v2raya || true
    systemctl start v2raya || true
    log "v2rayA 安装完成"
  else
    warn "自动下载 v2rayA 失败，请在 README 中按说明手动安装或提供可访问的 .deb 链接"
  fi
}

install_singbox() {
  if command -v sing-box &>/dev/null; then
    log "sing-box 已存在，跳过安装"
    return
  fi
  log "安装 sing-box..."

  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in
    amd64) ASSET="sing-box-linux-amd64" ;;
    arm64) ASSET="sing-box-linux-arm64" ;;
    *) ASSET="sing-box-linux-amd64" ;;
  esac

  # 获取最新 release 并下载 tar.gz
  API="https://api.github.com/repos/SagerNet/sing-box/releases"
  TAG=$(curl -sSfL "$API" | jq -r '.[0].tag_name' 2>/dev/null || echo '')
  if [[ -n "$TAG" ]]; then
    URL="https://github.com/SagerNet/sing-box/releases/download/${TAG}/${ASSET}.tar.gz"
  else
    URL="https://github.com/SagerNet/sing-box/releases/latest/download/${ASSET}.tar.gz"
  fi

  cd /tmp
  curl -L --fail -o singbox.tar.gz "$URL" || {
    warn "无法自动下载 sing-box，可能因网络原因。请手动安装 sing-box：https://github.com/SagerNet/sing-box"
    return
  }
  tar xzf singbox.tar.gz
  install -m 0755 sing-box /usr/local/bin/sing-box
  rm -f singbox.tar.gz sing-box

  # 简单 systemd 单元
  cat >/etc/systemd/system/singbox.service <<EOF
[Unit]
Description=sing-box
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/singbox/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable singbox || true
  log "sing-box 安装完成（请编辑 /etc/singbox/config.json 放入你的出站节点配置）"
}

apply_iptables() {
  mkdir -p /opt/v2raya-singbox
  cat >/opt/v2raya-singbox/iptables.sh <<EOF
#!/bin/bash
set -e
LAN_IF="${LAN_IF}"
LAN_NET="${LAN_NET}"
GATEWAY="${GATEWAY}"
TPORT=${SINGBOX_TPROXY_PORT}
DNS_PORT=${SINGBOX_DNS_PORT}

# 清理
iptables -t nat -F
iptables -t mangle -F
iptables -F
ip rule del fwmark 1 || true
ip route flush table 100 || true

# 创建一个专用路由表，走默认网关
ip rule add fwmark 1 lookup 100
ip route add default via ${GATEWAY} dev ${LAN_IF} table 100

# DIVERT 用于处理本地创建连接
iptables -t mangle -N DIVERT || true
iptables -t mangle -F DIVERT
iptables -t mangle -A PREROUTING -i ${LAN_IF} -p udp -j MARK --set-mark 1

# 标记本地进出的连接，避免循环
iptables -t mangle -A PREROUTING -i ${LAN_IF} -d ${GATEWAY} -j RETURN
iptables -t mangle -A PREROUTING -i ${LAN_IF} -d 127.0.0.1/8 -j RETURN
iptables -t mangle -A PREROUTING -i ${LAN_IF} -s ${LOCAL_IP} -j RETURN

# 不代理局域网内地址
iptables -t mangle -A PREROUTING -i ${LAN_IF} -d ${LAN_NET} -j RETURN

# TPROXY: 标记并交给路由表处理（udp/tcp）
iptables -t mangle -A PREROUTING -i ${LAN_IF} -p tcp -j TPROXY --on-port ${TPORT} --on-ip 0.0.0.0 --tproxy-mark 0x1/0x1
iptables -t mangle -A PREROUTING -i ${LAN_IF} -p udp -j TPROXY --on-port ${TPORT} --on-ip 0.0.0.0 --tproxy-mark 0x1/0x1

# 将本机经过的 DNS (53) 转到本地的 5353
iptables -t nat -A PREROUTING -i ${LAN_IF} -p udp --dport 53 -j REDIRECT --to-ports ${DNS_PORT}
iptables -t nat -A PREROUTING -i ${LAN_IF} -p tcp --dport 53 -j REDIRECT --to-ports ${DNS_PORT}

# NAT 出口
iptables -t nat -A POSTROUTING -o ${LAN_IF} -j MASQUERADE

