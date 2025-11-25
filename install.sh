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
        bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
        systemctl enable v2ray
        systemctl start v2ray
        log_info "V2Ray 安装完成"
    else
        log_info "v2ray 已安装，跳过..."
    fi
}

# 安装 v2rayA (使用正确的 .deb 包地址)
install_v2raya() {
    log_info "安装 v2rayA..."
    
    # 检查是否已安装
    if command -v v2raya &> /dev/null || dpkg -l | grep -q v2raya; then
        log_info "v2rayA 已安装，跳过..."
        return 0
    fi
    
    cd /tmp
    V2RAYA_VERSION="2.2.7.4"
    
    # 使用您提供的正确 deb 包地址
    DEB_PACKAGE="installer_debian_x64_${V2RAYA_VERSION}.deb"
    DOWNLOAD_URL="https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/${DEB_PACKAGE}"
    
    log_info "下载 v2rayA .deb 包: ${DEB_PACKAGE}"
    
    # 检查URL是否可访问
    log_info "检查下载链接可用性..."
    if curl --output /dev/null --silent --head --fail "$DOWNLOAD_URL"; then
        log_info "下载链接有效，开始下载..."
    else
        log_error "下载链接无效: $DOWNLOAD_URL"
        log_info "请检查网络连接或版本号"
        exit 1
    fi
    
    if wget --timeout=30 --tries=3 -O "$DEB_PACKAGE" "$DOWNLOAD_URL"; then
        log_info "下载成功，开始安装..."
        dpkg -i "$DEB_PACKAGE" || (apt install -f -y && log_info "依赖问题已解决")
        rm -f "$DEB_PACKAGE"
        log_info "v2rayA 安装完成"
    else
        log_error "v2rayA 下载失败"
        log_info "请检查以下可能的问题："
        log_info "1. 网络连接是否正常"
        log_info "2. 版本号是否正确"
        log_info "3. GitHub 访问是否顺畅"
        log_info "手动下载地址: $DOWNLOAD_URL"
        exit 1
    fi
}

# 配置系统参数
setup_system() {
    log_info "配置系统参数..."
    
    # 启用 IP 转发
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
    log_info "启动 v2rayA 服务..."
    
    systemctl enable v2raya
    systemctl start v2raya
    
    # 检查服务状态
    sleep 3
    if systemctl is-active --quiet v2raya; then
        log_info "v2rayA 服务启动成功"
    else
        log_warn "v2rayA 服务启动遇到问题，查看日志..."
        sleep 2
        journalctl -u v2raya -n 10 --no-pager
        log_info "请检查上述日志并解决问题后，手动运行: systemctl start v2raya"
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
    
    log_info "一键安装脚本执行完毕！"
}

# 执行主函数
main "$@"
