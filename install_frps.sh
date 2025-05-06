# --------------------------
# ✅ 多功能菜单式安装脚本 install_frps.sh（安装 / 卸载 / 查看配置）
# --------------------------

#!/bin/bash

set -e

FRP_VERSION=0.58.0
INSTALL_DIR=/usr/local/frp

check_installed() {
  if [[ -f "$INSTALL_DIR/frps" ]]; then
    return 0
  else
    return 1
  fi
}

show_menu() {
  echo "========================="
  echo " FRPS 一键管理脚本"
  echo "========================="
  echo "1. 安装 frps 服务端"
  echo "2. 卸载 frps 服务端"
  echo "3. 查看当前配置"
  echo "4. 退出"
  echo "========================="
  read -p "请输入选项 [1-4]: " choice

  case "$choice" in
    1) install_frps ;;
    2) uninstall_frps ;;
    3) cat $INSTALL_DIR/frps.ini 2>/dev/null || echo "未找到配置文件。" ;;
    4) exit 0 ;;
    *) echo "❌ 无效选项" ;;
  esac
}

install_frps() {
  if check_installed; then
    echo "⚠️ 已检测到 frps 已安装在 $INSTALL_DIR"
    show_menu
    return
  fi

  read -p "请输入 Dashboard 用户名（默认 admin）: " DASH_USER
  read -p "请输入 Dashboard 密码（默认 admin123）: " DASH_PWD
  DASH_USER=${DASH_USER:-admin}
  DASH_PWD=${DASH_PWD:-admin123}

  mkdir -p $INSTALL_DIR
  cd /tmp

  wget -q https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz
  tar -zxf frp_${FRP_VERSION}_linux_amd64.tar.gz

  if pgrep -x "frps" > /dev/null; then
    echo "⚠️ 检测到 frps 正在运行，尝试停止..."
    systemctl stop frps || true
    sleep 2
    while fuser "$INSTALL_DIR/frps" 2>/dev/null | grep -q .; do
      echo "⏳ 等待 frps 文件释放中..."
      sleep 1
    done
  fi

  cp frp_${FRP_VERSION}_linux_amd64/frps $INSTALL_DIR/frps.new
  mv -f $INSTALL_DIR/frps.new $INSTALL_DIR/frps

  cat > $INSTALL_DIR/frps.ini <<EOF
[common]
bind_port = 7000
dashboard_port = 7500
dashboard_user = ${DASH_USER}
dashboard_pwd = ${DASH_PWD}
log_level = info
log_file = /var/log/frps.log
authentication_method = token
token = mysecret123
EOF

  cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=FRP Server Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frps -c ${INSTALL_DIR}/frps.ini
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable frps
  systemctl restart frps

  ufw allow 7000 || true
  ufw allow 7500 || true
  ufw allow 6000 || true
  ufw allow 6001 || true
  ufw allow 6002 || true
  ufw enable || true

  echo "✅ frps 已安装成功，当前配置如下："
  cat $INSTALL_DIR/frps.ini
  systemctl status frps --no-pager
}

uninstall_frps() {
  if systemctl is-active --quiet frps; then
    echo "🔍 检测到 frps 正在运行，正在停止服务..."
    systemctl stop frps
  fi

  if systemctl is-enabled --quiet frps; then
    echo "🔧 正在移除开机启动配置..."
    systemctl disable frps
  fi

  echo "🗑️ 正在清理配置与文件..."
  rm -f /etc/systemd/system/frps.service
  rm -rf /usr/local/frp
  systemctl daemon-reload
  echo "✅ frps 已完全卸载。"
}

# 启动脚本前判断安装状态
if check_installed; then
  echo "✅ 已检测到 frps 安装，进入菜单模式管理："
else
  echo "🆕 未检测到 frps，可进行安装："
fi

show_menu
