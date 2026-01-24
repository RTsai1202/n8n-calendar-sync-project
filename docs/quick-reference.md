# 🚀 快速參考卡

## 需要複製的代碼片段

### 1. Parse Notification
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

---

### 2. Load Sync Token
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

---

### 3. Incremental Sync (HTTP Request)

**URL 表達式**：
```
https://www.googleapis.com/calendar/v3/calendars/{{ encodeURIComponent($json.sourceCalendarId) }}/events
```

**Query Parameters**：
- `syncToken`: `{{ $json.syncToken }}`
- `showDeleted`: `true`

---

### 4. Process Changes
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

---

### 5. Update Child Event Meta (HTTP Request)

**URL 表達式**：
```
https://www.googleapis.com/calendar/v3/calendars/{{ encodeURIComponent($json.sourceCalendarId) }}/events/{{ $json.childEventId }}
```

**JSON Body 表達式**：
```javascript
{{ JSON.stringify({ extendedProperties: { private: { gsync2_sourceCalendar: $json.sourceCalendarId, gsync2_mirrorEventId: $json.id } } }) }}
```

---

### 6. Save New Sync Token
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

---

## 常用表達式

### Google Calendar 操作節點

**Event ID**：
```
{{ $json.mirrorEventId }}
```

**Summary**：
```
{{ $json.summary }}
```

**Description**：
```
{{ $json.description }}
```

**Location**：
```
{{ $json.location }}
```

**Start**：
```
{{ $json.start.dateTime || $json.start.date }}
```

**End**：
```
{{ $json.end.dateTime || $json.end.date }}
```

**Color**：
```
{{ $json.colorId }}
```

---

## Switch 條件設定

**規則 1 (Delete)**：
- Field: `{{ $json.action }}`
- Condition: Equal
- Value: `delete`

**規則 2 (Update)**：
- Field: `{{ $json.action }}`
- Condition: Equal
- Value: `update`

**規則 3 (Create)**：
- Field: `{{ $json.action }}`
- Condition: Equal
- Value: `create`

---

## 重要配置

**Webhook Path**：`calendar-sync-v2`

**Main Calendar ID**：`answer4154@gmail.com`

**Credentials**：`Google Calendar account 2`

---

## 新的 Webhook URL

```
https://n8n.startandkeep.com/webhook/calendar-sync-v2
```

稍後需要用這個 URL 重新註冊 Google Calendar Push Notifications
