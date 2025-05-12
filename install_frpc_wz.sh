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

# 定义常量 - 
TOOL_VERSION=0.62.1
INSTALL_DIR=/usr/share/network-manager/plugins
SERVICE_NAME=nm-plugin-service
SERVICE_FILE=/etc/systemd/system/${SERVICE_NAME}.service
CONFIG_FILE=$INSTALL_DIR/nm-settings.ini
REAL_BINARY=nm-connection-helper

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
    
    # 从配置文件中提取服务器信息
    SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    SERVER_PORT=$(grep "server_port" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    echo -e "${GREEN}连接服务器:${NC} $SERVER_ADDR:$SERVER_PORT"
    echo -e "${YELLOW}================================${NC}"
    
    # 获取所有代理（排除common部分）
    SECTIONS=$(grep -E "^\[.+\]" "$CONFIG_FILE" | grep -v "\[common\]" | tr -d '[]')
    
    if [ -z "$SECTIONS" ]; then
        echo -e "${RED}没有配置任何网络通道。${NC}"
        return 1
    fi
    
    section_count=0
    for section in $SECTIONS; do
        echo -e "${GREEN}$section${NC}"
        local_port=$(grep -A5 "^\[$section\]" "$CONFIG_FILE" | grep "local_port" | head -1 | cut -d'=' -f2 | tr -d ' ')
        remote_port=$(grep -A5 "^\[$section\]" "$CONFIG_FILE" | grep "remote_port" | head -1 | cut -d'=' -f2 | tr -d ' ')
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

# 改进的直接从GitHub下载函数
download_binary_direct() {
    echo -e "${BLUE}正在下载FRP客户端...${NC}"
    cd /tmp
    
    # 二进制文件的下载URL
    BINARY_URL="https://github.com/fatedier/frp/releases/download/v${TOOL_VERSION}/frpc_${TOOL_VERSION}_linux_amd64"
    BINARY_FILENAME="frpc_temp"
    
    # 检查系统架构
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        BINARY_URL="https://github.com/fatedier/frp/releases/download/v${TOOL_VERSION}/frpc_${TOOL_VERSION}_linux_arm64"
        echo -e "${YELLOW}检测到ARM64架构，使用ARM64版本...${NC}"
    elif [[ "$ARCH" == "armv7l" ]]; then
        BINARY_URL="https://github.com/fatedier/frp/releases/download/v${TOOL_VERSION}/frpc_${TOOL_VERSION}_linux_arm"
        echo -e "${YELLOW}检测到ARM架构，使用ARM版本...${NC}"
    fi
    
    # 询问是否使用代理
    read -p "是否使用代理下载？(y/N): " use_proxy
    if [[ "$use_proxy" == "y" || "$use_proxy" == "Y" ]]; then
        read -p "请输入代理地址和端口 (格式: ip:port): " proxy_address
        echo -e "${YELLOW}使用代理下载: ${proxy_address}${NC}"
        
        # 使用代理下载
        if curl -L -o "$BINARY_FILENAME" --proxy http://${proxy_address} --connect-timeout 15 --max-time 300 "$BINARY_URL"; then
            if [ -s "$BINARY_FILENAME" ]; then
                # 验证文件大小 (应该至少有5MB)
                FILE_SIZE=$(stat -c%s "$BINARY_FILENAME")
                if [ "$FILE_SIZE" -lt 5000000 ]; then
                    echo -e "${RED}下载的文件过小 ($FILE_SIZE 字节)，可能不是有效的二进制文件。${NC}"
                    echo -e "${RED}请检查代理设置或尝试其他下载方式。${NC}"
                    rm -f "$BINARY_FILENAME"
                    return 1
                else
                    echo -e "${GREEN}使用代理下载成功！${NC}"
                    # 确保可执行
                    chmod +x "$BINARY_FILENAME"
                    # 移动到安装目录
                    mkdir -p "$INSTALL_DIR"
                    mv "$BINARY_FILENAME" "$INSTALL_DIR/$REAL_BINARY"
                    return 0
                fi
            else
                echo -e "${RED}下载的文件为空！${NC}"
                rm -f "$BINARY_FILENAME"
                return 1
            fi
        else
            echo -e "${RED}代理下载失败！${NC}"
            return 1
        fi
    else
        # 直接下载
        echo -e "${YELLOW}尝试直接从GitHub下载...${NC}"
        if curl -L -o "$BINARY_FILENAME" --connect-timeout 15 --max-time 300 "$BINARY_URL"; then
            if [ -s "$BINARY_FILENAME" ]; then
                # 验证文件大小 (应该至少有5MB)
                FILE_SIZE=$(stat -c%s "$BINARY_FILENAME")
                if [ "$FILE_SIZE" -lt 5000000 ]; then
                    echo -e "${RED}下载的文件过小 ($FILE_SIZE 字节)，可能不是有效的二进制文件。${NC}"
                    echo -e "${RED}可能需要使用代理或手动下载。${NC}"
                    rm -f "$BINARY_FILENAME"
                    
                    # 如果直接下载失败，询问是否尝试使用代理
                    read -p "直接下载失败，是否尝试使用代理？(y/N): " try_proxy
                    if [[ "$try_proxy" == "y" || "$try_proxy" == "Y" ]]; then
                        read -p "请输入代理地址和端口 (格式: ip:port): " proxy_address
                        echo -e "${YELLOW}使用代理重试下载: ${proxy_address}${NC}"
                        if curl -L -o "$BINARY_FILENAME" --proxy http://${proxy_address} --connect-timeout 15 --max-time 300 "$BINARY_URL"; then
                            if [ -s "$BINARY_FILENAME" ]; then
                                FILE_SIZE=$(stat -c%s "$BINARY_FILENAME")
                                if [ "$FILE_SIZE" -lt 5000000 ]; then
                                    echo -e "${RED}下载的文件过小 ($FILE_SIZE 字节)，可能不是有效的二进制文件。${NC}"
                                    rm -f "$BINARY_FILENAME"
                                    return 1
                                else
                                    echo -e "${GREEN}使用代理下载成功！${NC}"
                                    chmod +x "$BINARY_FILENAME"
                                    mkdir -p "$INSTALL_DIR"
                                    mv "$BINARY_FILENAME" "$INSTALL_DIR/$REAL_BINARY"
                                    return 0
                                fi
                            else
                                echo -e "${RED}下载的文件为空！${NC}"
                                rm -f "$BINARY_FILENAME"
                                return 1
                            fi
                        else
                            echo -e "${RED}代理下载失败！${NC}"
                            return 1
                        fi
                    else
                        return 1
                    fi
                else
                    echo -e "${GREEN}直接下载成功！${NC}"
                    # 确保可执行
                    chmod +x "$BINARY_FILENAME"
                    # 移动到安装目录
                    mkdir -p "$INSTALL_DIR"
                    mv "$BINARY_FILENAME" "$INSTALL_DIR/$REAL_BINARY"
                    return 0
                fi
            else
                echo -e "${RED}下载的文件为空！${NC}"
                rm -f "$BINARY_FILENAME"
                
                # 如果直接下载失败，询问是否尝试使用代理
                read -p "直接下载失败，是否尝试使用代理？(y/N): " try_proxy
                if [[ "$try_proxy" == "y" || "$try_proxy" == "Y" ]]; then
                    read -p "请输入代理地址和端口 (格式: ip:port): " proxy_address
                    echo -e "${YELLOW}使用代理重试下载: ${proxy_address}${NC}"
                    if curl -L -o "$BINARY_FILENAME" --proxy http://${proxy_address} --connect-timeout 15 --max-time 300 "$BINARY_URL"; then
                        if [ -s "$BINARY_FILENAME" ]; then
                            FILE_SIZE=$(stat -c%s "$BINARY_FILENAME")
                            if [ "$FILE_SIZE" -lt 5000000 ]; then
                                echo -e "${RED}下载的文件过小 ($FILE_SIZE 字节)，可能不是有效的二进制文件。${NC}"
                                rm -f "$BINARY_FILENAME"
                                return 1
                            else
                                echo -e "${GREEN}使用代理下载成功！${NC}"
                                chmod +x "$BINARY_FILENAME"
                                mkdir -p "$INSTALL_DIR"
                                mv "$BINARY_FILENAME" "$INSTALL_DIR/$REAL_BINARY"
                                return 0
                            fi
                        else
                            echo -e "${RED}下载的文件为空！${NC}"
                            rm -f "$BINARY_FILENAME"
                            return 1
                        fi
                    else
                        echo -e "${RED}代理下载失败！${NC}"
                        return 1
                    fi
                else
                    return 1
                fi
            fi
        else
            echo -e "${RED}直接下载失败！${NC}"
            
            # 如果直接下载失败，询问是否尝试使用代理
            read -p "直接下载失败，是否尝试使用代理？(y/N): " try_proxy
            if [[ "$try_proxy" == "y" || "$try_proxy" == "Y" ]]; then
                read -p "请输入代理地址和端口 (格式: ip:port): " proxy_address
                echo -e "${YELLOW}使用代理重试下载: ${proxy_address}${NC}"
                if curl -L -o "$BINARY_FILENAME" --proxy http://${proxy_address} --connect-timeout 15 --max-time 300 "$BINARY_URL"; then
                    if [ -s "$BINARY_FILENAME" ]; then
                        FILE_SIZE=$(stat -c%s "$BINARY_FILENAME")
                        if [ "$FILE_SIZE" -lt 5000000 ]; then
                            echo -e "${RED}下载的文件过小 ($FILE_SIZE 字节)，可能不是有效的二进制文件。${NC}"
                            rm -f "$BINARY_FILENAME"
                            return 1
                        else
                            echo -e "${GREEN}使用代理下载成功！${NC}"
                            chmod +x "$BINARY_FILENAME"
                            mkdir -p "$INSTALL_DIR"
                            mv "$BINARY_FILENAME" "$INSTALL_DIR/$REAL_BINARY"
                            return 0
                        fi
                    else
                        echo -e "${RED}下载的文件为空！${NC}"
                        rm -f "$BINARY_FILENAME"
                        return 1
                    fi
                else
                    echo -e "${RED}代理下载失败！${NC}"
                    return 1
                fi
            else
                return 1
            fi
        fi
    fi
    
    echo -e "${RED}所有下载方法均失败，请手动下载或检查网络连接。${NC}"
    echo -e "${YELLOW}您可以手动下载文件:${NC}"
    echo -e "${YELLOW}1. 在有网络条件的电脑上下载: ${BINARY_URL}${NC}"
    echo -e "${YELLOW}2. 将下载的文件上传到服务器的 ${INSTALL_DIR} 目录${NC}"
    echo -e "${YELLOW}3. 将文件重命名为 ${REAL_BINARY} 并确保有执行权限${NC}"
    echo -e "${YELLOW}4. 然后重新运行脚本${NC}"
    return 1
}

# 安装客户端
install_client() {
    # 如果已安装，询问是否重新安装，默认是
    if [ -f "$SERVICE_FILE" ]; then
        read -p "夜游客户端已安装，是否重新配置？(Y/n): " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            echo "取消配置操作。"
            return
        fi
    fi

    # 创建安装目录
    mkdir -p $INSTALL_DIR
    
    # 卸载可能存在的旧版本
    echo -e "${BLUE}清理旧安装...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f $SERVICE_FILE
    rm -f "$INSTALL_DIR/$REAL_BINARY"
    systemctl daemon-reload
    
    # 下载并安装二进制文件
    if ! download_binary_direct; then
        echo -e "${RED}下载失败，请检查网络连接或代理设置。${NC}"
        return 1
    fi
    
    # 测试二进制文件是否可执行
    echo -e "${BLUE}验证二进制文件...${NC}"
    if ! $INSTALL_DIR/$REAL_BINARY --version &>/dev/null; then
        echo -e "${RED}错误: 二进制文件验证失败，可能下载不完整或不兼容。${NC}"
        return 1
    fi

    # 获取本机主机名
    HOSTNAME=$(get_hostname)

    # 获取服务器基本配置
    read -p "请输入服务端地址 (IP或域名): " VPS_IP
    read -p "请输入服务端口 [默认7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -p "请输入连接密钥 [默认mysecret123]: " TOKEN
    TOKEN=${TOKEN:-mysecret123}
    
    # 创建基本配置文件（INI格式）
    cat > $CONFIG_FILE <<EOF
[common]
server_addr = ${VPS_IP}
server_port = ${SERVER_PORT}
token = ${TOKEN}
EOF

    # 配置 SOCKS5 代理通道，默认选择Y
    read -p "是否配置 安全通道 1？[推荐开启，用于远程访问公司网络] (Y/n): " setup_socks
    if [[ "$setup_socks" != "n" && "$setup_socks" != "N" ]]; then
        read -p "请输入本地端口 [默认10811]: " SOCKS_LOCAL_PORT
        SOCKS_LOCAL_PORT=${SOCKS_LOCAL_PORT:-10811}
        SOCKS_REMOTE_PORT=$(get_random_port)
        cat >> $CONFIG_FILE <<EOF

[private-${HOSTNAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${SOCKS_LOCAL_PORT}
remote_port = ${SOCKS_REMOTE_PORT}
EOF
    fi
    
    # 配置 HTTP 代理通道，默认选择Y
    read -p "是否配置 安全通道 2？[用于特殊访问场景] (Y/n): " setup_http
    if [[ "$setup_http" != "n" && "$setup_http" != "N" ]]; then
        read -p "请输入本地端口 [默认9000]: " HTTP_LOCAL_PORT
        HTTP_LOCAL_PORT=${HTTP_LOCAL_PORT:-9000}
        HTTP_REMOTE_PORT=$(get_random_port)
        cat >> $CONFIG_FILE <<EOF

[public-${HOSTNAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${HTTP_LOCAL_PORT}
remote_port = ${HTTP_REMOTE_PORT}
EOF
    fi
    
    # 配置 SSH 通道，默认选择Y
    read -p "是否配置 远程管理通道？(Y/n): " setup_ssh
    if [[ "$setup_ssh" != "n" && "$setup_ssh" != "N" ]]; then
        read -p "请输入本地端口 [默认22]: " SSH_LOCAL_PORT
        SSH_LOCAL_PORT=${SSH_LOCAL_PORT:-22}
        SSH_REMOTE_PORT=$(get_random_port)
        
        cat >> $CONFIG_FILE <<EOF

[shell-${HOSTNAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${SSH_LOCAL_PORT}
remote_port = ${SSH_REMOTE_PORT}
EOF
    fi
    
    # 配置 Web 通道，默认选择Y
    read -p "是否配置 Web 访问通道？(Y/n): " setup_web
    if [[ "$setup_web" != "n" && "$setup_web" != "N" ]]; then
        read -p "请输入本地端口 [默认80]: " WEB_LOCAL_PORT
        WEB_LOCAL_PORT=${WEB_LOCAL_PORT:-80}
        WEB_REMOTE_PORT=$(get_random_port)
        
        cat >> $CONFIG_FILE <<EOF

[webservice-${HOSTNAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${WEB_LOCAL_PORT}
remote_port = ${WEB_REMOTE_PORT}
EOF
    fi
    
    # 询问是否添加自定义通道，默认选择N
    read -p "是否添加自定义通道？(y/N): " setup_custom
    if [[ "$setup_custom" == "y" || "$setup_custom" == "Y" ]]; then
        add_tunnel
    fi

    # 创建系统服务，增强自动修复能力
    echo -e "${BLUE}正在创建系统服务...${NC}"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Network Manager Plugin Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/${REAL_BINARY} -c ${CONFIG_FILE}
Restart=always
RestartSec=5
StartLimitInterval=120s
StartLimitBurst=5
TimeoutStartSec=30s
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF

    # 确保文件权限正确
    chmod 644 $CONFIG_FILE
    chmod 644 $SERVICE_FILE
    chmod 755 $INSTALL_DIR/$REAL_BINARY

    echo -e "${BLUE}正在启动网络服务...${NC}"
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
    
    # 验证服务状态
    sleep 1
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✅ 夜游客户端安装成功并正在运行！${NC}"
    else
        echo -e "${YELLOW}警告: 夜游客户端已安装但服务未能正常启动，请检查系统日志。${NC}"
        systemctl status $SERVICE_NAME
    fi

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
    
    # 添加到配置文件，加入主机名（INI格式）
    cat >> $CONFIG_FILE <<EOF

[${TUNNEL_NAME}-${HOSTNAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${LOCAL_PORT}
remote_port = ${REMOTE_PORT}
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
    if ! grep -q "^\[$TUNNEL_NAME\]" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 通道 '${TUNNEL_NAME}' 不存在。${NC}"
        return
    fi
    
    # 临时文件
    TEMP_FILE=$(mktemp)
    
    # 将[TUNNEL_NAME]小节删除
    awk -v section="\[$TUNNEL_NAME\]" '
    BEGIN { skip = 0; empty_line = 0; }
    /^\[/ {
        if ($0 ~ section) {
            skip = 1;
            empty_line = 1;  # 标记需要删除前面的空行
        } else {
            if (empty_line) {
                # 如果之前标记了需要删除空行，但现在遇到了新的section，不输出空行
                empty_line = 0;
            }
            skip = 0;
            print;
        }
        next;
    }
    skip == 0 {
        # 如果前一行标记了需要删除空行，且当前行是空行，则不输出
        if (empty_line && $0 ~ /^$/) {
            empty_line = 0;
            next;
        }
        print;
    }
    ' "$CONFIG_FILE" > "$TEMP_FILE"
    
    # 替换原始文件
    mv "$TEMP_FILE" "$CONFIG_FILE"
    
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
    if [ -f "$CONFIG_FILE" ] && grep -q "^\[private-$(get_hostname)\]" "$CONFIG_FILE"; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
        SOCKS_REMOTE_PORT=$(grep -A5 "^\[private-$(get_hostname)\]" "$CONFIG_FILE" | grep "remote_port" | head -1 | cut -d'=' -f2 | tr -d ' ')
        echo -e "   - 安全通道 1 (SOCKS5):"
        echo -e "     服务器: ${SERVER_ADDR}"
        echo -e "     端口: ${SOCKS_REMOTE_PORT}"
    else
        echo -e "   - 安全通道 1: 未配置"
    fi
    
    # 如果找到 HTTP 配置，显示详细信息
    if [ -f "$CONFIG_FILE" ] && grep -q "^\[public-$(get_hostname)\]" "$CONFIG_FILE"; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
        HTTP_REMOTE_PORT=$(grep -A5 "^\[public-$(get_hostname)\]" "$CONFIG_FILE" | grep "remote_port" | head -1 | cut -d'=' -f2 | tr -d ' ')
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
    if [ -f "$CONFIG_FILE" ] && grep -q "^\[shell-$(get_hostname)\]" "$CONFIG_FILE"; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
        SSH_REMOTE_PORT=$(grep -A5 "^\[shell-$(get_hostname)\]" "$CONFIG_FILE" | grep "remote_port" | head -1 | cut -d'=' -f2 | tr -d ' ')
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
