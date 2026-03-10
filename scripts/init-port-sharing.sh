#!/bin/bash
# 等待 Coder 就绪，通过数据库直接为所有模板开启端口共享
set -e

echo "⏳ 等待数据库就绪..."
for i in $(seq 1 60); do
  if PGPASSWORD="$POSTGRES_PASSWORD" psql -h database -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1" > /dev/null 2>&1; then
    echo "✅ 数据库已就绪"
    break
  fi
  if [ "$i" = "60" ]; then
    echo "❌ 等待数据库超时"
    exit 1
  fi
  sleep 1
done

# 等待 Coder 创建表
sleep 5

echo "🔧 设置所有模板端口共享为 public..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h database -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "UPDATE templates SET max_port_sharing_level = 'public' WHERE max_port_sharing_level != 'public';"

echo "🎉 端口共享初始化完成"
