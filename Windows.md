# --------------------------
# ✅ Windows 客户端 frpc.ini（保存到 E:\mypython\xray_custom）
# --------------------------
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


# --------------------------
# ✅ Windows 启动脚本（frpc.bat）
# --------------------------
@echo off
cd /d E:\mypython\xray_custom
start frpc.exe -c frpc.ini
