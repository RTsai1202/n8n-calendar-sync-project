# 📘 n8n UI 建立指南：Calendar Sync - Main v2

> **目標**：在 n8n UI 中用拖曳的方式建立新的增量同步工作流程
> **預計時間**：15-20 分鐘
> **難度**：⭐⭐☆☆☆（中等）

---

## 🎯 開始之前

### 你需要準備的東西：
1. ✅ 開啟 n8n：https://n8n.startandkeep.com
2. ✅ 確認 Initialize 工作流程已建立（ID: LS8vhCra91gFdEm0）
3. ✅ 這份指南（保持開啟）

### 建立流程概覽：
```
步驟 1：建立新工作流程
步驟 2：添加 Webhook 節點（拖曳）
步驟 3：添加 Parse Notification 節點（拖曳 + 代碼）
步驟 4：添加 Load Sync Token 節點（拖曳 + 代碼）
步驟 5：添加 Incremental Sync 節點（拖曳 + 設定）⭐核心
步驟 6：添加 Process Changes 節點（拖曳 + 代碼）
步驟 7：添加 Switch 節點（拖曳）
步驟 8：添加 Create/Update/Delete 節點（拖曳 + 設定）
步驟 9：添加 Update Meta 和 Save Token 節點（拖曳）
步驟 10：連接所有節點（拖曳連線）
步驟 11：測試工作流程
```

---

## 📋 步驟 1：建立新工作流程

### 操作：
1. 點擊左上角「➕」按鈕
2. 選擇「New workflow」
3. 工作流程名稱改為：`Calendar Sync - Main v2`

### 為什麼這樣做：
- 新的工作流程代表新的架構
- 舊的工作流程保留作為備份

---

## 📋 步驟 2：添加 Webhook 節點

### 操作：🖱️ **100% 拖曳操作**

1. **添加節點**：
   - 點擊畫布上的 「+」按鈕
   - 搜尋框輸入：`webhook`
   - 選擇：「Webhook」節點

2. **設定參數**（在右側面板）：
   ```
   HTTP Method: POST
   Path: calendar-sync-v2
   ```

3. **為什麼這樣設定**：
   - `POST`：Google Calendar 用 POST 發送 webhook
   - `calendar-sync-v2`：新的 webhook 路徑（避免與舊系統衝突）

4. **📝 記下你的 Webhook URL**：
   ```
   https://n8n.startandkeep.com/webhook/calendar-sync-v2
   ```
   **稍後需要用這個 URL 重新註冊 Google webhook**

### 你的畫布應該長這樣：
```
┌─────────────────────┐
│  Webhook - Calendar │
│     Notification    │
└─────────────────────┘
```

---

## 📋 步驟 3：添加 Parse Notification 節點

### 操作：🖱️ **拖曳** + 💻 **代碼**

1. **添加節點**：
   - 點擊 Webhook 節點右側的 「+」按鈕
   - 搜尋：`code`
   - 選擇：「Code」節點
   - 節點名稱改為：`Parse Notification`

2. **設定參數**：
   ```
   Language: JavaScript
   ```

3. **💻 複製這段代碼** 到 JavaScript 欄位：
   ```javascript
   // 解析 Google Push Notification Headers
   const headers = $input.first().json.headers || {};

   const channelId = headers['x-goog-channel-id'] || '';
   const resourceState = headers['x-goog-resource-state'] || '';
   const channelToken = headers['x-goog-channel-token'] || '';

   // 解析 Token 取得子日曆 ID
   const calendarIdMatch = channelToken.match(/calendarId=([^&]+)/);
   const sourceCalendarId = calendarIdMatch ? decodeURIComponent(calendarIdMatch[1]) : null;

   // 如果是 sync 狀態（首次建立通道的確認），直接返回空
   if (resourceState === 'sync') {
     return [];
   }

   // 如果沒有日曆 ID，跳過
   if (!sourceCalendarId) {
     return [];
   }

   return [{
     json: {
       channelId,
       resourceState,
       sourceCalendarId,
       timestamp: new Date().toISOString()
     }
   }];
   ```

### 為什麼需要這個節點：
- **功能**：從 Google webhook 的 HTTP headers 中提取資訊
- **提取什麼**：
  - `channelId`：識別是哪個通道
  - `sourceCalendarId`：是哪個子日曆有變更
  - `resourceState`：是什麼狀態（sync/exists）
- **為什麼用代碼**：HTTP headers 無法用拖曳處理，必須寫代碼解析

### 你的畫布應該長這樣：
```
┌─────────────┐      ┌─────────────┐
│   Webhook   │─────▶│    Parse    │
│             │      │Notification │
└─────────────┘      └─────────────┘
```

---

## 📋 步驟 4：添加 Load Sync Token 節點

### 操作：🖱️ **拖曳** + 💻 **代碼**

1. **添加節點**：
   - 點擊 Parse Notification 節點右側的 「+」
   - 搜尋：`code`
   - 選擇：「Code」節點
   - 節點名稱改為：`Load Sync Token`

2. **💻 複製這段代碼**：
   ```javascript
   // 從 static data 載入該日曆的 sync token
   const sourceCalendarId = $input.first().json.sourceCalendarId;
   const staticData = $getWorkflowStaticData('global');

   // 檢查是否已初始化
   if (!staticData.syncTokens || !staticData.syncTokens[sourceCalendarId]) {
     throw new Error(`No sync token found for calendar ${sourceCalendarId}. Please run the Initialize workflow first.`);
   }

   const syncToken = staticData.syncTokens[sourceCalendarId];
   const lastSync = staticData.lastSync[sourceCalendarId] || 'Never';

   return [{
     json: {
       ...($input.first().json),
       syncToken: syncToken,
       lastSyncTime: lastSync
     }
   }];
   ```

### 為什麼需要這個節點：
- **功能**：從工作流程記憶體中取出「書籤」（Sync Token）
- **取出什麼**：
  - 上次讀到哪裡的記錄（syncToken）
  - 上次同步時間（lastSync）
- **為什麼重要**：這個「書籤」告訴 Google「只給我從這裡之後的變更」
- **為什麼用代碼**：需要從 workflow static data 讀取，無法用拖曳

### 📊 資料流示意：
```
前一個節點傳來：
{ sourceCalendarId: "b8cca329..." }

↓ 這個節點處理

輸出：
{
  sourceCalendarId: "b8cca329...",
  syncToken: "ABC123...",  ← 新增
  lastSyncTime: "2026-01-24..."  ← 新增
}
```

---

## 📋 步驟 5：添加 Incremental Sync 節點 ⭐**核心**

### 操作：🖱️ **100% 拖曳操作**

1. **添加節點**：
   - 點擊 Load Sync Token 右側的 「+」
   - 搜尋：`http request`
   - 選擇：「HTTP Request」節點
   - 節點名稱改為：`Incremental Sync`

2. **設定參數**（全部用拖曳）：

   **Authentication（認證）**：
   ```
   點擊「Add credentials」
   選擇：Predefined Credential Type
   Credential Type: Google Calendar OAuth2 API
   選擇：Google Calendar account 2（已存在的）
   ```

   **Request（請求）**：
   ```
   Method: GET
   ```

   **URL**（點擊右側的「表達式」圖示 🔧）：
   ```javascript
   https://www.googleapis.com/calendar/v3/calendars/{{ encodeURIComponent($json.sourceCalendarId) }}/events
   ```

   > **為什麼用表達式**：URL 需要動態插入日曆 ID
   > **怎麼用**：點擊 URL 欄位右側的 🔧 圖示，切換到表達式模式

   **Query Parameters（查詢參數）**：
   ```
   點擊「Add Parameter」兩次，添加：

   參數 1:
   Name: syncToken
   Value: [點擊右側 🔧] {{ $json.syncToken }}

   參數 2:
   Name: showDeleted
   Value: true  [直接輸入文字]
   ```

3. **⚙️ 在 Settings 標籤**：
   ```
   On Error: Continue
   ```

   **為什麼**：如果 token 失效，不要讓整個工作流程停止

### 為什麼這是核心節點：
- **這是新架構的關鍵！**
- **舊做法**：每次查詢整個日曆（46+ 個事件）
- **新做法**：用 `syncToken` 參數，只查詢變更的事件（1-2 個）
- **節省**：95% 的 API 調用量！

### 📊 API 調用示意：
```
你的請求：
GET /calendars/xxx/events?syncToken=ABC123&showDeleted=true

Google 回應：
{
  items: [
    { id: "event1", summary: "新事件", ... }  ← 只有變更的！
  ],
  nextSyncToken: "XYZ789"  ← 新的書籤
}
```

### 你的畫布應該長這樣：
```
┌────────┐   ┌───────┐   ┌──────┐   ┌────────────┐
│Webhook │─▶│ Parse │─▶│ Load │─▶│Incremental │
│        │   │       │   │Token │   │   Sync     │
└────────┘   └───────┘   └──────┘   └────────────┘
```

---

## 📋 步驟 6：添加 Process Changes 節點

### 操作：🖱️ **拖曳** + 💻 **代碼**

1. **添加節點**：
   - 點擊 Incremental Sync 右側的 「+」
   - 搜尋：`code`
   - 選擇：「Code」節點
   - 節點名稱改為：`Process Changes`

2. **💻 複製這段代碼**：
   ```javascript
   const calendarColors = {
     'b8cca329113187787bdb3a92b282629cd876b96c6df554fe080480e2adc0085c@group.calendar.google.com': '10',
     '99e65d42d1d82579541b603b5d9ee7230e9c3b4198a61e557de6e72b8627f114@group.calendar.google.com': '11',
     '27ae50e57228753b062a8bada3937433b7289f634f76b40cbfed30df943c66b3@group.calendar.google.com': '4',
     '8c44030dc1d314fbb8c2c795fddb24eab5cad08517f18a7ae43259d1b3abfe0d@group.calendar.google.com': '3',
     'b421d3a5c904f920639eb5a98b9a5f3d64148c26a2376b279e2e56d2c6f857c0@group.calendar.google.com': '1'
   };

   const MAIN_CALENDAR_ID = 'answer4154@gmail.com';
   const sourceCalendarId = $('Parse Notification').first().json.sourceCalendarId;

   // 從 HTTP Response 取得事件列表和新的 sync token
   const responseData = $input.first().json;
   const changedEvents = responseData.items || [];
   const nextSyncToken = responseData.nextSyncToken;

   const results = [];

   for (const event of changedEvents) {
     if (!event.id) continue;

     // 檢查是否被用戶刪除（黑名單）
     const userDeleted = event.extendedProperties?.private?.gsync2_userDeleted === 'true';
     if (userDeleted) continue;

     const isCancelled = event.status === 'cancelled';
     const colorId = calendarColors[sourceCalendarId] || '1';
     const mirrorEventId = event.extendedProperties?.private?.gsync2_mirrorEventId || null;

     let action = null;

     // 判斷操作類型
     if (isCancelled && mirrorEventId) {
       action = 'delete';
     } else if (isCancelled && !mirrorEventId) {
       continue; // 已刪除且沒有鏡像，忽略
     } else if (!isCancelled && mirrorEventId) {
       action = 'update';
     } else if (!isCancelled && !mirrorEventId) {
       action = 'create';
     }

     if (!action) continue;

     results.push({
       json: {
         action,
         childEventId: event.id,
         mirrorEventId,
         summary: event.summary || '(No Title)',
         description: event.description || '',
         location: event.location || '',
         start: event.start,
         end: event.end,
         colorId,
         sourceCalendarId,
         targetCalendarId: MAIN_CALENDAR_ID,
         nextSyncToken: nextSyncToken
       }
     });
   }

   return results;
   ```

### 為什麼需要這個節點：
- **功能**：判斷每個變更的事件應該怎麼處理
- **判斷邏輯**：
  ```
  事件被刪除 + 有鏡像 → delete（刪除主日曆的鏡像）
  事件正常 + 有鏡像 → update（更新主日曆的鏡像）
  事件正常 + 沒鏡像 → create（建立新鏡像）
  事件被刪除 + 沒鏡像 → 忽略
  ```
- **為什麼用代碼**：複雜的邏輯判斷，無法用拖曳完成

### 📊 資料流示意：
```
輸入（從 Incremental Sync）：
{
  items: [
    { id: "abc", summary: "新事件", status: "confirmed", ... }
  ],
  nextSyncToken: "XYZ789"
}

↓ 這個節點處理

輸出：
[
  {
    action: "create",
    childEventId: "abc",
    summary: "新事件",
    colorId: "10",
    ...
  }
]
```

---

## 📋 步驟 7：添加 Switch 節點（分流）

### 操作：🖱️ **100% 拖曳操作**

1. **添加節點**：
   - 點擊 Process Changes 右側的 「+」
   - 搜尋：`switch`
   - 選擇：「Switch」節點
   - 節點名稱改為：`Route by Action`

2. **設定規則**（點擊「Add Routing Rule」3 次）：

   **規則 1（Delete）**：
   ```
   Mode: Rules

   Conditions:
   - 點擊「Add Condition」
   - Field: [點擊 🔧 切換表達式] {{ $json.action }}
   - Condition: Equal
   - Value: delete

   Output: [勾選] Rename Output
   Output Name: delete
   ```

   **規則 2（Update）**：
   ```
   Conditions:
   - Field: [表達式] {{ $json.action }}
   - Condition: Equal
   - Value: update

   Output Name: update
   ```

   **規則 3（Create）**：
   ```
   Conditions:
   - Field: [表達式] {{ $json.action }}
   - Condition: Equal
   - Value: create

   Output Name: create
   ```

### 為什麼需要這個節點：
- **功能**：根據 `action` 欄位分流
- **分流到**：
  - `delete` → Delete Mirror Event 節點
  - `update` → Update Mirror Event 節點
  - `create` → Create Mirror Event 節點
- **為什麼這樣做**：不同操作需要呼叫不同的 Google Calendar API

### 📊 視覺化：
```
              ┌─────────────┐
              │   Switch    │
              │(Route by    │
              │  Action)    │
              └──────┬──────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
    delete        update       create
        │            │            │
        ▼            ▼            ▼
    [刪除]        [更新]        [建立]
```

---

## 📋 步驟 8A：添加 Delete Mirror Event 節點

### 操作：🖱️ **100% 拖曳操作**

1. **添加節點**：
   - 點擊 Switch 節點**下方**的 「+」（delete 輸出）
   - 搜尋：`google calendar`
   - 選擇：「Google Calendar」節點
   - 節點名稱改為：`Delete Mirror Event`

2. **設定參數**（全部拖曳）：

   **Credential（認證）**：
   ```
   選擇：Google Calendar account 2
   ```

   **Resource（資源）**：
   ```
   選擇：Event
   ```

   **Operation（操作）**：
   ```
   選擇：Delete
   ```

   **Calendar（日曆）**：
   ```
   From List: 選擇你的主日曆
   或
   By ID: answer4154@gmail.com
   ```

   **Event ID（事件 ID）**：
   ```
   [點擊右側 🔧 切換表達式]
   {{ $json.mirrorEventId }}
   ```

   **為什麼用表達式**：Event ID 是動態的，從前一個節點傳來

   **Options（選項）**：
   ```
   展開 Options
   Send Updates: None
   ```

3. **⚙️ 在 Settings 標籤**：
   ```
   On Error: Continue
   ```

### 為什麼需要這個節點：
- **功能**：刪除主日曆的鏡像事件
- **觸發時機**：當子日曆的事件被刪除時
- **為什麼用 On Error Continue**：如果鏡像已經不存在，不要讓工作流程失敗

---

## 📋 步驟 8B：添加 Update Mirror Event 節點

### 操作：🖱️ **100% 拖曳操作**

1. **添加節點**：
   - 點擊 Switch 節點**中間**的 「+」（update 輸出）
   - 搜尋：`google calendar`
   - 選擇：「Google Calendar」節點
   - 節點名稱改為：`Update Mirror Event`

2. **設定參數**：

   **Credential**：
   ```
   Google Calendar account 2
   ```

   **Resource**：
   ```
   Event
   ```

   **Operation**：
   ```
   Update
   ```

   **Calendar**：
   ```
   answer4154@gmail.com
   ```

   **Event ID**：
   ```
   [表達式] {{ $json.mirrorEventId }}
   ```

   **Fields to Update（要更新的欄位）**：

   點擊「Add Field」，依序添加：

   ```
   Summary: [表達式] {{ $json.summary }}
   Description: [表達式] {{ $json.description }}
   Location: [表達式] {{ $json.location }}
   Start: [表達式] {{ $json.start.dateTime || $json.start.date }}
   End: [表達式] {{ $json.end.dateTime || $json.end.date }}
   Color: [表達式] {{ $json.colorId }}
   ```

   **為什麼用這些欄位**：
   - 同步事件的基本資訊（標題、描述、位置、時間）
   - **Color**：這是關鍵！不同子日曆用不同顏色

3. **⚙️ Settings**：
   ```
   On Error: Continue
   ```

---

## 📋 步驟 8C：添加 Create Mirror Event 節點

### 操作：🖱️ **100% 拖曳操作**

1. **添加節點**：
   - 點擊 Switch 節點**上方**的 「+」（create 輸出）
   - 搜尋：`google calendar`
   - 選擇：「Google Calendar」節點
   - 節點名稱改為：`Create Mirror Event`

2. **設定參數**：

   **Credential**：
   ```
   Google Calendar account 2
   ```

   **Resource**：
   ```
   Event
   ```

   **Operation**：
   ```
   Create
   ```

   **Calendar**：
   ```
   answer4154@gmail.com
   ```

   **Start（必填）**：
   ```
   [表達式] {{ $json.start.dateTime || $json.start.date }}
   ```

   **End（必填）**：
   ```
   [表達式] {{ $json.end.dateTime || $json.end.date }}
   ```

   **Additional Fields（點擊展開）**：

   添加以下欄位：
   ```
   Summary: [表達式] {{ $json.summary }}
   Description: [表達式] {{ $json.description }}
   Location: [表達式] {{ $json.location }}
   Color: [表達式] {{ $json.colorId }}
   ```

3. **⚙️ Settings**：
   ```
   On Error: Continue
   ```

### 你的畫布應該長這樣：
```
                    ┌──────────────┐
                 ┌─▶│   Delete     │
                 │  │ Mirror Event │
                 │  └──────────────┘
┌──────────┐    │
│  Switch  │────┼─▶┌──────────────┐
│ (Route)  │    │  │   Update     │
└──────────┘    │  │ Mirror Event │
                │  └──────────────┘
                │
                └─▶┌──────────────┐
                   │   Create     │
                   │ Mirror Event │
                   └──────────────┘
```

---

## 📋 步驟 9A：添加 Update Child Event Meta 節點

### 操作：🖱️ **拖曳** + 💻 **代碼**

1. **添加節點**：
   - 點擊 Create Mirror Event 右側的 「+」
   - 搜尋：`http request`
   - 選擇：「HTTP Request」節點
   - 節點名稱改為：`Update Child Event Meta`

2. **設定參數**：

   **Authentication**：
   ```
   Predefined Credential Type
   Google Calendar OAuth2 API
   Google Calendar account 2
   ```

   **Method**：
   ```
   PATCH
   ```

   **URL**（表達式）：
   ```javascript
   https://www.googleapis.com/calendar/v3/calendars/{{ encodeURIComponent($json.sourceCalendarId) }}/events/{{ $json.childEventId }}
   ```

   **Send Body**：
   ```
   勾選：Yes
   Body Content Type: JSON
   ```

   **JSON Body**（表達式）：
   ```javascript
   {{ JSON.stringify({ extendedProperties: { private: { gsync2_sourceCalendar: $json.sourceCalendarId, gsync2_mirrorEventId: $json.id } } }) }}
   ```

### 為什麼需要這個節點：
- **功能**：在子日曆事件中記錄「我已經在主日曆建立鏡像了」
- **記錄什麼**：
  - `gsync2_mirrorEventId`：主日曆鏡像的 ID
  - `gsync2_sourceCalendar`：來源日曆 ID
- **為什麼重要**：下次更新時才知道要更新哪個鏡像

---

## 📋 步驟 9B：添加 Save New Sync Token 節點

### 操作：🖱️ **拖曳** + 💻 **代碼**

1. **添加節點**：
   - 你需要連接 3 個操作節點的輸出到這個節點
   - 先添加節點：點擊畫布空白處的 「+」
   - 搜尋：`code`
   - 選擇：「Code」節點
   - 節點名稱改為：`Save New Sync Token`
   - 位置：放在畫布最右側

2. **💻 複製這段代碼**：
   ```javascript
   // 儲存新的 sync token
   const sourceCalendarId = $('Parse Notification').first().json.sourceCalendarId;
   const nextSyncToken = $input.first().json.nextSyncToken;

   if (!nextSyncToken) {
     // 如果沒有新的 token，不更新
     return $input.all();
   }

   const staticData = $getWorkflowStaticData('global');
   const now = new Date().toISOString();

   staticData.syncTokens[sourceCalendarId] = nextSyncToken;
   staticData.lastSync[sourceCalendarId] = now;

   return [{
     json: {
       status: 'success',
       syncTokenUpdated: true,
       calendar: sourceCalendarId.substring(0, 8) + '...',
       updateTime: now
     }
   }];
   ```

3. **連接節點**（重要！）：
   - **從 Delete Mirror Event** 拖曳連線到 Save New Sync Token
   - **從 Update Mirror Event** 拖曳連線到 Save New Sync Token
   - **從 Update Child Event Meta** 拖曳連線到 Save New Sync Token

### 為什麼需要這個節點：
- **功能**：更新「書籤」到新位置
- **更新什麼**：把 Google 給的 `nextSyncToken` 存起來
- **為什麼重要**：下次 webhook 才能從新位置開始讀
- **為什麼連接 3 個節點**：不管是 create/update/delete，最後都要更新 token

### 📊 視覺化完整流程：
```
                    ┌──────────┐
                 ┌─▶│  Delete  │─┐
                 │  └──────────┘ │
┌────────┐      │  ┌──────────┐ │   ┌────────┐
│ Switch │──────┼─▶│  Update  │─┼──▶│  Save  │
└────────┘      │  └──────────┘ │   │ Token  │
                │  ┌──────────┐ │   └────────┘
                └─▶│  Create  │─┤
                   └──────────┘ │
                         │      │
                         ▼      │
                   ┌──────────┐ │
                   │Update Meta◀┘
                   └──────────┘
```

---

## 📋 步驟 10：最終檢查和連接

### 檢查清單：

1. **節點數量**：
   - [ ] Webhook - Calendar Notification
   - [ ] Parse Notification
   - [ ] Load Sync Token
   - [ ] Incremental Sync
   - [ ] Process Changes
   - [ ] Route by Action (Switch)
   - [ ] Delete Mirror Event
   - [ ] Update Mirror Event
   - [ ] Create Mirror Event
   - [ ] Update Child Event Meta
   - [ ] Save New Sync Token

   **總計：11 個節點**

2. **連接檢查**：
   ```
   Webhook → Parse → Load → Incremental → Process → Switch
                                                       ├─▶ Delete ──┐
                                                       ├─▶ Update ──┼─▶ Save Token
                                                       └─▶ Create ──┤
                                                                    │
                                                                    ▼
                                                            Update Child Meta
   ```

3. **所有表達式欄位**（用 {{ }} 包起來的）：
   - [ ] Incremental Sync 的 URL
   - [ ] Incremental Sync 的 syncToken 參數
   - [ ] Switch 的 3 個條件
   - [ ] Delete/Update/Create 的各種欄位
   - [ ] Update Child Meta 的 URL 和 Body

---

## 📋 步驟 11：儲存並準備測試

### 操作：

1. **儲存工作流程**：
   - 按 `Ctrl + S` (Windows) 或 `Cmd + S` (Mac)
   - 或點擊右上角「Save」按鈕

2. **啟動工作流程**：
   - **先不要啟動！**
   - 我們需要先執行 Initialize 工作流程

3. **記下新的 Webhook URL**：
   ```
   https://n8n.startandkeep.com/webhook/calendar-sync-v2
   ```

---

## ✅ 完成建立！

恭喜！你已經完成新工作流程的建立。

### 📊 對比舊架構：

| 項目 | 舊架構 | 新架構 |
|------|--------|--------|
| Webhook URL | /webhook/calendar-sync | /webhook/calendar-sync-v2 |
| 每次查詢事件數 | 46+ 個 | 1-2 個 ⭐ |
| 使用 Sync Token | ❌ | ✅ ⭐ |
| API 效率 | 低 | 高 ⭐ |

---

## 🔧 下一步

完成建立後，請告訴我，我們會：

1. **先執行 Initialize 工作流程**（取得 Sync Token）
2. **測試新工作流程**（模擬 webhook）
3. **重新註冊 Google webhook**（使用新 URL）
4. **停用舊工作流程**
5. **啟動新工作流程**

**準備好了嗎？** 🚀
