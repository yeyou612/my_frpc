#!/bin/bash

# FRP 客户端安装/卸载/管理脚本
# 专为远程访问公司网络设计
# 日期：2025-05-07

set -e

# 定义颜色
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # 无颜色

# 定义常量
FRP_VERSION=0.62.1
INSTALL_DIR=/usr/local/frp
SERVICE_FILE=/etc/systemd/system/frpc.service
CONFIG_FILE=$INSTALL_DIR/frpc.ini

# 获取本机 IP
get_local_ip() {
    local IP=$(hostname -I | awk '{print $1}')
    echo $IP
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     FRP 远程访问客户端管理脚本        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 安装/重新配置 FRP 客户端"
    echo -e "${GREEN}2.${NC} 卸载 FRP 客户端"
    echo -e "${GREEN}3.${NC} 管理端口穿透"
    echo -e "${GREEN}4.${NC} 查看当前配置"
    echo -e "${GREEN}5.${NC} 查看使用说明"
    echo -e "${GREEN}6.${NC} 退出"
    echo -e "${BLUE}========================================${NC}"
    echo -e "当前状态: $(check_status)"
    echo -e "本机 IP: $(get_local_ip)"
    echo -e "${BLUE}========================================${NC}"
}

# 显示端口管理菜单
show_port_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        FRP 端口穿透管理               ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 添加新的端口穿透"
    echo -e "${GREEN}2.${NC} 删除端口穿透"
    echo -e "${GREEN}3.${NC} 返回主菜单"
    echo -e "${BLUE}========================================${NC}"
}

# 检查 FRP 客户端状态
check_status() {
    if [ -f "$SERVICE_FILE" ]; then
        if systemctl is-active --quiet frpc; then
            echo -e "${GREEN}已安装且正在运行${NC}"
        else
            echo -e "${RED}已安装但未运行${NC}"
        fi
    else
        echo -e "${RED}未安装${NC}"
    fi
}

# 检查配置文件中的端口穿透
list_tunnels() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装 FRP 客户端。${NC}"
        return 1
    fi

    echo -e "${BLUE}当前配置的端口穿透:${NC}"
    echo -e "${YELLOW}================================${NC}"
    
    # 提取服务器信息
    SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    SERVER_PORT=$(grep "server_port" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    
    echo -e "${GREEN}FRP 服务器:${NC} $SERVER_ADDR:$SERVER_PORT"
    echo -e "${YELLOW}================================${NC}"
    
    # 跳过 [common] 部分
    skip_common=true
    section_count=0
    
    while IFS= read -r line; do
        if [[ $line == \[*] ]]; then
            if [[ $line != "[common]" ]]; then
                skip_common=false
                section_name=$(echo "$line" | tr -d '[]')
                echo -e "${GREEN}$section_name${NC}"
                section_count=$((section_count+1))
            else
                skip_common=true
            fi
        elif [ "$skip_common" = false ]; then
            if [[ $line == local_port* ]]; then
                local_port=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
                echo -e "  本地端口: ${local_port}"
            elif [[ $line == remote_port* ]]; then
                remote_port=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
                echo -e "  远程端口: ${remote_port}"
                echo -e "  远程访问地址: ${SERVER_ADDR}:${remote_port}"
                echo -e "${YELLOW}--------------------------------${NC}"
            fi
        fi
    done < "$CONFIG_FILE"
    
    if [ $section_count -eq 0 ]; then
        echo -e "${RED}没有配置任何端口穿透。${NC}"
        return 1
    fi
    
    return 0
}

# 安装 FRP 客户端
install_frpc() {
    # 如果已安装，询问是否重新安装
    if [ -f "$SERVICE_FILE" ]; then
        read -p "FRP 客户端已安装，是否重新配置？(y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "取消配置操作。"
            return
        fi
    fi

    # 创建安装目录
    mkdir -p $INSTALL_DIR
    
    # 如果是新安装，则下载并安装 FRP
    if [ ! -f "$INSTALL_DIR/frpc" ]; then
        echo -e "${BLUE}正在下载 FRP ${FRP_VERSION}...${NC}"
        cd /tmp
        wget -q --show-progress https://mirror.ghproxy.com/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz || {
            echo -e "${YELLOW}镜像下载失败，尝试直接下载...${NC}"
            wget -q --show-progress --timeout=10 https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz || {
                echo -e "${RED}下载失败，请检查网络连接或手动下载。${NC}"
                exit 1
            }
        }
        
        echo -e "${BLUE}正在安装 FRP 客户端...${NC}"
        tar -zxf frp_${FRP_VERSION}_linux_amd64.tar.gz
        cp frp_${}_linux_amd64/frpc $INSTALL_DIR/
        
        # 清理临时文件
        rm -f /tmp/frp_${}_linux_amd64.tar.gz
    fi

    # 获取服务器基本配置
    read -p "请输入服务端公网 IP 或域名: " VPS_IP
    read -p "请输入服务端口 [默认7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -p "请输入认证令牌 [默认mysecret123]: " TOKEN
    TOKEN=${TOKEN:-mysecret123}
    
    # 创建基本配置文件
    cat > $CONFIG_FILE <<EOF
[common]
server_addr = ${VPS_IP}
server_port = ${SERVER_PORT}
token = ${TOKEN}
EOF

    # 配置 SOCKS5 穿透（推荐用于远程访问）
    read -p "是否配置 SOCKS5 代理穿透？(y/n) [推荐开启，用于远程访问公司网络]: " setup_socks
    if [[ "$setup_socks" == "y" || "$setup_socks" == "Y" ]]; then
        read -p "请输入 SOCKS5 本地端口 [默认10811]: " SOCKS_LOCAL_PORT
        SOCKS_LOCAL_PORT=${SOCKS_LOCAL_PORT:-10811}
        read -p "请输入 SOCKS5 远程端口 [建议用6000以上端口]: " SOCKS_REMOTE_PORT
        
        cat >> $CONFIG_FILE <<EOF

[socks5_proxy]
type = tcp
local_ip = 127.0.0.1
local_port = ${SOCKS_LOCAL_PORT}
remote_port = ${SOCKS_REMOTE_PORT}
EOF
    fi
    
    # 配置 SSH 穿透
    read -p "是否配置 SSH 穿透？(y/n): " setup_ssh
    if [[ "$setup_ssh" == "y" || "$setup_ssh" == "Y" ]]; then
        read -p "请输入 SSH 本地端口 [默认22]: " SSH_LOCAL_PORT
        SSH_LOCAL_PORT=${SSH_LOCAL_PORT:-22}
        read -p "请输入 SSH 远程端口: " SSH_REMOTE_PORT
        
        cat >> $CONFIG_FILE <<EOF

[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = ${SSH_LOCAL_PORT}
remote_port = ${SSH_REMOTE_PORT}
EOF
    fi
    
    # 配置 Web 穿透
    read -p "是否配置 Web 穿透？(y/n): " setup_web
    if [[ "$setup_web" == "y" || "$setup_web" == "Y" ]]; then
        read -p "请输入 Web 本地端口 [默认80]: " WEB_LOCAL_PORT
        WEB_LOCAL_PORT=${WEB_LOCAL_PORT:-80}
        read -p "请输入 Web 远程端口: " WEB_REMOTE_PORT
        
        cat >> $CONFIG_FILE <<EOF

[web]
type = tcp
local_ip = 127.0.0.1
local_port = ${WEB_LOCAL_PORT}
remote_port = ${WEB_REMOTE_PORT}
EOF
    fi
    
    # 询问是否添加自定义端口穿透
    read -p "是否添加自定义端口穿透？(y/n): " setup_custom
    if [[ "$setup_custom" == "y" || "$setup_custom" == "Y" ]]; then
        add_tunnel
    fi

    # 创建系统服务
    echo -e "${BLUE}正在创建系统服务...${NC}"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frpc -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
StartLimitInterval=60s
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${BLUE}正在启动 FRP 客户端服务...${NC}"
    systemctl daemon-reload
    systemctl enable frpc
    systemctl restart frpc

    echo -e "${GREEN}✅ FRP 客户端安装完成！${NC}"
    echo
    view_config
    echo
    echo -e "${YELLOW}提示：运行选项 5 查看如何从外部连接到公司网络${NC}"
}

# 添加新的端口穿透
add_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装 FRP 客户端。${NC}"
        return
    fi
    
    read -p "请输入穿透名称 (英文字母，如 http, game 等): " TUNNEL_NAME
    read -p "请输入本地端口: " LOCAL_PORT
    read -p "请输入远程端口: " REMOTE_PORT
    
    # 添加到配置文件
    cat >> $CONFIG_FILE <<EOF

[${TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${LOCAL_PORT}
remote_port = ${REMOTE_PORT}
EOF

    echo -e "${GREEN}✅ 已添加新的端口穿透: ${TUNNEL_NAME}${NC}"
    
    # 如果 FRP 已安装并运行，则重启服务
    if systemctl is-active --quiet frpc; then
        systemctl restart frpc
        echo -e "${GREEN}✅ FRP 客户端服务已重启${NC}"
    fi
}

# 删除端口穿透
remove_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装 FRP 客户端。${NC}"
        return
    fi
    
    # 列出现有穿透
    if ! list_tunnels; then
        return
    fi
    
    echo
    read -p "请输入要删除的穿透名称: " TUNNEL_NAME
    
    # 检查穿透是否存在
    if ! grep -q "\[${TUNNEL_NAME}\]" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 穿透 '${TUNNEL_NAME}' 不存在。${NC}"
        return
    fi
    
    # 创建临时文件
    TEMP_FILE=$(mktemp)
    
    # 使用 awk 删除指定的穿透部分
    awk -v name="$TUNNEL_NAME" '
    BEGIN { skip = 0; }
    /^\[/ { 
        if ($0 == "[" name "]") {
            skip = 1;
        } else {
            skip = 0;
            print;
        }
        next;
    }
    !skip { print; }
    ' "$CONFIG_FILE" > "$TEMP_FILE"
    
    # 替换原配置文件
    mv "$TEMP_FILE" "$CONFIG_FILE"
    
    echo -e "${GREEN}✅ 已删除端口穿透: ${TUNNEL_NAME}${NC}"
    
    # 如果 FRP 已安装并运行，则重启服务
    if systemctl is-active --quiet frpc; then
        systemctl restart frpc
        echo -e "${GREEN}✅ FRP 客户端服务已重启${NC}"
    fi
}

# 查看当前配置
view_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装 FRP 客户端。${NC}"
        return
    fi
    
    echo -e "${BLUE}FRP 客户端配置:${NC}"
    
    # 列出所有端口穿透
    list_tunnels
}

# 显示使用说明
show_usage() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        FRP 远程访问使用说明           ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}【基本概念】${NC}"
    echo -e "FRP 客户端安装在公司电脑上，FRP 服务端安装在有公网 IP 的服务器上。"
    echo -e "通过 FRP，您可以在外部通过服务器访问公司内网资源。"
    echo
    echo -e "${GREEN}【使用 SOCKS5 代理访问公司网络】${NC}"
    echo -e "1. 确保您的 FRP 客户端已配置并启动 SOCKS5 代理穿透"
    echo -e "2. 在您的手机或其他设备上设置 SOCKS5 代理:"
    
    # 如果找到 SOCKS5 配置，显示详细信息
    if [ -f "$CONFIG_FILE" ] && grep -q "\[socks5_proxy\]" "$CONFIG_FILE"; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        SOCKS_REMOTE_PORT=$(grep -A 3 "\[socks5_proxy\]" "$CONFIG_FILE" | grep "remote_port" | cut -d'=' -f2 | tr -d ' ')
        echo -e "   - 代理服务器: ${SERVER_ADDR}"
        echo -e "   - 代理端口: ${SOCKS_REMOTE_PORT}"
    else
        echo -e "   - 代理服务器: 您的 FRP 服务器 IP/域名"
        echo -e "   - 代理端口: 您配置的 SOCKS5 远程端口"
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
    echo -e "或者使用专用的代理软件/APP (如 Shadowsocks, V2rayNG 等)，设置 SOCKS5 代理。"
    echo
    echo -e "${GREEN}【SSH 远程连接】${NC}"
    
    # 如果找到 SSH 配置，显示详细信息
    if [ -f "$CONFIG_FILE" ] && grep -q "\[ssh\]" "$CONFIG_FILE"; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        SSH_REMOTE_PORT=$(grep -A 3 "\[ssh\]" "$CONFIG_FILE" | grep "remote_port" | cut -d'=' -f2 | tr -d ' ')
        echo -e "使用以下命令连接到您的公司电脑:"
        echo -e "  ssh -p ${SSH_REMOTE_PORT} 用户名@${SERVER_ADDR}"
    else
        echo -e "如果您配置了 SSH 穿透，使用以下命令连接到您的公司电脑:"
        echo -e "  ssh -p <SSH远程端口> 用户名@<您的FRP服务器IP>"
    fi
    
    echo
    echo -e "${GREEN}【注意事项】${NC}"
    echo -e "1. 确保公司电脑始终开机并运行 FRP 客户端"
    echo -e "2. 如果公司网络有防火墙，确保不会阻止 FRP 连接"
    echo -e "3. 定期检查 FRP 客户端状态，确保服务正常运行"
    echo -e "4. 建议为 FRP 设置强密码保护，避免未授权访问"
    echo -e "${BLUE}========================================${NC}"
}

# 卸载 FRP 客户端
uninstall_frpc() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${RED}FRP 客户端未安装，无需卸载。${NC}"
        return
    fi

    echo -e "${BLUE}正在停止 FRP 客户端服务...${NC}"
    systemctl stop frpc 2>/dev/null || echo "服务已经停止"
    systemctl disable frpc 2>/dev/null || echo "服务已经禁用"

    echo -e "${BLUE}正在删除 FRP 文件...${NC}"
    rm -f $SERVICE_FILE
    rm -rf $INSTALL_DIR

    echo -e "${BLUE}正在重新加载 systemd...${NC}"
    systemctl daemon-reload

    echo -e "${GREEN}✅ FRP 客户端已完全卸载。${NC}"
}

# 端口管理功能
manage_ports() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装 FRP 客户端。${NC}"
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

# 主函数
main() {
    while true; do
        show_menu
        read -p "请输入选项 [1-6]: " choice
        case $choice in
            1)
                install_frpc
                read -p "按回车键继续..."
                ;;
            2)
                uninstall_frpc
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
