# --------------------------
# ✅ 一键部署脚本 install_frps.sh（带交互设置 + 可卸载）
# --------------------------

#!/bin/bash

set -e

# 交互输入
read -p "请输入 Dashboard 用户名（默认 admin）: " DASH_USER
read -p "请输入 Dashboard 密码（默认 admin123）: " DASH_PWD

DASH_USER=${DASH_USER:-admin}
DASH_PWD=${DASH_PWD:-admin123}

# 配置参数
FRP_VERSION=0.58.0
INSTALL_DIR=/usr/local/frp

# 创建目录
mkdir -p $INSTALL_DIR
cd /tmp

# 下载并解压
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz

tar -zxvf frp_${FRP_VERSION}_linux_amd64.tar.gz

# 检查是否正在运行，避免覆盖错误
if pgrep -x "frps" > /dev/null; then
  echo "⚠️ 检测到 frps 正在运行，正在尝试停止..."
  systemctl stop frps || true
  sleep 2
  while fuser "$INSTALL_DIR/frps" 2>/dev/null | grep -q .; do
    echo "⏳ 等待 frps 文件释放中..."
    sleep 1
  done
fi

cp frp_${FRP_VERSION}_linux_amd64/frps $INSTALL_DIR/frps.new
mv -f $INSTALL_DIR/frps.new $INSTALL_DIR/frps

# 写入配置文件
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

# 创建 systemd 服务
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

# 启动服务
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable frps
systemctl start frps

# 防火墙放通（如使用 ufw）
ufw allow 7000 || true
ufw allow 7500 || true
ufw allow 6000 || true
ufw allow 6001 || true
ufw allow 6002 || true
ufw enable || true

# 输出状态
systemctl status frps --no-pager


# --------------------------
# ✅ 卸载脚本 uninstall_frps.sh
# --------------------------

#!/bin/bash

set -e

systemctl stop frps
systemctl disable frps
rm -f /etc/systemd/system/frps.service
rm -rf /usr/local/frp
systemctl daemon-reload

echo "✅ frps 已完全卸载。"
