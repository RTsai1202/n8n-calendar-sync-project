# 新架構設計：增量同步（Sync Token）

## 📐 設計日期
2026-01-24

## 🎯 設計目標

1. **減少 API 調用 90%+**：只查詢變更的事件
2. **縮短執行時間 90%+**：從 2-3 分鐘降到 < 5 秒
3. **消除 quota 錯誤**：大幅降低 API 使用量
4. **保持即時性**：webhook 觸發後立即處理

## 🏗️ 架構概覽

### 雙工作流程設計

```
┌─────────────────────────────────────────────────────────┐
│  Workflow 1: Calendar Sync - Initialize (初始化)        │
│  用途：為每個子日曆取得初始 Sync Token                   │
│  觸發：手動執行（只需執行一次）                          │
└─────────────────────────────────────────────────────────┘
                        ↓ 儲存 Sync Tokens
┌─────────────────────────────────────────────────────────┐
│  Workflow Static Data (持久化儲存)                       │
│  {                                                       │
│    syncTokens: { ... },                                 │
│    lastSync: { ... }                                    │
│  }                                                       │
└─────────────────────────────────────────────────────────┘
                        ↓ 讀取 Sync Tokens
┌─────────────────────────────────────────────────────────┐
│  Workflow 2: Calendar Sync - Main v2 (主同步)           │
│  用途：處理 webhook 並增量同步                           │
│  觸發：Google Calendar Webhook                          │
└─────────────────────────────────────────────────────────┘
```

---

## 📋 Workflow 1: Calendar Sync - Initialize

### 目的
為每個子日曆取得初始 Sync Token，儲存到 workflow static data

### 節點設計

```
[Manual Trigger / Schedule]
  ↓
[Load Calendar Config]
  Code Node
  - 讀取 5 個子日曆 ID
  - 產生5個輸出項目
  ↓
[Get Initial Sync Token]
  HTTP Request Node (×5 平行處理)
  - API: GET /calendars/{calendarId}/events
  - 參數: maxResults=1
  - 取得 response.nextSyncToken
  ↓
[Save Sync Tokens]
  Code Node
  - 儲存到 workflow static data
  - 結構：syncTokens[calendarId] = token
  - 記錄時間：lastSync[calendarId] = now
```

### Load Calendar Config 節點代碼

```javascript
// 讀取子日曆配置
const childCalendars = [
  'b8cca329113187787bdb3a92b282629cd876b96c6df554fe080480e2adc0085c@group.calendar.google.com',
  '99e65d42d1d82579541b603b5d9ee7230e9c3b4198a61e557de6e72b8627f114@group.calendar.google.com',
  '27ae50e57228753b062a8bada3937433b7289f634f76b40cbfed30df943c66b3@group.calendar.google.com',
  '8c44030dc1d314fbb8c2c795fddb24eab5cad08517f18a7ae43259d1b3abfe0d@group.calendar.google.com',
  'b421d3a5c904f920639eb5a98b9a5f3d64148c26a2376b279e2e56d2c6f857c0@group.calendar.google.com'
];

const results = [];

for (const calId of childCalendars) {
  results.push({
    json: {
      calendarId: calId,
      apiUrl: `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calId)}/events`
    }
  });
}

return results;
```

### Get Initial Sync Token 節點配置

**HTTP Request Node:**
```
Method: GET
URL: ={{ $json.apiUrl }}
Authentication: googleCalendarOAuth2Api
Query Parameters:
  - maxResults: 1
  - singleEvents: true
```

### Save Sync Tokens 節點代碼

```javascript
// 儲存所有日曆的 Sync Token
const staticData = $getWorkflowStaticData('global');

// 初始化結構
if (!staticData.syncTokens) {
  staticData.syncTokens = {};
}
if (!staticData.lastSync) {
  staticData.lastSync = {};
}

const now = new Date().toISOString();
const summary = [];

// 處理每個日曆的回應
for (const item of $input.all()) {
  const calendarId = item.json.calendarId;
  const nextSyncToken = item.json.nextSyncToken;

  if (nextSyncToken) {
    staticData.syncTokens[calendarId] = nextSyncToken;
    staticData.lastSync[calendarId] = now;
    summary.push({
      calendar: calendarId.substring(0, 8) + '...',
      status: 'success',
      syncToken: nextSyncToken.substring(0, 20) + '...'
    });
  } else {
    summary.push({
      calendar: calendarId.substring(0, 8) + '...',
      status: 'failed',
      error: 'No sync token received'
    });
  }
}

return [{
  json: {
    initialized: summary.filter(s => s.status === 'success').length,
    failed: summary.filter(s => s.status === 'failed').length,
    details: summary,
    timestamp: now
  }
}];
```

---

## 📋 Workflow 2: Calendar Sync - Main v2

### 目的
接收 webhook，使用 Sync Token 增量查詢變更的事件，同步到主日曆

### 節點設計

```
[Webhook - Calendar Notification]
  ↓
[Parse Notification]
  提取：sourceCalendarId, channelId, resourceState
  ↓
[Load Sync Token]
  從 static data 讀取該日曆的 syncToken
  ↓
[Incremental Sync] ⭐核心節點
  HTTP Request
  使用 syncToken 查詢增量變更
  只返回變更的事件（1-2個）
  ↓
[Process Changes]
  判斷事件類型（create/update/delete）
  合併顏色資料
  ↓
[Route by Action]
  IF Node: 判斷操作類型
  ├─ Delete → [Delete Mirror Event]
  ├─ Update → [Update Mirror Event]
  └─ Create → [Verify No Mirror] → [Create Mirror Event]
  ↓
[Update Child Event Meta]
  記錄 mirrorEventId 到子日曆
  ↓
[Save New Sync Token]
  儲存 API 回應的 nextSyncToken
```

### Parse Notification 節點（複用舊邏輯）

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

### Load Sync Token 節點代碼

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
    ...$input.first().json,
    syncToken: syncToken,
    lastSyncTime: lastSync,
    apiUrl: `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(sourceCalendarId)}/events`
  }
}];
```

### Incremental Sync 節點配置 ⭐

**HTTP Request Node:**
```
Method: GET
URL: ={{ $json.apiUrl }}
Authentication: googleCalendarOAuth2Api
Query Parameters:
  - syncToken: ={{ $json.syncToken }}
  - showDeleted: true
```

**關鍵說明**：
- 使用 `syncToken` 參數，Google 只返回自上次同步後變更的事件
- 不需要 `timeMin` 或 `maxResults`
- API 回應包含：
  - `items`: 變更的事件陣列（通常只有 1-2 個）
  - `nextSyncToken`: 新的 sync token（用於下次查詢）

### Process Changes 節點代碼

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
      nextSyncToken: nextSyncToken // 傳遞給後續節點
    }
  });
}

return results;
```

### Save New Sync Token 節點代碼

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
    ...$input.first().json,
    syncTokenUpdated: true,
    updateTime: now
  }
}];
```

---

## 🔄 資料流程示意

### 初始化流程（執行一次）

```
用戶手動觸發
  ↓
讀取5個子日曆配置
  ↓
並行呼叫 5 次 Google Calendar API
  ├─ calendar1: GET /events?maxResults=1 → token1
  ├─ calendar2: GET /events?maxResults=1 → token2
  ├─ calendar3: GET /events?maxResults=1 → token3
  ├─ calendar4: GET /events?maxResults=1 → token4
  └─ calendar5: GET /events?maxResults=1 → token5
  ↓
儲存到 workflow static data
{
  syncTokens: {
    "calendar1": "token1",
    "calendar2": "token2",
    ...
  },
  lastSync: {
    "calendar1": "2026-01-24T01:00:00Z",
    ...
  }
}
```

### 主同步流程（每次 webhook）

```
Google 發送 webhook：「calendar1 有變更」
  ↓
解析通知：sourceCalendarId = calendar1
  ↓
載入 sync token：token = syncTokens[calendar1]
  ↓
增量查詢：GET /events?syncToken=token
  ↓
Google 回應：
{
  items: [
    { id: "abc123", summary: "新事件", ... }  ← 只有變更的事件！
  ],
  nextSyncToken: "new_token"
}
  ↓
處理變更：判斷是 create/update/delete
  ↓
同步到主日曆：建立/更新/刪除鏡像事件
  ↓
儲存新 token：syncTokens[calendar1] = new_token
```

---

## 📊 效率對比

### API 調用次數

| 場景 | 舊架構 | 新架構 | 改善 |
|------|--------|--------|------|
| 單次 webhook | 1 次完整查詢（46+事件） | 1 次增量查詢（1-2事件） | **95%↓** |
| 新增事件 | 1 查詢 + 1 重查 + 1 建立 + 1 更新 = 4 次 | 1 查詢 + 1 建立 + 1 更新 = 3 次 | **25%↓** |
| 更新事件 | 1 查詢 + 1 更新 = 2 次 | 1 查詢 + 1 更新 = 2 次 | **持平** |
| 刪除事件 | 1 查詢 + 1 檢查 + 1 刪除 = 3 次 | 1 查詢 + 1 刪除 = 2 次 | **33%↓** |

### 傳輸資料量

| 場景 | 舊架構 | 新架構 | 改善 |
|------|--------|--------|------|
| 單次查詢 | ~46 個事件 JSON | ~1-2 個事件 JSON | **95%↓** |

### 執行時間

| 場景 | 舊架構 | 新架構 | 改善 |
|------|--------|--------|------|
| 單次 webhook | 2-3 分鐘 | < 5 秒 | **97%↓** |

---

## 🛡️ 錯誤處理

### Sync Token 失效處理

**問題**：Sync Token 可能在以下情況失效：
- 超過一個月未使用
- Google 端資料結構變更
- Token 損壞

**解決方案**：
```javascript
// 在 Incremental Sync 節點設定錯誤處理
// 如果 API 回應 410 Gone 或 400 Invalid Sync Token

onError: "continueRegularOutput"

// 在後續節點檢查錯誤
if (error && error.httpCode === 410) {
  // Token 失效，需要重新初始化
  // 自動觸發 Initialize workflow
  // 或返回錯誤訊息提示用戶手動執行
}
```

### Quota 超限降級

**如果仍然遇到 quota 錯誤**：
```javascript
if (error && error.httpCode === 403 && error.message.includes('Quota exceeded')) {
  // 暫停處理，等待 1 分鐘
  // 或記錄到 queue，稍後重試
}
```

---

## 📝 實作檢查清單

### Workflow 1: Initialize
- [ ] Manual Trigger 節點
- [ ] Load Calendar Config 節點
- [ ] Get Initial Sync Token 節點（HTTP Request）
- [ ] Save Sync Tokens 節點
- [ ] 測試：執行並確認 static data 已儲存

### Workflow 2: Main v2
- [ ] Webhook 節點（複用舊 URL）
- [ ] Parse Notification 節點（複用舊代碼）
- [ ] Load Sync Token 節點
- [ ] Incremental Sync 節點（HTTP Request）
- [ ] Process Changes 節點
- [ ] Route by Action 節點（IF）
- [ ] Create/Update/Delete Mirror Event 節點（複用）
- [ ] Update Child Event Meta 節點（複用）
- [ ] Save New Sync Token 節點
- [ ] 測試：模擬 webhook 並確認流程正確

---

## ✅ 驗收標準

1. **功能正確性**
   - [ ] 新增事件：主日曆建立正確顏色的鏡像
   - [ ] 更新事件：主日曆鏡像同步更新
   - [ ] 刪除事件：主日曆鏡像同步刪除

2. **效能指標**
   - [ ] API 調用量：< 每分鐘 60 次（安全範圍）
   - [ ] 執行時間：< 5 秒
   - [ ] 無 quota 錯誤

3. **穩定性**
   - [ ] 連續 10 次事件變更無錯誤
   - [ ] 壓力測試：快速建立 5 個事件，全部正確同步

---

## 🔗 相關文件

- [Google Calendar API - Sync](https://developers.google.com/calendar/api/guides/sync)
- [Google Calendar API - Events List](https://developers.google.com/calendar/api/v3/reference/events/list)
