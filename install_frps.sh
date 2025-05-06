
# --------------------------
# ✅ 一键部署脚本 install_frps.sh（仅适用于 VPS 服务端）
# --------------------------

#!/bin/bash

set -e

# 配置参数
FRP_VERSION=0.58.0
INSTALL_DIR=/usr/local/frp

# 创建目录
mkdir -p $INSTALL_DIR
cd /tmp

# 下载并解压
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz

tar -zxvf frp_${FRP_VERSION}_linux_amd64.tar.gz
cp frp_${FRP_VERSION}_linux_amd64/frps $INSTALL_DIR/

# 写入配置文件
cat > $INSTALL_DIR/frps.ini <<EOF
[common]
bind_port = 7000
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin123
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
