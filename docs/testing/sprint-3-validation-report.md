# Sprint 3 Validation Report

## Scope

- Validate build moi cua `TradeAction.mq4` sau Sprint 3.
- Xac minh contract cho `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, `ProfitSinceStart` bang source walkthrough va scenario simulation.
- Tach ro phan nao da PASS bang CLI/source, phan nao van can trade tay trong MT4.
- Theo doi them thay doi Sprint 3: timer-driven refresh va dirty redraw guard de giam object churn/flicker.

## Validation completed

### 1. Build validation

- Date: `2026-03-11`
- Source timestamp:
  - `TradeAction.mq4`: `2026-03-11 11:57:58`
- Output timestamp:
  - `TradeAction.ex4`: `2026-03-11 11:58:23`
- Compile log:
  - `metaeditor-mt4-compile.log`
- Result:
  - `PASS`
  - `0 errors, 0 warnings`

### 2. Source walkthrough of derived-field engine

- File: `TradeAction.mq4:925-962`
- Result:
  - `PASS`
- Notes:
  - `Exposure` duoc tinh bang `Round(previousExposure + signedQuantity, 10)` thong qua `GetSignedQuantity()` va `RoundTradeActionValue()`.
  - `MillisecondsSinceLastAction` chi so voi state truoc do cua cung `symbolName`.
  - `PriceDifferenceFromPrevious` chi duoc gan khi:
    - symbol da co action truoc do
    - `Abs(previousExposure) > 0.000001`
    - direction dao chieu
  - `ProfitSinceStart` mac dinh giu `previousProfit`, va chi cong them khi `hasPriceDifferenceFromPrevious == true`.

### 3. Scenario simulation aligned with source contract

- Result:
  - `PASS`
- Method:
  - Chay mot PowerShell simulation dung cung contract nhu code da implement.
- Cases:
  - Example A:
    - `Buy 0.1 @ 1.1000` -> `Exposure=0.1`, `PriceDiff=N/A`, `ProfitSinceStart=0`
    - `Sell 0.1 @ 1.1050` -> `Exposure=0`, `PriceDiff=0.005`, `ProfitSinceStart=0.005`
  - Example B:
    - `Buy -> Buy` giu `PriceDiff=N/A`, `ProfitSinceStart` khong doi
  - Example C:
    - `Sell -> Buy` khi con exposure tinh ra `PriceDiff=0.005`
    - action tiep theo `Sell` sau khi symbol da flat giu `PriceDiff=N/A`
  - Multi-symbol:
    - sequence `EURUSD -> AUDUSD -> EURUSD` cho thay milliseconds, exposure, price diff duoc tinh theo symbol rieng, khong bi row cua symbol khac chen vao

### 4. Regression review for sorting and trimming

- Files:
  - `TradeAction.mq4:750-783`
  - `TradeAction.mq4:781-825`
- Result:
  - `PASS` cho source review
- Notes:
  - `SortTradeActionsByTime()` van giu thu tu on dinh theo `actionTimeMs`, `open` truoc `close`, roi den `ticket`.
  - `TrimTradeActionLog()` khong con giu duy nhat mot exposure baseline; no cap nhat baseline theo tung symbol truoc khi recalc retained rows.

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
  - Tuy nhien cac dong event nay la truoc build moi `2026-03-11 10:22:03`, nen chi co gia tri tham chieu cho flow, khong thay the duoc runtime validation cua build hien tai.

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

1. Manual MT4 execution tren build moi `TradeAction.ex4` timestamp `2026-03-11 10:22:03`
   - Chay S1-S6 trong `docs/testing/task-3.3-manual-scenario-matrix.md`
   - Danh dau `PASS/FAIL` theo gia tri table thuc te
2. Runtime log review sau khi reload build moi
   - Can co log moi trong `MQL4/Logs/20260311.log` hoac log ngay tiep theo
   - Kiem tra xem build moi co phat sinh print event va co runtime error hay khong
3. UI verification
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

- Reload EA `TradeAction` tren MT4 sau ban compile `2026-03-11 11:58:23`.
- Chay lan luot S1-S6.
- Ghi lai ket qua thuc te vao `docs/testing/task-3.3-manual-scenario-matrix.md`.
