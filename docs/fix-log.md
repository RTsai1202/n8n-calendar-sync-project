# n8n Calendar Sync 修復紀錄

## 2026-01-26 修復：Process Events 只處理第一個日曆

### 問題描述

**原始問題程式碼**：
```javascript
const responseData = $input.first().json;  // ← 只讀取第一個項目！
const events = responseData.items || [];
```

**影響**：
- Load Last Sync Time 輸出 5 個日曆配置
- Get Updated Events 返回 5 個 API 回應
- Process Events 只處理第 1 個回應，忽略其他 4 個
- 測試事件可能在其他日曆，永遠不會被處理

### 解決方案

改用 `$input.all()` 遍歷所有輸入項目，並使用 `pairedItem` 追蹤對應的日曆配置：

```javascript
const allInputs = $input.all();
const results = [];

for (let i = 0; i < allInputs.length; i++) {
  const responseData = allInputs[i].json;
  const events = responseData.items || [];

  for (const event of events) {
    results.push({
      json: { /* event data */ },
      pairedItem: { item: i }  // ← 追蹤對應的日曆配置
    });
  }
}

return results;
```

### 執行成功的證據（執行紀錄 #4437）

| 節點 | 輸入 | 輸出 | 狀態 |
|-----|-----|-----|-----|
| Get Updated Events | 5 | 5 | ✅ 抓到新事件「蔡行程」 |
| Process Events | 5 | 1 | ✅ 正確輸出 create action |
| Check Mirror Exists | 1 | 1 | ✅ items: [] (無現有鏡像) |
| Filter New Only | 1 | 1 | ✅ 走 true 分支 |
| Create Mirror Event | 1 | 1 | ✅ 建立鏡像 ID: 72lrthkpjis1ftlp3005ucd5sc |
| Update Child Event Meta | 1 | 1 | ✅ 設置 gsync2_mirrorEventId |

### 關鍵修正

1. **遍歷所有輸入**：從 `$input.first()` 改為 `$input.all()` 迴圈
2. **保持項目對應**：使用 `pairedItem: { item: i }` 讓後續節點能正確引用來源日曆配置
3. **正確輸出格式**：返回 `{ json: {...}, pairedItem: {...} }` 格式的陣列

---

## 2026-01-26 修復：Code 節點 API 呼叫問題

### 問題描述

**錯誤訊息**：
```
The function "helpers.httpRequestWithAuthentication" is not supported in the Code Node
```

**原因**：n8n 的 Code 節點不支援 `this.helpers.httpRequestWithAuthentication` 函數。原本的設計是在 Code 節點中直接呼叫 Google Calendar API 來建立鏡像事件，但這個方法在 n8n 中無法使用。

### 解決方案

將原本的 `Create Mirror If Not Exists` Code 節點拆分成多個獨立的節點：

| 原本結構 | 修改後結構 |
|---------|-----------|
| `Route by Action` → `Create Mirror If Not Exists` (Code) → `Update Child Event Meta` | `Route by Action` → `Check Mirror Exists` → `Filter New Only` → `Create Mirror Event` → `Update Child Event Meta` |

### 新增/修改的節點

1. **Check Mirror Exists** (HTTP Request)
   - 功能：查詢主日曆是否已存在對應的鏡像事件
   - 使用 `privateExtendedProperty` 參數搜尋 `gsync2_childEventId`

2. **Filter New Only** (IF)
   - 功能：過濾只處理尚未建立鏡像的事件
   - 條件：`$json.items.length === 0`

3. **Create Mirror Event** (HTTP Request)
   - 功能：在主日曆建立新的鏡像事件
   - 包含 `extendedProperties.private` 用於追蹤來源

4. **Update Child Event Meta** (HTTP Request) - 已更新
   - 功能：更新子日曆事件的 metadata，記錄鏡像事件 ID
   - 更新了 URL 和 body 的資料引用路徑

### 修復後的 Create 分支流程

```
Route by Action (output 2: create)
    ↓
Check Mirror Exists (HTTP GET - 查詢現有鏡像)
    ↓
Filter New Only (IF - items.length === 0)
    ↓ (true branch)
Create Mirror Event (HTTP POST - 建立鏡像事件)
    ↓
Update Child Event Meta (HTTP PATCH - 更新來源事件 metadata)
    ↓
Save Sync Time
```

### 驗證結果

- ✅ Workflow 執行狀態：全部成功
- ✅ 每 30 秒自動執行
- ✅ 新事件可正常同步到主日曆

### 相關 Workflow

- **Workflow ID**: `Cv4chzBsubStu01w`
- **Workflow 名稱**: Calendar Sync - Polling

---

*修復完成時間：2026-01-26 07:37 (Asia/Taipei)*

---

## 2026-02-03 重整：Workflow 架構清理 + LINE 排程時區修正

### 今天完成的修正

1. **線上工作流清理**
   - 依「只留在用流程」原則，保留 4 條 active workflow：
     - `Cv4chzBsubStu01w`（Calendar Sync - Polling）
     - `c6RpvarTOfxYL5aEk84Mp`（Ghost 註冊 -> Kit 自動確認）
     - `b9Qyu4KPLv1ZaeiT`（Kit → Ghost 會員同步）
     - `v2C7zLs5PLMiuZRy`（LINE 行程查詢 Bot）
   - 永久刪除 14 條 inactive/archived 舊流程。

2. **Repo 架構重整**
   - 將 workflow JSON 重新分層到：
     - `workflows/prod/calendar-sync/`
     - `workflows/prod/membership-sync/`
     - `workflows/prod/calendar-assistant/`
   - 新增 `workflows/manifests/workflows.catalog.json` 作為 workflow 索引。
   - 新增 `docs/workflow-architecture.md` 供維運與責任邊界查閱。

3. **LINE 每日推送時間修正**
   - 問題：預期 06:00 推送，實際在 19:00 觸發。
   - 根因：workflow 未明確設定時區，Cron `0 6 * * *` 被以 instance 預設時區解讀。
   - 修正：將 workflow `v2C7zLs5PLMiuZRy` settings 設為 `timezone: Asia/Taipei`。

### 值得紀錄的問題與經驗

1. **Cron 正確不代表排程正確**
   - `0 6 * * *` 必須搭配 workflow timezone，否則在跨時區部署會偏移。

2. **清理策略要先用白名單**
   - 先定義「保留白名單」，再刪除其餘流程，可有效降低誤刪風險。

3. **結構快照與完整備份用途不同**
   - `structure` 匯出適合架構治理與對照，不等於可完整還原的 full backup。

### 驗收結果

- `active=true`：4 條（符合預期）
- `active=false`：0 條（符合預期）
- 4 條保留流程皆有近期成功執行紀錄。

*修復完成時間：2026-02-03 (Asia/Taipei)*
