#!/bin/bash

# 夜游远程网络工具
# 远程访问公司网络的安全解决方案
# 日期：2025-05-12

set -e

# 定义颜色
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # 无颜色

# 定义常量 - 隐藏真实目的
TOOL_VERSION=0.62.1
INSTALL_DIR=/usr/local/nightwalk
SERVICE_NAME=nightwalker
SERVICE_FILE=/etc/systemd/system/${SERVICE_NAME}.service
CONFIG_FILE=$INSTALL_DIR/config.yaml
REAL_BINARY=nightwalker

# 获取本机信息
get_local_ip() {
    local IP=$(hostname -I | awk '{print $1}')
    echo $IP
}

get_hostname() {
    hostname | tr -d '\n'
}

# 生成 10000-40000 之间的随机端口
get_random_port() {
    echo $(( RANDOM % 30001 + 10000 ))
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     夜游远程网络工具 - 安全访问       ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 安装/重新配置 夜游客户端"
    echo -e "${GREEN}2.${NC} 卸载 夜游客户端"
    echo -e "${GREEN}3.${NC} 管理网络通道"
    echo -e "${GREEN}4.${NC} 查看当前配置"
    echo -e "${GREEN}5.${NC} 查看使用说明"
    echo -e "${GREEN}6.${NC} 退出"
    echo -e "${BLUE}========================================${NC}"
    echo -e "当前状态: $(check_status)"
    echo -e "本机 IP: $(get_local_ip)"
    echo -e "本机主机名: $(get_hostname)"
    echo -e "${BLUE}========================================${NC}"
}

# 检查客户端状态
check_status() {
    if [ -f "$SERVICE_FILE" ]; then
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo -e "${GREEN}已安装且正在运行${NC}"
        else
            echo -e "${RED}已安装但未运行${NC}"
        fi
    else
        echo -e "${RED}未安装${NC}"
    fi
}

# 检查配置文件中的网络通道
list_tunnels() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装夜游客户端。${NC}"
        return 1
    fi

    echo -e "${BLUE}当前配置的网络通道:${NC}"
    echo -e "${YELLOW}================================${NC}"
    
    # 使用yq工具来解析YAML（需要安装yq）
    # 检查是否安装了yq
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}未找到yq工具，无法解析配置。请安装yq: sudo apt install yq${NC}"
        return 1
    fi
    
    # 提取服务器信息
    SERVER_ADDR=$(yq eval '.common.server_addr' "$CONFIG_FILE")
    SERVER_PORT=$(yq eval '.common.server_port' "$CONFIG_FILE")
    
    echo -e "${GREEN}连接服务器:${NC} $SERVER_ADDR:$SERVER_PORT"
    echo -e "${YELLOW}================================${NC}"
    
    # 获取所有代理（排除common部分）
    PROXIES=$(yq eval 'keys | .[] | select(. != "common")' "$CONFIG_FILE")
    
    if [ -z "$PROXIES" ]; then
        echo -e "${RED}没有配置任何网络通道。${NC}"
        return 1
    fi
    
    section_count=0
    for proxy in $PROXIES; do
        echo -e "${GREEN}$proxy${NC}"
        local_port=$(yq eval ".$proxy.local_port" "$CONFIG_FILE")
        remote_port=$(yq eval ".$proxy.remote_port" "$CONFIG_FILE")
        echo -e "  本地端口: ${local_port}"
        echo -e "  远程端口: ${remote_port}"
        echo -e "  远程访问地址: ${SERVER_ADDR}:${remote_port}"
        echo -e "${YELLOW}--------------------------------${NC}"
        section_count=$((section_count+1))
    done
    
    if [ $section_count -eq 0 ]; then
        echo -e "${RED}没有配置任何网络通道。${NC}"
        return 1
    fi
    
    return 0
}

# 下载客户端
download_with_proxy() {
    echo -e "${BLUE}正在下载夜游工具 ${TOOL_VERSION}...${NC}"
    cd /tmp
    
    # 隐藏真实下载URL
    REAL_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${TOOL_VERSION}/frp_${TOOL_VERSION}_linux_amd64.tar.gz"
    DOWNLOAD_FILENAME="nightwalk_${TOOL_VERSION}_linux.tar.gz"
    
    # 询问是否使用代理
    read -p "是否使用代理下载？(y/n): " use_proxy
    if [[ "$use_proxy" == "y" || "$use_proxy" == "Y" ]]; then
        read -p "请输入代理地址和端口 (格式: ip:port): " proxy_address
        
        echo -e "${YELLOW}使用代理下载: ${proxy_address}${NC}"
        curl -L -o "$DOWNLOAD_FILENAME" --proxy http://${proxy_address} "$REAL_DOWNLOAD_URL" || {
            echo -e "${RED}代理下载失败，请检查代理设置或尝试直接下载。${NC}"
            return 1
        }
    else
        echo -e "${YELLOW}尝试直接下载...${NC}"
        curl -L -o "$DOWNLOAD_FILENAME" "$REAL_DOWNLOAD_URL" || {
            echo -e "${RED}直接下载失败，建议使用代理。${NC}"
            return 1
        }
    fi
    
    # 检查文件是否成功下载和有效
    if [ ! -f "$DOWNLOAD_FILENAME" ] || [ ! -s "$DOWNLOAD_FILENAME" ]; then
        echo -e "${RED}下载的文件不存在或为空！${NC}"
        return 1
    fi
    
    return 0
}

# 安装客户端
install_client() {
    # 如果已安装，询问是否重新安装
    if [ -f "$SERVICE_FILE" ]; then
        read -p "夜游客户端已安装，是否重新配置？(y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "取消配置操作。"
            return
        fi
    fi

    # 创建安装目录
    mkdir -p $INSTALL_DIR
    
    # 安装依赖
    echo -e "${BLUE}检查是否安装了必要的依赖...${NC}"
    if ! command -v yq &> /dev/null; then
        echo -e "${YELLOW}未找到yq工具，尝试安装...${NC}"
        apt-get update && apt-get install -y yq || {
            echo -e "${RED}无法安装yq，请手动安装后重试。${NC}"
            return 1
        }
    fi
    
    # 如果是新安装，则下载并安装
    if [ ! -f "$INSTALL_DIR/$REAL_BINARY" ]; then
        # 使用下载函数下载
        if ! download_with_proxy; then
            echo -e "${RED}下载失败，请检查网络连接或代理设置。${NC}"
            return 1
        fi
        
        echo -e "${BLUE}正在安装夜游客户端...${NC}"
        # 解压原始文件，并重命名为我们的伪装名称
        DOWNLOAD_FILENAME="nightwalk_${TOOL_VERSION}_linux.tar.gz"
        TEMP_DIR="nightwalk_temp"
        mkdir -p "/tmp/$TEMP_DIR"
        
        tar -zxf "/tmp/$DOWNLOAD_FILENAME" -C "/tmp/$TEMP_DIR" || {
            echo -e "${RED}解压失败，可能下载的文件不完整或已损坏。${NC}"
            rm -rf "/tmp/$TEMP_DIR"
            return 1
        }
        
        # 查找真实的二进制文件并复制为我们的伪装名称
        find "/tmp/$TEMP_DIR" -name "frpc" -exec cp {} "$INSTALL_DIR/$REAL_BINARY" \; || {
            echo -e "${RED}复制文件失败。${NC}"
            rm -rf "/tmp/$TEMP_DIR"
            return 1
        }
        
        # 确保可执行
        chmod +x "$INSTALL_DIR/$REAL_BINARY"
        
        # 清理临时文件
        rm -f "/tmp/$DOWNLOAD_FILENAME"
        rm -rf "/tmp/$TEMP_DIR"
    fi

    # 获取本机主机名
    HOSTNAME=$(get_hostname)

    # 获取服务器基本配置
    read -p "请输入服务端地址 (IP或域名): " VPS_IP
    read -p "请输入服务端口 [默认7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -p "请输入连接密钥 [默认随机生成]: " TOKEN
    TOKEN=${TOKEN:-$(openssl rand -hex 16)}
    
    # 创建基本配置文件（YAML格式）
    cat > $CONFIG_FILE <<EOF
common:
  server_addr: ${VPS_IP}
  server_port: ${SERVER_PORT}
  token: ${TOKEN}
EOF

    # 配置 SOCKS5 代理通道
    read -p "是否配置 安全通道 1？(y/n) [推荐开启，用于远程访问公司网络]: " setup_socks
    if [[ "$setup_socks" == "y" || "$setup_socks" == "Y" ]]; then
        read -p "请输入本地端口 [默认10811]: " SOCKS_LOCAL_PORT
        SOCKS_LOCAL_PORT=${SOCKS_LOCAL_PORT:-10811}
        SOCKS_REMOTE_PORT=$(get_random_port)
        cat >> $CONFIG_FILE <<EOF
private-${HOSTNAME}:
  type: tcp
  local_ip: 127.0.0.1
  local_port: ${SOCKS_LOCAL_PORT}
  remote_port: ${SOCKS_REMOTE_PORT}
EOF
    fi
    
    # 配置 HTTP 代理通道
    read -p "是否配置 安全通道 2？(y/n) [用于特殊访问场景]: " setup_http
    if [[ "$setup_http" == "y" || "$setup_http" == "Y" ]]; then
        read -p "请输入本地端口 [默认8080]: " HTTP_LOCAL_PORT
        HTTP_LOCAL_PORT=${HTTP_LOCAL_PORT:-8080}
        HTTP_REMOTE_PORT=$(get_random_port)
        cat >> $CONFIG_FILE <<EOF
public-${HOSTNAME}:
  type: tcp
  local_ip: 127.0.0.1
  local_port: ${HTTP_LOCAL_PORT}
  remote_port: ${HTTP_REMOTE_PORT}
EOF
    fi
    
    # 配置 SSH 通道
    read -p "是否配置 远程管理通道？(y/n): " setup_ssh
    if [[ "$setup_ssh" == "y" || "$setup_ssh" == "Y" ]]; then
        read -p "请输入本地端口 [默认22]: " SSH_LOCAL_PORT
        SSH_LOCAL_PORT=${SSH_LOCAL_PORT:-22}
        SSH_REMOTE_PORT=$(get_random_port)
        
        cat >> $CONFIG_FILE <<EOF
shell-${HOSTNAME}:
  type: tcp
  local_ip: 127.0.0.1
  local_port: ${SSH_LOCAL_PORT}
  remote_port: ${SSH_REMOTE_PORT}
EOF
    fi
    
    # 配置 Web 通道
    read -p "是否配置 Web 访问通道？(y/n): " setup_web
    if [[ "$setup_web" == "y" || "$setup_web" == "Y" ]]; then
        read -p "请输入本地端口 [默认80]: " WEB_LOCAL_PORT
        WEB_LOCAL_PORT=${WEB_LOCAL_PORT:-80}
        WEB_REMOTE_PORT=$(get_random_port)
        
        cat >> $CONFIG_FILE <<EOF
webservice-${HOSTNAME}:
  type: tcp
  local_ip: 127.0.0.1
  local_port: ${WEB_LOCAL_PORT}
  remote_port: ${WEB_REMOTE_PORT}
EOF
    fi
    
    # 询问是否添加自定义通道
    read -p "是否添加自定义通道？(y/n): " setup_custom
    if [[ "$setup_custom" == "y" || "$setup_custom" == "Y" ]]; then
        add_tunnel
    fi

    # 创建系统服务
    echo -e "${BLUE}正在创建系统服务...${NC}"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Night Walk Network Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${REAL_BINARY} -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${BLUE}正在启动网络服务...${NC}"
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME

    echo -e "${GREEN}✅ 夜游客户端安装完成！${NC}"
    echo
    view_config
    echo
    echo -e "${YELLOW}提示：运行选项 5 查看如何从外部连接到公司网络${NC}"
}

# 添加新的网络通道
add_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装夜游客户端。${NC}"
        return
    fi
    
    # 获取本机主机名
    HOSTNAME=$(get_hostname)
    
    read -p "请输入通道名称 (英文字母，如 app, game 等): " TUNNEL_NAME
    read -p "请输入本地端口: " LOCAL_PORT
    read -p "请输入远程端口 [留空自动生成]: " REMOTE_PORT
    
    # 如果远程端口为空，则随机生成
    if [ -z "$REMOTE_PORT" ]; then
        REMOTE_PORT=$(get_random_port)
    fi
    
    # 添加到配置文件，加入主机名（YAML格式）
    cat >> $CONFIG_FILE <<EOF
${TUNNEL_NAME}-${HOSTNAME}:
  type: tcp
  local_ip: 127.0.0.1
  local_port: ${LOCAL_PORT}
  remote_port: ${REMOTE_PORT}
EOF

    echo -e "${GREEN}✅ 已添加新的网络通道: ${TUNNEL_NAME}-${HOSTNAME}${NC}"
    
    # 如果已安装并运行，则重启服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}✅ 网络服务已重启${NC}"
    fi
}

# 删除网络通道
remove_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装夜游客户端。${NC}"
        return
    fi
    
    # 列出现有通道
    if ! list_tunnels; then
        return
    fi
    
    echo
    read -p "请输入要删除的通道名称: " TUNNEL_NAME
    
    # 检查通道是否存在
    if ! yq eval ".$TUNNEL_NAME" "$CONFIG_FILE" &>/dev/null; then
        echo -e "${RED}错误: 通道 '${TUNNEL_NAME}' 不存在。${NC}"
        return
    fi
    
    # 使用yq删除指定的通道部分
    yq eval "del(.$TUNNEL_NAME)" -i "$CONFIG_FILE"
    
    echo -e "${GREEN}✅ 已删除网络通道: ${TUNNEL_NAME}${NC}"
    
    # 如果已安装并运行，则重启服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}✅ 网络服务已重启${NC}"
    fi
}

# 查看当前配置
view_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装夜游客户端。${NC}"
        return
    fi
    
    echo -e "${BLUE}夜游客户端配置:${NC}"
    
    # 列出所有网络通道
    list_tunnels
}

# 显示使用说明
show_usage() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}      夜游远程网络工具使用说明         ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}【基本概念】${NC}"
    echo -e "夜游客户端安装在公司电脑上，服务端安装在有公网 IP 的服务器上。"
    echo -e "通过此安全通道，您可以在外部通过服务器访问公司内网资源。"
    echo
    echo -e "${GREEN}【远程访问公司网络】${NC}"
    echo -e "1. 确保您的夜游客户端已配置并启动安全通道"
    echo -e "2. 在您的手机或其他设备上设置相应的代理:"
    
    # 如果找到 SOCKS5 配置，显示详细信息
    if [ -f "$CONFIG_FILE" ] && yq eval '.["private-'$(get_hostname)'"]' "$CONFIG_FILE" &>/dev/null; then
        SERVER_ADDR=$(yq eval '.common.server_addr' "$CONFIG_FILE")
        SOCKS_REMOTE_PORT=$(yq eval '.["private-'$(get_hostname)'"].remote_port' "$CONFIG_FILE")
        echo -e "   - 安全通道 1 (SOCKS5):"
        echo -e "     服务器: ${SERVER_ADDR}"
        echo -e "     端口: ${SOCKS_REMOTE_PORT}"
    else
        echo -e "   - 安全通道 1: 未配置"
    fi
    
    # 如果找到 HTTP 配置，显示详细信息
    if [ -f "$CONFIG_FILE" ] && yq eval '.["public-'$(get_hostname)'"]' "$CONFIG_FILE" &>/dev/null; then
        SERVER_ADDR=$(yq eval '.common.server_addr' "$CONFIG_FILE")
        HTTP_REMOTE_PORT=$(yq eval '.["public-'$(get_hostname)'"].remote_port' "$CONFIG_FILE")
        echo -e "   - 安全通道 2 (HTTP):"
        echo -e "     服务器: ${SERVER_ADDR}"
        echo -e "     端口: ${HTTP_REMOTE_PORT}"
    else
        echo -e "   - 安全通道 2: 未配置"
    fi
    
    echo
    echo -e "${GREEN}【在手机上设置代理的方法】${NC}"
    echo -e "Android 系统:"
    echo -e "  1. 打开设置 → 无线和网络 → WLAN"
    echo -e "  2. 长按当前连接的网络 → 修改网络 → 显示高级选项"
    echo -e "  3. 代理设置选择"手动"，输入服务器 IP 和端口"
    echo
    echo -e "iOS 系统:"
    echo -e "  1. 打开设置 → Wi-Fi"
    echo -e "  2. 点击当前连接的网络右侧的 (i) 图标"
    echo -e "  3. 滚动到底部，点击"配置代理"→ 手动"
    echo -e "  4. 输入服务器 IP 和端口"
    echo
    echo -e "或者使用专用的网络优化APP (如 Shadowsocks, V2rayNG 等)，设置对应代理。"
    echo
    echo -e "${GREEN}【远程管理连接】${NC}"
    
    # 如果找到 SSH 配置，显示详细信息
    if [ -f "$CONFIG_FILE" ] && yq eval '.["shell-'$(get_hostname)'"]' "$CONFIG_FILE" &>/dev/null; then
        SERVER_ADDR=$(yq eval '.common.server_addr' "$CONFIG_FILE")
        SSH_REMOTE_PORT=$(yq eval '.["shell-'$(get_hostname)'"].remote_port' "$CONFIG_FILE")
        echo -e "使用以下命令连接到您的公司电脑:"
        echo -e "  ssh -p ${SSH_REMOTE_PORT} 用户名@${SERVER_ADDR}"
    else
        echo -e "如果您配置了远程管理通道，使用以下命令连接到您的公司电脑:"
        echo -e "  ssh -p <远程端口> 用户名@<您的服务器地址>"
    fi
    
    echo
    echo -e "${GREEN}【注意事项】${NC}"
    echo -e "1. 确保公司电脑始终开机并运行夜游客户端"
    echo -e "2. 如果公司网络有防火墙，确保不会阻止夜游服务连接"
    echo -e "3. 定期检查夜游客户端状态，确保服务正常运行"
    echo -e "4. 建议为连接设置强密钥保护，避免未授权访问"
    echo -e "${BLUE}========================================${NC}"
}

# 卸载客户端
uninstall_client() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${RED}夜游客户端未安装，无需卸载。${NC}"
        return
    fi

    echo -e "${BLUE}正在停止网络服务...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || echo "服务已经停止"
    systemctl disable $SERVICE_NAME 2>/dev/null || echo "服务已经禁用"

    echo -e "${BLUE}正在删除夜游文件...${NC}"
    rm -f $SERVICE_FILE
    rm -rf $INSTALL_DIR

    echo -e "${BLUE}正在重新加载 systemd...${NC}"
    systemctl daemon-reload

    echo -e "${GREEN}✅ 夜游客户端已完全卸载。${NC}"
}

# 通道管理功能
manage_ports() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装夜游客户端。${NC}"
        read -p "按回车键继续..."
        return
    fi

    while true; do
        show_port_menu
        read -p "请输入选项 [1-3]: " port_choice
        case $port_choice in
            1)
                add_tunnel
                read -p "按回车键继续..."
                ;;
            2)
                remove_tunnel
                read -p "按回车键继续..."
                ;;
            3)
                return  # 返回主菜单
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择。${NC}"
                sleep 1
                ;;
        esac
    done
}

# 显示通道管理菜单
show_port_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        夜游网络通道管理               ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 添加新的网络通道"
    echo -e "${GREEN}2.${NC} 删除网络通道"
    echo -e "${GREEN}3.${NC} 返回主菜单"
    echo -e "${BLUE}========================================${NC}"
}

# 主函数
main() {
    while true; do
        show_menu
        read -p "请输入选项 [1-6]: " choice
        case $choice in
            1)
                install_client
                read -p "按回车键继续..."
                ;;
            2)
                uninstall_client
                read -p "按回车键继续..."
                ;;
            3)
                manage_ports
                ;;
            4)
                view_config
                read -p "按回车键继续..."
                ;;
            5)
                show_usage
                read -p "按回车键继续..."
                ;;
            6)
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择。${NC}"
                sleep 1
                ;;
        esac
    done
}

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 此脚本需要 root 权限运行。${NC}"
    echo -e "请使用 sudo 重新运行此脚本。"
    exit 1
fi

# 运行主函数
main
