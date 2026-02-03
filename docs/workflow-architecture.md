# n8n Workflow Architecture

更新日期：2026-02-03

## 目標

本專案已重整為 3 個清楚的功能域，並依「只保留正在使用流程」原則清理線上 instance。

「在用」定義：`active=true` 且在保留白名單內。

## Domain 分層

### 1) calendar-sync

- Workflow ID: `Cv4chzBsubStu01w`
- Name: `Calendar Sync - Polling`
- 觸發型態: Schedule + Manual
- 責任邊界:
  - 輪詢子日曆事件
  - 依 create / update / delete 同步到主日曆
  - 維護 last sync time

### 2) membership-sync

- Workflow ID: `c6RpvarTOfxYL5aEk84Mp`
- Name: `Ghost 註冊 -> Kit 自動確認`
- 觸發型態: Webhook
- 責任邊界:
  - 接收 Ghost 註冊事件
  - 判斷 Kit 是否已存在
  - 不重複建立訂閱者

- Workflow ID: `b9Qyu4KPLv1ZaeiT`
- Name: `Kit → Ghost 會員同步 (輪詢)`
- 觸發型態: Schedule
- 責任邊界:
  - 輪詢 Kit 訂閱者
  - 過濾已處理/無效資料
  - 寫入 Ghost member

### 3) calendar-assistant

- Workflow ID: `v2C7zLs5PLMiuZRy`
- Name: `LINE 行程查詢 Bot (for Heptabase journal)`
- 觸發型態: Webhook + Schedule
- 時區設定: `Asia/Taipei`（確保每日推送為台灣時間 06:00）
- 責任邊界:
  - 回覆 LINE 行程查詢（即時）
  - 每日固定時間推播行程摘要

## Repository 對應

```text
workflows/
  prod/
    calendar-sync/
      Cv4chzBsubStu01w__calendar-sync-polling.json
    membership-sync/
      c6RpvarTOfxYL5aEk84Mp__ghost-to-kit-webhook.json
      b9Qyu4KPLv1ZaeiT__kit-to-ghost-polling.json
    calendar-assistant/
      v2C7zLs5PLMiuZRy__line-calendar-assistant.json
  manifests/
    workflows.catalog.json
```

## 已永久刪除流程（2026-02-03）

- `6cKAhGmwShcKNI7xmoFTB`
- `CqMLONcdFzucYYB1`
- `F2XnKl10Yj0_SHU4_3K7f`
- `Fh4yc0w0Amz5v-UiFPDCJ`
- `H72HCPwFmEZi2DE80yDaN`
- `LS8vhCra91gFdEm0`
- `Nt75QRbLQsMsBvmrT_rCo`
- `_Wtz0LFjppZ4kA71MXehX`
- `bQpL1sqg1lUtyxAJ2GbNQ`
- `iTiR3K3V0FX8acQE`
- `or_FR8VIHqDfWpYwl8cNo`
- `p4sFCY6shktqqAkn`
- `uRhCccIVAxMCDZk4UXe8u`
- `zaHwqghp6VEamvjX`

## 備註

- `workflows/prod` 內的 JSON 為架構快照（structure export），用於維運、審核、邊界管理。
- 線上行為來源以 n8n instance 為準，repo 作為可追蹤的結構索引。
