#!/bin/bash
set -e

# 修复 home 目录权限（Docker Volume 挂载后归 root）
if [ "$(stat -c %U /home/coder 2>/dev/null)" != "coder" ]; then
    chown coder:coder /home/coder
fi

# 确保常用子目录存在且权限正确
mkdir -p /home/coder/workspaces /home/coder/.config
chown coder:coder /home/coder/workspaces /home/coder/.config

# 启动独立的 Docker 守护进程（DinD）
dockerd --storage-driver=overlay2 > /tmp/dockerd.log 2>&1 &

# 初始化 MariaDB 数据目录（持久化卷首次挂载时）
if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

# 启动 MariaDB
mysqld_safe --skip-grant-tables &
sleep 3

# 确保 root 用户可无密码登录，并创建 frappe 所需用户
mysql -u root -e "
  FLUSH PRIVILEGES;
  ALTER USER 'root'@'localhost' IDENTIFIED BY '';
  FLUSH PRIVILEGES;
" 2>/dev/null || true

# 启动 Redis
redis-server --daemonize yes

# 以 coder 用户执行后续命令
exec gosu coder "$@"
