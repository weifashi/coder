#!/bin/bash
set -e

# 修复 home 目录权限（Docker Volume 挂载后归 root）
if [ "$(stat -c %U /home/coder 2>/dev/null)" != "coder" ]; then
    chown coder:coder /home/coder
fi

# 确保常用子目录存在且权限正确
mkdir -p /home/coder/workspaces /home/coder/.config
chown coder:coder /home/coder/workspaces /home/coder/.config

# Go 目录（仅安装了 Go 时创建）
if [ -d /usr/local/go ]; then
    mkdir -p /home/coder/go
    chown coder:coder /home/coder/go
fi

# 启动独立的 Docker 守护进程（DinD）
dockerd --storage-driver=overlay2 > /tmp/dockerd.log 2>&1 &

# 等待 dockerd 就绪
for i in $(seq 1 30); do
    if docker info > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 以 coder 用户执行后续命令
exec gosu coder "$@"
