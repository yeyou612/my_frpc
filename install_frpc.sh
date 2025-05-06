# --------------------------
# ✅ 一键部署脚本 install_frpc.sh（适用于 Linux 客户端）
# --------------------------

#!/bin/bash

set -e

read -p "请输入服务端公网 IP 或域名: " VPS_IP

FRP_VERSION=0.58.0
INSTALL_DIR=/usr/local/frp

mkdir -p $INSTALL_DIR
cd /tmp

wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz

tar -zxvf frp_${FRP_VERSION}_linux_amd64.tar.gz
cp frp_${FRP_VERSION}_linux_amd64/frpc $INSTALL_DIR/

cat > $INSTALL_DIR/frpc.ini <<EOF
[common]
server_addr = ${VPS_IP}
server_port = 7000
token = mysecret123

[socks5_proxy]
type = tcp
local_ip = 127.0.0.1
local_port = 10811
remote_port = 6000

[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 6001

[web]
type = tcp
local_ip = 127.0.0.1
local_port = 8000
remote_port = 6002
EOF

cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frpc -c ${INSTALL_DIR}/frpc.ini
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable frpc
systemctl start frpc


# --------------------------
# ✅ 卸载脚本 uninstall_frpc.sh
# --------------------------

#!/bin/bash

set -e

systemctl stop frpc
systemctl disable frpc
rm -f /etc/systemd/system/frpc.service
rm -rf /usr/local/frp
systemctl daemon-reload

echo "✅ frpc 已完全卸载。"
