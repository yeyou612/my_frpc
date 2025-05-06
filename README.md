# my_frpc

; --------------------------
; ✅ FRP 服务端配置（frps.ini）
; 放在 VPS 上
; --------------------------
[common]
bind_port = 7000

# 可视化面板
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin123

# 日志
log_level = info
log_file = ./frps.log

# 安全认证
authentication_method = token
token = mysecret123


; --------------------------
; ✅ FRP 客户端配置（frpc.ini）
; 放在 Linux 客户端（Xray/SSH/Web）上
; --------------------------
[common]
server_addr = YOUR_VPS_PUBLIC_IP
server_port = 7000
token = mysecret123

# socks5 代理穿透（Xray）
[socks5_proxy]
type = tcp
local_ip = 127.0.0.1
local_port = 10811
remote_port = 6000

# SSH 穿透
[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 6001

# Web（Flask等）穿透
[web]
type = tcp
local_ip = 127.0.0.1
local_port = 8000
remote_port = 6002


; --------------------------
; ✅ 客户端 systemd 启动服务（/etc/systemd/system/frpc.service）
; 可选，如果你希望 Linux 客户端开机自启
; --------------------------
[Unit]
Description=FRP Client Service
After=network.target

[Service]
Type=simple
ExecStart=/root/frp_0.58.0_linux_amd64/frpc -c /root/frp_0.58.0_linux_amd64/frpc.ini
Restart=on-failure

[Install]
WantedBy=multi-user.target


; --------------------------
; ✅ VPS 上 UFW 防火墙开放命令
; --------------------------
sudo ufw allow 7000
sudo ufw allow 7500
sudo ufw allow 6000
sudo ufw allow 6001
sudo ufw allow 6002
sudo ufw enable

; --------------------------
; ✅ VPS 启动 frps
; --------------------------
cd ~/frp_0.58.0_linux_amd64
./frps -c ./frps.ini

; 可选后台运行方式
nohup ./frps -c ./frps.ini > frps.log 2>&1 &

创建 systemd 服务文件：
/etc/systemd/system/frps.service
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=/root/frp_0.58.0_linux_amd64/frps -c /root/frp_0.58.0_linux_amd64/frps.ini
Restart=on-failure

[Install]
WantedBy=multi-user.target

注意修改 ExecStart 中的路径为你实际 frps 所在目录

# 启用服务并开机自启：
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable frps
sudo systemctl start frps

# 查看状态 / 日志：
sudo systemctl status frps
journalctl -u frps -f


; --------------------------
; ✅ windows 客户端
; --------------------------
[common]
server_addr = YOUR_VPS_PUBLIC_IP
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

# 创建一个 启动_frpc.bat 批处理文件，内容如下：
@echo off
cd /d E:\mypython\xray_custom
start frpc.exe -c frpc.ini
