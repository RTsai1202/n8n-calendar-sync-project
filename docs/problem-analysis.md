# Google Calendar 同步系統 - 問題分析報告

## 📅 報告日期
2026-01-24

## 🔴 核心問題

### API Quota 超限錯誤
```
Error: Quota exceeded for quota metric 'Queries' and limit
'Queries per minute per user' of service 'calendar-json.googleapis.com'

Google Calendar API 限制：每分鐘 600 次請求
```

### 錯誤執行記錄
- 時間範圍：2026-01-23 23:30-23:36（6分鐘）
- 總執行次數：30+ 次
- 失敗次數：27+ 次
- 成功執行耗時：2-3 分鐘（異常長）

**典型錯誤執行**：
- #358: 23:35:55 - Error (Get Child Calendar Events 失敗)
- #357: 23:35:55 - Error (API quota exceeded)
- #356: 23:35:54 - Error (API quota exceeded)

## 🔍 根本原因分析

### 1. 架構設計缺陷

**當前架構**：
```
每個 Webhook 觸發
  ↓
解析通知
  ↓
查詢整個子日曆（最近10分鐘的所有事件）  ← 問題所在
  ↓
處理事件
  ↓
同步到主日曆
```

**問題**：
- 每次 webhook 都查詢**完整的日曆**（最近10分鐘所有事件）
- 即使只有1個事件變更，也要取得可能的 46 個事件
- 無法知道具體是哪個事件變更

### 2. Webhook 風暴

**觀察到的模式**：
- Google Calendar 會在短時間內發送多個 webhook
- 5個子日曆 × 多個通知 = 大量並發請求
- 去重機制只能防止完全相同的 webhook，無法減少 API 調用

**23:33-23:36 執行分析**：
```
23:30:08 - #329: 開始（耗時 3分25秒）
23:30:09 - #330: 開始（耗時 3分31秒）
23:30:09 - #331: 開始（耗時 2分59秒）
23:30:35 - #332, #333, #334: 同時開始
23:31:12 - #335, #336, #337: API quota 錯誤開始出現
23:33:07 - #341-343: 持續錯誤
23:33:16 - #344-346: 部分成功
23:33:27 - #347-349: 錯誤
23:35:45 - #353-358: 全部錯誤
```

### 3. API 效率低下

**每次 webhook 的 API 調用**：
1. Get Child Calendar Events（完整查詢，可能46+個事件）
2. Check Before Create / Verify Mirror Exists（額外查詢）
3. Create/Update/Delete Mirror Event（實際操作）
4. Update Child Event Meta（更新 metadata）

**實際需求 vs 實際查詢**：
- 需求：知道哪1-2個事件變更了
- 實際：查詢整個日曆的所有事件

## 📊 數據證據

### API 使用量估算
```
假設：23:30-23:36（6分鐘）
- Webhook 觸發：30+ 次
- 每次查詢事件數：~46 個
- 每個事件可能觸發：1-4 次額外 API 調用

估算總調用數：
30 (webhook) × 1 (getAll) = 30 次基礎查詢
+ 成功執行的額外操作：~50-100 次

總計：100-150 次 API 調用在 6 分鐘內
```

**結果**：雖然沒有超過理論限制（600/分鐘），但：
- 實際執行速度慢（2-3分鐘/次）
- 大量並發導致 quota 快速耗盡
- 錯誤重試加劇問題

### 執行時間異常

**正常預期**：
- 簡單的同步應該 < 5 秒

**實際觀察**：
- #346: 2分27秒
- #345: 2分51秒
- #331: 2分59秒
- #330: 3分31秒

**原因**：
- 查詢大量事件數據
- 多次 API 往返
- 可能的網絡延遲累積

## ✅ 解決方案需求

### 必須解決的問題
1. ✅ 減少 API 調用量（至少降低 80%+）
2. ✅ 縮短執行時間（目標 < 5 秒）
3. ✅ 只查詢真正變更的事件
4. ✅ 避免查詢整個日曆

### 方案選擇
**選擇：增量同步（Sync Token）**

**理由**：
- Google 官方推薦的最佳實踐
- 只傳輸變更的事件
- API 使用量最低
- 即時處理

## 📈 預期改善

### API 調用量
```
舊架構：每次 webhook = 1 次完整查詢（46+ 事件）
新架構：每次 webhook = 1 次增量查詢（1-2 個變更事件）

減少比例：90%+
```

### 執行時間
```
舊架構：2-3 分鐘
新架構：< 5 秒

改善：90%+
```

### 穩定性
```
舊架構：頻繁 quota 錯誤
新架構：幾乎不會觸發 quota 限制
```

## 🔗 參考資料

- [Google Calendar API - Sync](https://developers.google.com/calendar/api/guides/sync)
- [Google Calendar API - Quotas](https://developers.google.com/calendar/api/guides/quota)
- [n8n Workflow Static Data](https://docs.n8n.io/code/cookbook/builtin/get-workflow-static-data/)
