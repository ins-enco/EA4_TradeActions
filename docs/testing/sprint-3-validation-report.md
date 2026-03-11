# Sprint 3 Validation Report

## Scope

- Validate build moi cua `TradeAction.mq4` sau Sprint 3.
- Xac minh contract cho `MeasuredTimestamp`, `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, `ProfitSinceStart` bang source walkthrough.
- Tach ro phan nao da PASS bang CLI/source, phan nao van can trade tay trong MT4.
- Theo doi them thay doi Sprint 3: timer-driven refresh va dirty redraw guard de giam object churn/flicker.

## Validation completed

### 1. Build validation

- Date: `2026-03-11`
- Source timestamp:
  - `TradeAction.mq4`: `2026-03-11 14:18:19`
- Output timestamp:
  - `TradeAction.ex4`: `2026-03-11 14:19:11`
- Compile log:
  - `metaeditor-mt4-compile.log`
- Result:
  - `PASS`
  - `0 errors, 0 warnings`

### 2. Source walkthrough of measured timestamp capture

- File:
  - `TradeAction.mq4:221-241`
  - `TradeAction.mq4:720-726`
  - `TradeAction.mq4:808-814`
  - `TradeAction.mq4:1288-1307`
- Result:
  - `PASS`
- Notes:
- `SetMeasuredTimestampNow()` lay `TimeLocal()` va ghep them phan mili-giay tu `GetTickCount() % 1000` de tao local measured timestamp.
- `AppendOpenActionFromSnapshot()` va `AppendCloseActionFromSnapshot()` deu gan `MeasuredTimestamp` tai luc row duoc append, khong dung `OrderOpenTime()` hay `OrderCloseTime()` lam measured time.
- `SeedBaselineOpenActions()` goi `ClearMeasuredTimestamp()` nen row baseline sau attach hien de trong.
- `FormatMeasuredTimestamp()` tra ve chuoi `yyyy.MM.dd HH:mm:ss.mmm`; neu `hasMeasuredTimestamp == false` thi tra ve chuoi rong.

### 3. Source walkthrough of derived-field engine

- File:
  - `TradeAction.mq4:1148-1181`
- Result:
  - `PASS`
- Notes:
  - `Exposure` duoc tinh bang `Round(previousExposure + signedQuantity, 10)` thong qua `GetSignedQuantity()` va `RoundTradeActionValue()`.
  - `MillisecondsSinceLastAction` chi tinh khi action truoc do cua cung `symbolName` co `MeasuredTimestamp` va action hien tai cung co `MeasuredTimestamp`; neu khong thi giu `0`.
  - `PriceDifferenceFromPrevious` chi duoc gan khi:
    - symbol da co action truoc do
    - `Abs(previousExposure) > 0.000001`
    - direction dao chieu
  - `ProfitSinceStart` mac dinh giu `previousProfit`, va chi cong them khi `hasPriceDifferenceFromPrevious == true`.

### 4. Regression review for sorting, trimming, and redraw state

- Files:
  - `TradeAction.mq4:248-270`
  - `TradeAction.mq4:975-1016`
  - `TradeAction.mq4:1110-1149`
- Result:
  - `PASS` cho source review
- Notes:
  - `BuildTableRenderState()` da them `FormatMeasuredTimestamp(action)` vao dirty redraw hash, nen thay doi cot moi se kich redraw.
  - `SortTradeActionsByTime()` uu tien `MeasuredTimestamp` khi co, neu khong thi fallback ve `actionTimeMs`; thu tu tiep theo van la `open` truoc `close`, roi den `ticket`.
  - `TrimTradeActionLog()` va `UpdateTradeActionSymbolStateFromAction()` da carry forward ca `hasMeasuredTimestamp` va `measuredTimestampMs`, nen retained rows khong mat context cho rule milliseconds moi.

### 5. Experts log review

- Files:
  - `MQL4/Logs/20260310.log`
  - `MQL4/Logs/20260311.log`
- Result:
  - `PARTIAL PASS`
- Notes:
  - Khong thay chuoi `array out of range` hoac `zero divide` gan voi `TradeAction`.
  - Log lich su cho thay EA da initialize/remove nhieu lan va da tung ghi cac event:
    - `TradeAction: Seeded 1 baseline open actions.`
    - `TradeAction: detected 1 new open action(s).`
    - `TradeAction: detected 1 close action(s) from snapshot diff.`
  - Tuy nhien cac dong event nay la truoc build moi `2026-03-11 14:19:11`, nen chi co gia tri tham chieu cho flow, khong thay the duoc runtime validation cua build hien tai.

### 6. Sprint 3 source review: timer-driven redraw policy

- Result:
  - `PASS` cho source review
- Files:
  - `TradeAction.mq4`
- Notes:
  - `OnTick()` da duoc de rong, khong con la refresh owner.
  - `OnTimer()` goi `RunTimerRefreshCycle()` de poll trade state theo `InpRefreshIntervalMs`.
  - `RefreshTradeActionView()` chi `DrawTable()` khi render state thay doi, chart width thay doi, hoac object table bi mat.
  - Dirty redraw guard giu lai object tren chart giua cac cycle timer neu table visible state khong doi.

## Still pending

1. Manual MT4 execution tren build moi `TradeAction.ex4` timestamp `2026-03-11 14:19:11`
   - Chay M0-M2 va S1-S6 trong `docs/testing/task-3.3-manual-scenario-matrix.md`
   - Danh dau `PASS/FAIL` theo gia tri table thuc te
2. Runtime log review sau khi reload build moi
   - Can co log moi trong `MQL4/Logs/20260311.log` hoac log ngay tiep theo
   - Kiem tra xem build moi co phat sinh print event va co runtime error hay khong
3. UI verification
   - Xac nhan cot `MeasuredTimestamp` nam sau `Exposure` va truoc `MillisecondsSinceLastAction`
   - Xac nhan row baseline attach hien `MeasuredTimestamp` de trong
   - Xac nhan action moi hien `MeasuredTimestamp` theo format `yyyy.MM.dd HH:mm:ss.mmm`
   - Xac nhan `MillisecondsSinceLastAction` = `0` neu row truoc do cua symbol la baseline blank
   - Xac nhan `MillisecondsSinceLastAction` > `0` giua hai action lien tiep deu co `MeasuredTimestamp`
   - Xac nhan `PriceDifferenceFromPrevious` hien `N/A` tren table, khong phai `0`
   - Xac nhan `Exposure` va `ProfitSinceStart` hien dung dinh dang mong muon tren chart
4. Timer-driven refresh verification
   - Gan EA len quiet chart va mo/close lenh tu terminal hoac chart khac
   - Xac nhan table update trong khoang `InpRefreshIntervalMs` ma khong can tick moi tren chart attach
5. Dirty redraw / flicker verification
   - Thu voi `InpRefreshIntervalMs = 100`, `200`, `500`
   - Resize chart khi khong co trade change va xac nhan table van redraw dung layout
   - Theo doi `Experts` xem co log `timer cadence lagged` hoac `timer refresh took` thuong xuyen hay khong

## Suggested next step

- Reload EA `TradeAction` tren MT4 sau ban compile `2026-03-11 14:19:11`.
- Chay lan luot M0-M2 va S1-S6.
- Ghi lai ket qua thuc te vao `docs/testing/task-3.3-manual-scenario-matrix.md`.
