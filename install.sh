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
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    apt update
    apt install -y curl wget sudo dpkg
}

# 安装 v2ray 核心
install_v2ray() {
    log_info "安装 v2ray 核心..."
    if ! command -v v2ray &> /dev/null; then
        # 使用官方脚本安装 V2Ray [citation:1]
        bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
        systemctl enable v2ray
        systemctl start v2ray
        log_info "V2Ray 安装完成"
    else
        log_info "v2ray 已安装，跳过..."
    fi
}

# 安装 v2rayA (使用 .deb 包)
install_v2raya() {
    log_info "安装 v2rayA..."
    
    # 检查是否已安装
    if dpkg -l | grep -q v2raya; then
        log_info "v2rayA 已安装，跳过..."
        return 0
    fi
    
    # 下载并安装 .deb 包
    cd /tmp
    V2RAYA_VERSION="2.2.7.4"
    DEB_PACKAGE="v2raya_${V2RAYA_VERSION}_amd64.deb"
    DEB_URL="https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/${DEB_PACKAGE}"
    
    log_info "下载 v2rayA .deb 包: ${V2RAYA_VERSION}"
    
    if wget --timeout=30 --tries=3 -O "$DEB_PACKAGE" "$DEB_URL"; then
        log_info "下载成功，开始安装..."
        apt install -y "./$DEB_PACKAGE"
        rm -f "$DEB_PACKAGE"
        log_info "v2rayA 安装完成"
    else
        log_error "v2rayA 下载失败"
        log_info "请手动下载 .deb 包: $DEB_URL"
        log_info "然后运行: sudo dpkg -i /path/to/$DEB_PACKAGE"
        exit 1
    fi
}

# 配置系统参数
setup_system() {
    log_info "配置系统参数..."
    
    # 启用 IP 转发 (对旁路由很关键) [citation:2]
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi
    
    # 应用配置
    sysctl -p
    
    # 创建透明代理配置脚本 [citation:2]
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
    log_info "启动 v2rayA 服务..."
    systemctl enable v2raya
    systemctl start v2raya
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet v2raya; then
        log_info "v2rayA 服务启动成功"
    else
        log_error "v2rayA 服务启动失败，查看日志..."
        journalctl -u v2raya -n 10 --no-pager
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
    log_info "2. 添加节点配置或订阅链接"
    log_info "3. 在设置中启用透明代理"
    log_info "4. 运行透明代理配置脚本: /root/setup_transparent_proxy.sh"
    echo
}

# 主函数
main() {
    show_welcome
    check_root
    install_dependencies
    install_v2ray
    install_v2raya
    setup_system
    start_services
    show_result
    
    log_info "安装脚本执行完毕！"
}

# 执行主函数
main "$@"
