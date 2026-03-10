#!/bin/bash
# 等待 Coder 就绪，为所有模板开启端口共享 (max_port_share_level=public)
set -e

CODER_URL="http://coder:7080"
MAX_WAIT=120

echo "⏳ 等待 Coder 就绪..."
for i in $(seq 1 $MAX_WAIT); do
  if curl -sf "$CODER_URL/api/v2/buildinfo" > /dev/null 2>&1; then
    echo "✅ Coder 已就绪"
    break
  fi
  if [ "$i" = "$MAX_WAIT" ]; then
    echo "❌ 等待 Coder 超时"
    exit 1
  fi
  sleep 1
done

# 使用 coder CLI 登录并获取 token
echo "🔑 登录 Coder..."
TOKEN=$(curl -sf -X POST "$CODER_URL/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | grep -o '"session_token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo "⚠️ 无法获取 token（可能使用 OAuth 登录），跳过初始化"
  exit 0
fi

# 获取所有模板并设置 max_port_share_level=public
echo "🔧 设置所有模板端口共享为 public..."
TEMPLATES=$(curl -sf -H "Coder-Session-Token: $TOKEN" "$CODER_URL/api/v2/templates")
echo "$TEMPLATES" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | while read -r TEMPLATE_ID; do
  RESULT=$(curl -sf -X PATCH \
    -H "Coder-Session-Token: $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"max_port_share_level": "public"}' \
    "$CODER_URL/api/v2/templates/$TEMPLATE_ID")
  NAME=$(echo "$RESULT" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "  ✅ $NAME -> public"
done

echo "🎉 端口共享初始化完成"
