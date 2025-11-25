#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 显示欢迎信息
show_welcome() {
    echo
    log_info "=========================================="
    log_info "   v2rayA LXC Debian 一键安装脚本"
    log_info "=========================================="
    echo
    log_info "此脚本将安装以下组件："
    log_info "  • V2Ray 核心"
    log_info "  • v2rayA 管理界面 (v2.2.7.4)"
    log_info "  • 透明代理支持"
    log_info "  • 系统服务配置"
    echo
    log_warn "请确保："
    log_warn "  • LXC 容器以特权模式运行"
    log_warn "  • 系统为 Debian 12"
    log_warn "  • 具有稳定的网络连接"
    echo
    
    read -p "是否继续安装？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    echo
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检查系统
check_system() {
    if ! grep -q "Debian GNU/Linux 12" /etc/os-release; then
        log_warn "检测到系统不是 Debian 12，兼容性可能存在问题"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    apt update
    apt upgrade -y
    apt install -y curl wget sudo nano git unzip iptables-persistent netfilter-persistent
}

# 安装 v2ray 核心
install_v2ray() {
    log_info "安装 v2ray 核心..."
    if ! command -v v2ray &> /dev/null; then
        # 使用官方脚本安装 V2Ray [citation:7]
        log_info "下载并运行 V2Ray 官方安装脚本..."
        bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
        systemctl enable v2ray
        systemctl start v2ray
        log_info "V2Ray 安装完成"
    else
        log_info "v2ray 已安装，跳过..."
    fi
}

# 安装 v2rayA (修正版本)
install_v2raya() {
    log_info "安装 v2rayA..."
    
    # 检查是否已安装
    if command -v v2raya &> /dev/null; then
        log_info "v2rayA 已安装，跳过..."
        return 0
    fi
    
    # 下载 v2rayA 预编译二进制文件
    cd /tmp
    V2RAYA_VERSION="2.2.7.4"
    
    log_info "下载 v2rayA 版本: ${V2RAYA_VERSION}"
    
    # 尝试多个可能的下载源
    MIRROR_URLS=(
        "https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya-linux-x64-v${V2RAYA_VERSION}.zip"
        "https://ghproxy.com/https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya-linux-x64-v${V2RAYA_VERSION}.zip"
        "https://download.fastgit.org/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya-linux-x64-v${V2RAYA_VERSION}.zip"
        "https://hub.gitmirror.com/https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya-linux-x64-v${V2RAYA_VERSION}.zip"
    )
    
    download_success=false
    for i in "${!MIRROR_URLS[@]}"; do
        url="${MIRROR_URLS[$i]}"
        log_info "尝试从镜像源 $((i+1)) 下载: $(echo $url | cut -d'/' -f3)"
        if wget --no-check-certificate --timeout=30 --tries=2 -O v2raya.zip "$url"; then
            download_success=true
            log_info "下载成功！"
            break
        else
            log_warn "镜像源 $((i+1)) 下载失败"
            rm -f v2raya.zip
        fi
    done
    
    if [ "$download_success" = false ]; then
        log_error "所有下载镜像均失败"
        log_info "请尝试以下解决方案："
        log_info "1. 检查网络连接和DNS设置"
        log_info "2. 手动下载 v2rayA 并放置在 /tmp/v2raya.zip"
        log_info "3. 访问 https://github.com/v2rayA/v2rayA/releases 手动下载最新版本"
        log_info "4. 使用代理服务器设置环境变量"
        exit 1
    fi
    
    # 解压并安装
    log_info "解压并安装 v2rayA..."
    if ! unzip -o v2raya.zip; then
        log_error "解压失败，文件可能已损坏"
        log_info "请手动下载 v2rayA 并重试"
        exit 1
    fi
    
    # 查找解压后的目录
    if [ -d "v2raya-linux-x64-v${V2RAYA_VERSION}" ]; then
        sudo mv "v2raya-linux-x64-v${V2RAYA_VERSION}/v2raya" /usr/local/bin/
    elif [ -f "v2raya" ]; then
        sudo mv v2raya /usr/local/bin/
    else
        log_error "在解压文件中找不到 v2raya 可执行文件"
        ls -la /tmp/
        exit 1
    fi
    
    sudo chmod +x /usr/local/bin/v2raya
    rm -rf v2raya.zip v2raya-*
    log_info "v2rayA 安装完成"
}

# 创建 v2rayA 配置目录
create_config_dir() {
    log_info "创建配置目录..."
    mkdir -p /etc/v2raya
}

# 配置系统服务
setup_service() {
    log_info "配置系统服务..."
    
    cat > /etc/systemd/system/v2raya.service << 'EOF'
[Unit]
Description=V2rayA Service
Documentation=https://github.com/v2rayA/v2raya
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2raya --lite --config /etc/v2raya
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable v2raya
    log_info "系统服务配置完成"
}

# 配置系统参数
setup_system() {
    log_info "配置系统参数..."
    
    # 启用 IP 转发 (对旁路由很关键)
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi
    
    # 应用配置
    sysctl -p
    
    # 创建透明代理配置脚本
    cat > /root/setup_transparent_proxy.sh << 'EOF'
#!/bin/bash
set -e

echo "配置透明代理规则..."

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# 清理现有规则
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# 设置默认策略
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 保存规则
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

echo "透明代理规则配置完成"
echo "请访问 v2rayA Web 界面完成后续配置：http://$(hostname -I | awk '{print $1}'):2017"
EOF

    chmod +x /root/setup_transparent_proxy.sh
    log_info "系统参数配置完成"
}

# 启动服务
start_services() {
    log_info "启动服务..."
    
    systemctl start v2raya
    
    # 检查服务状态
    sleep 3
    if systemctl is-active --quiet v2raya; then
        log_info "v2rayA 服务启动成功"
    else
        log_error "v2rayA 服务启动失败，查看日志..."
        sleep 2
        journalctl -u v2raya -n 15 --no-pager
        log_warn "服务启动失败，请检查日志获取详细信息"
    fi
}

# 显示安装结果
show_result() {
    local ip_address=$(hostname -I | awk '{print $1}')
    
    echo
    log_info "=========================================="
    log_info "           安装完成！"
    log_info "=========================================="
    echo
    log_info "🎉 v2rayA 已成功安装"
    echo
    log_info "📱 管理界面地址: http://${ip_address}:2017"
    echo
    log_info "📋 下一步操作："
    log_info "1. 访问上述地址完成 v2rayA 初始设置"
    log_info "2. 添加你的节点配置或订阅链接"
    log_info "3. 在设置中启用透明代理"
    log_info "4. 运行透明代理配置脚本: /root/setup_transparent_proxy.sh"
    echo
    log_info "🔧 服务管理命令："
    log_info "   systemctl start v2raya    # 启动"
    log_info "   systemctl stop v2raya     # 停止" 
    log_info "   systemctl status v2raya   # 状态"
    log_info "   journalctl -u v2raya -f   # 日志"
    echo
    log_info "💡 常见问题："
    log_info "- 如果无法访问管理界面，请检查防火墙设置"
    log_info "- 确保 LXC 容器以特权模式运行"
    log_info "- 透明代理需要配置正确的路由规则"
    echo
    log_info "⚠️  注意：安装完成后请运行透明代理配置脚本"
    log_info "   /root/setup_transparent_proxy.sh"
    echo
}

# 主函数
main() {
    show_welcome
    check_root
    check_system
    install_dependencies
    install_v2ray
    install_v2raya
    create_config_dir
    setup_service
    setup_system
    start_services
    show_result
    
    log_info "安装脚本执行完毕！"
}

# 执行主函数
main "$@"
