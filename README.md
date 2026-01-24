# n8n Calendar Sync Project

Google Calendar 子日曆事件同步到主日曆的 n8n 工作流程。

## 功能

- 📅 **輪詢同步**：每 30 秒檢查子日曆更新
- 🔄 **雙向追蹤**：自動建立鏡像事件和元資料連結
- 🎨 **保留格式**：維持原始事件顏色、標題、描述、位置
- ✅ **錯誤恢復**：異常時自動繼續執行
- 📊 **無並發問題**：輪詢架構避免 webhook 並發衝突

## 工作流程

### 子日曆清單
- 佩行程
- 主要行程
- 其他 1-3

### 架構

```
排程觸發器（30秒） → 載入上次同步時間 → 取得更新事件
           ↓
       處理事件 → 依動作分流
           ↓
      ┌─────────────────┐
      ↓     ↓           ↓
     刪除  更新         建立
           ↓     ↓           ↓
           └─────────────────┘
           ↓
     儲存同步時間
```

### 支援的操作

1. **CREATE** - 新事件在子日曆建立 → 在主日曆建立鏡像
2. **UPDATE** - 子日曆事件更新 → 同步到主日曆鏡像
3. **DELETE** - 子日曆事件刪除 → 刪除主日曆鏡像

## 技術細節

- **平台**：n8n
- **API**：Google Calendar API v3
- **語言**：JavaScript（Code 節點）
- **延遲**：30 秒內
- **API 配額消耗**：每天 ~2,880 次查詢（遠低於 Google 限制）

## 文件

- [`docs/problem-analysis.md`](docs/problem-analysis.md) - 問題診斷與初期 webhook 方案分析
- [`docs/new-architecture-design.md`](docs/new-architecture-design.md) - 輪詢架構設計
- [`docs/ui-setup-guide.md`](docs/ui-setup-guide.md) - n8n UI 操作指南
- [`docs/quick-reference.md`](docs/quick-reference.md) - 快速參考

## 設定

### 必要資訊

在 `configs/calendar-mappings.json` 中設定：

```json
{
  "calendars": [
    {
      "id": "calendar-id@group.calendar.google.com",
      "colorId": "10",
      "name": "子日曆名稱"
    }
  ],
  "mainCalendar": "answer4154@gmail.com"
}
```

### n8n 工作流程 ID

- **Polling Workflow**: `Cv4chzBsubStu01w`

## 測試

1. 在子日曆建立測試事件
2. 執行 n8n 工作流程：「Execute Workflow」
3. 檢查主日曆是否出現鏡像事件（應該有對應顏色）

## 故障排除

### 鏡像事件未建立

1. 檢查 n8n 執行日誌
2. 驗證 Google Calendar OAuth2 憑證有效
3. 確認子日曆 ID 正確

### 同步延遲

- 當前設定：30 秒
- 可調整到最快 10 秒（需評估 API 配額）

## 貢獻

問題或改進建議請提交 Issue。

## 作者

鎮羽 蔡 (answer4154@gmail.com)

## 許可

MIT License
