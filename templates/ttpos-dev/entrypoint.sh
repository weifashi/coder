#!/bin/bash
set -e

# 修复 home 目录权限（Docker Volume 挂载后归 root）
if [ "$(stat -c %U /home/coder 2>/dev/null)" != "coder" ]; then
    chown coder:coder /home/coder
fi

# 确保常用子目录存在且权限正确
mkdir -p /home/coder/workspaces /home/coder/go /home/coder/.config
chown coder:coder /home/coder/workspaces /home/coder/go /home/coder/.config

# 修复 Docker socket 权限，让 coder 用户可以访问
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c %g /var/run/docker.sock)
    if ! getent group "$DOCKER_GID" >/dev/null 2>&1; then
        groupadd -g "$DOCKER_GID" dockerhost
    fi
    DOCKER_GROUP=$(getent group "$DOCKER_GID" | cut -d: -f1)
    usermod -aG "$DOCKER_GROUP" coder
fi

# 以 coder 用户执行后续命令
exec gosu coder "$@"