# Ghost ↔ ConvertKit 整合策略

> 更新日期：2026-01-27

## 整合概覽

```
Ghost 會員系統 ←→ ConvertKit (Kit) 訂閱系統
```

兩個系統透過 n8n 自動化工作流程進行雙向同步。

---

## 目前已完成的工作流程

### 1. Ghost → Kit 同步

**工作流程名稱**：`Ghost <-> Kit`

**觸發方式**：Ghost Webhook（member.added 事件）

**運作邏輯**：
- Ghost 有新會員註冊時，自動加到 ConvertKit 指定的表單
- 使用 Ghost 內建的 Webhook 功能通知 n8n
- n8n 呼叫 ConvertKit API 新增訂閱者

**狀態**：✅ 已啟用

---

### 2. Kit → Ghost 同步

**工作流程名稱**：`Kit → Ghost 會員同步 (輪詢)`

**觸發方式**：每 10 秒輪詢一次

**運作邏輯**：
- 定時呼叫 ConvertKit API 取得所有訂閱者
- 追蹤已處理的訂閱者 ID（使用 n8n 靜態資料）
- 新的已確認訂閱者會同步到 Ghost
- Ghost 中會加上 `Kit-Import` 標籤
- 重複的會員會被 Ghost API 自動忽略（不會發送歡迎信）

**為什麼用輪詢而非 Webhook**：
- ConvertKit 免費帳戶不支援 Webhook 功能
- 輪詢間隔 10 秒對 NAS 和 API 負擔極低

**狀態**：✅ 已啟用

---

### 3. 測試用工作流程

**工作流程名稱**：`[測試] Kit → Ghost API 驗證`

**用途**：手動測試 Ghost API 連接和 JWT 生成

**狀態**：可保留或刪除

---

## 技術細節

### Ghost Admin API 認證

- 使用 JWT Token 進行認證
- Token 由 n8n Code 節點動態生成
- 需要環境變數 `NODE_FUNCTION_ALLOW_BUILTIN=crypto`

### ConvertKit API 認證

- 使用 API Secret 作為 Query Parameter
- API Secret 存放在工作流程中

### 重複處理機制

- Ghost API 返回會員已存在時，工作流程不會失敗（Never Error）
- 使用靜態資料追蹤已處理的訂閱者 ID，避免重複呼叫

---

## 未來可能需要做的事情

### 短期優化

- [ ] **監控與告警**：設定錯誤通知（例如 Telegram 或 Email），當同步失敗時收到警報
- [ ] **執行紀錄清理**：設定 n8n 自動清理舊的執行紀錄，避免佔用空間
- [ ] **輪詢間隔調整**：根據實際需求調整輪詢頻率（目前 10 秒）

### 中期改進

- [ ] **升級 ConvertKit 帳戶**：如果升級到付費帳戶，可以改用 Webhook 方式，更即時
- [ ] **表單標籤同步**：從不同 Kit 表單來的訂閱者，可以在 Ghost 加上不同標籤
- [ ] **雙向同步完整性**：
  - Ghost 會員取消訂閱時，同步到 Kit
  - Kit 訂閱者取消時，同步到 Ghost

### 長期考量

- [ ] **會員資料同步**：同步更多欄位（例如姓名更新、自訂欄位）
- [ ] **付費會員整合**：如果 Ghost 有付費訂閱，考慮與 Kit 的標籤或 Sequence 整合
- [ ] **Analytics 整合**：追蹤訂閱來源的轉換率

---

## 相關資源

### n8n 工作流程

| 工作流程 ID | 名稱 | 狀態 |
|------------|------|------|
| c6RpvarTOfxYL5aEk84Mp | Ghost <-> Kit | 已啟用 |
| b9Qyu4KPLv1ZaeiT | Kit → Ghost 會員同步 (輪詢) | 已啟用 |
| zaHwqghp6VEamvjX | Kit → Ghost 會員同步 | 未啟用（免費帳戶無法使用） |
| p4sFCY6shktqqAkn | [測試] Kit → Ghost API 驗證 | 測試用 |

### 重要設定

| 設定項目 | 值 |
|---------|---|
| Ghost Webhook URL | `https://n8n.startandkeep.com/webhook/ghost-to-kit` |
| Kit Form ID | 8838914 |
| Ghost API 端點 | `https://startandkeep.com/ghost/api/admin/members/` |
| n8n 環境變數 | `NODE_FUNCTION_ALLOW_BUILTIN=crypto` |

---

## 變更歷史

### 2026-01-27（晚間更新）

- **優化 Ghost → Kit 同步**：加入「檢查 Kit 是否已有該訂閱者」邏輯
  - 解決從 Kit 表單訂閱時會收到兩封 Incentive Email 的問題
  - 新增 Check Kit Subscriber 節點（HTTP Request 查詢 Kit API）
  - 新增 If Not Exists in Kit 節點（判斷訂閱者是否存在）
  - 只有 Kit 中不存在的用戶才會訂閱表單

### 2026-01-27

- 從 Make 遷移 Ghost → Kit 同步到 n8n
- 建立 Kit → Ghost 同步工作流程（輪詢方式）
- 設定 n8n 容器環境變數以支援 crypto 模組
- 測試並驗證雙向同步功能

