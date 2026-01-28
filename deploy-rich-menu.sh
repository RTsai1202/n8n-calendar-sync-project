#!/bin/bash

# LINE Rich Menu 一鍵部署腳本
# 此腳本會自動創建並啟用 Rich Menu

set -e

echo "🚀 開始部署 LINE Rich Menu..."

# LINE Channel Access Token
ACCESS_TOKEN="08rtpZLZGYFeIkgeFarEoQJ0vGxf0o5oNwtQZv/YAweBoLbWdwx6AY90BmpExgm2BU77wLq0xlKFk9HW4Lq/tmsmxCnvRrA3FdF+lWzt/Gf5+/fsxtFIgY8YO22dXb31UwHbncFqIjTr48LHBu1GqAdB04t89/1O/w1cDnyilFU="

# 取得當前月份（用於動態按鈕）
CURRENT_MONTH=$(date +%m | sed 's/^0//')
NEXT_MONTH=$(date -v+1m +%m | sed 's/^0//')

echo "📅 當前月份: ${CURRENT_MONTH}月"
echo "📅 下個月份: ${NEXT_MONTH}月"

# 步驟 1: 創建 Rich Menu
echo ""
echo "📝 步驟 1/4: 創建 Rich Menu 結構..."

RICHMENU_RESPONSE=$(curl -s -X POST https://api.line.me/v2/bot/richmenu \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "size": {
      "width": 2500,
      "height": 843
    },
    "selected": true,
    "name": "行程查詢選單",
    "chatBarText": "查詢選單",
    "areas": [
      {
        "bounds": {
          "x": 0,
          "y": 0,
          "width": 625,
          "height": 843
        },
        "action": {
          "type": "message",
          "label": "今天",
          "text": "今天"
        }
      },
      {
        "bounds": {
          "x": 625,
          "y": 0,
          "width": 625,
          "height": 843
        },
        "action": {
          "type": "message",
          "label": "明天",
          "text": "明天"
        }
      },
      {
        "bounds": {
          "x": 1250,
          "y": 0,
          "width": 625,
          "height": 843
        },
        "action": {
          "type": "message",
          "label": "這個月",
          "text": "'"${CURRENT_MONTH}"'月"
        }
      },
      {
        "bounds": {
          "x": 1875,
          "y": 0,
          "width": 625,
          "height": 843
        },
        "action": {
          "type": "message",
          "label": "下個月",
          "text": "'"${NEXT_MONTH}"'月"
        }
      }
    ]
  }')

RICHMENU_ID=$(echo $RICHMENU_RESPONSE | grep -o '"richMenuId":"[^"]*"' | cut -d'"' -f4)

if [ -z "$RICHMENU_ID" ]; then
    echo "❌ 錯誤: 無法創建 Rich Menu"
    echo "回應: $RICHMENU_RESPONSE"
    exit 1
fi

echo "✅ Rich Menu 已創建，ID: $RICHMENU_ID"

# 步驟 2: 檢查圖片是否存在
echo ""
echo "🖼️  步驟 2/4: 檢查 Rich Menu 圖片..."

IMAGE_PATH="./line-rich-menu.png"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "⚠️  警告: 找不到 line-rich-menu.png"
    echo ""
    echo "請先執行以下步驟："
    echo "1. 在瀏覽器中開啟 rich-menu-generator.html"
    echo "2. 下載生成的圖片為 line-rich-menu.png"
    echo "3. 將圖片放在與此腳本相同的目錄下"
    echo ""
    echo "📍 當前目錄: $(pwd)"
    echo ""
    read -p "按 Enter 繼續（如果你已經準備好圖片）或 Ctrl+C 取消..."
fi

# 步驟 3: 上傳圖片
echo ""
echo "⬆️  步驟 3/4: 上傳 Rich Menu 圖片..."

UPLOAD_RESPONSE=$(curl -s -X POST \
  "https://api-data.line.me/v2/bot/richmenu/${RICHMENU_ID}/content" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: image/png" \
  --data-binary "@${IMAGE_PATH}")

if [ -n "$UPLOAD_RESPONSE" ] && echo "$UPLOAD_RESPONSE" | grep -q "error"; then
    echo "❌ 錯誤: 圖片上傳失敗"
    echo "回應: $UPLOAD_RESPONSE"
    exit 1
fi

echo "✅ 圖片已上傳"

# 步驟 4: 設定為預設選單
echo ""
echo "🔗 步驟 4/4: 設定為所有用戶的預設選單..."

DEFAULT_RESPONSE=$(curl -s -X POST \
  "https://api.line.me/v2/bot/user/all/richmenu/${RICHMENU_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}")

if [ -n "$DEFAULT_RESPONSE" ] && echo "$DEFAULT_RESPONSE" | grep -q "error"; then
    echo "❌ 錯誤: 無法設定預設選單"
    echo "回應: $DEFAULT_RESPONSE"
    exit 1
fi

echo "✅ 已設定為預設選單"

# 完成
echo ""
echo "════════════════════════════════════════"
echo "✨ Rich Menu 部署完成！"
echo "════════════════════════════════════════"
echo ""
echo "📱 請開啟 LINE 官方帳號聊天室確認"
echo "🎯 Rich Menu ID: $RICHMENU_ID"
echo ""
echo "測試方式："
echo "1. 點擊底部的選單按鈕"
echo "2. 確認是否正確觸發查詢"
echo ""
echo "如需移除 Rich Menu，執行："
echo "curl -X DELETE https://api.line.me/v2/bot/richmenu/${RICHMENU_ID} \\"
echo "  -H \"Authorization: Bearer ${ACCESS_TOKEN}\""
echo ""
