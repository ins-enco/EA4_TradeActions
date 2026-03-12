# Sprint 3 Validation Report

## Scope

- Validate build moi cua `TradeAction.mq4` sau Sprint 3.
- Xac minh contract cho `MeasuredTimestamp`, `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, `ProfitSinceStart` bang source walkthrough.
- Audit va source-validate luong sort cua action log sau comparator refactor sang broker `actionTimeMs`.
- Tach ro phan nao da PASS bang CLI/source, phan nao van can trade tay trong MT4.
- Theo doi them thay doi Sprint 3: timer-driven refresh va dirty redraw guard de giam object churn/flicker.

## Validation completed

### 1. Build validation

- Date: `2026-03-12`
- Source timestamp:
  - `TradeAction.mq4`: `2026-03-12 11:29:11`
- Output timestamp:
  - `TradeAction.ex4`: `2026-03-12 11:29:18`
- Compile log:
  - `metaeditor-mt4-compile.log`
- Result:
  - `PASS`
  - `0 errors, 0 warnings`
  - `84 msec elapsed`
- Deployment:
  - `PASS`
  - Da copy [TradeAction.ex4](/d:/data/source/EA4_TradeActions/TradeAction.ex4) vao `C:\Users\pc203\AppData\Roaming\MetaQuotes\Terminal\EFDAB33BCD240EC29090A2E95CB483C8\MQL4\Experts\TradeAction.ex4`
  - Timestamp file deploy khop build repo: `2026-03-12 11:29:18`

### 2. Source walkthrough of measured timestamp capture

- File:
  - `TradeAction.mq4`
- Result:
  - `PASS`
- Notes:
- `SetMeasuredTimestampNow()` lay `TimeLocal()` va ghep them phan mili-giay tu `GetTickCount() % 1000` de tao local measured timestamp.
- `AppendOpenActionFromSnapshot()` va `AppendCloseActionFromSnapshot()` deu gan `MeasuredTimestamp` tai luc row duoc append, khong dung `OrderOpenTime()` hay `OrderCloseTime()` lam measured time.
- `SeedBaselineOpenActions()` goi `ClearMeasuredTimestamp()` nen row baseline sau attach hien de trong.
- `FormatMeasuredTimestamp()` tra ve chuoi `yyyy.MM.dd HH:mm:ss.mmm`; neu `hasMeasuredTimestamp == false` thi tra ve chuoi rong.

### 3. Source walkthrough of derived-field engine

- File:
  - `TradeAction.mq4`
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

### 4. Current-source review for sorting, trimming, and redraw state

- Files:
  - `TradeAction.mq4`
- Result:
  - `PASS` cho source review
- Notes:
  - `BuildTableRenderState()` da them `FormatMeasuredTimestamp(action)` vao dirty redraw hash, nen thay doi cot moi se kich redraw.
  - `SortTradeActionsByTime()` nay sort tang dan theo broker `actionTimeMs`; neu bang nhau thi van la `open` truoc `close`, roi den `ticket`.
  - `DrawTable()` va `BuildTableRenderState()` deu doc `g_tradeActions` sau khi mang nay da duoc sort va recalc, nen row order tren chart phu thuoc truc tiep vao comparator cua `SortTradeActionsByTime()`.
  - `TrimTradeActionLog()` va `UpdateTradeActionSymbolStateFromAction()` da carry forward ca `hasMeasuredTimestamp` va `measuredTimestampMs`, nen retained rows khong mat context cho rule milliseconds moi.

### 5. Sprint 2 ordering implementation review

- Files:
  - `TradeAction.mq4`
- Result:
  - `PASS` cho source audit
  - `PASS` cho comparator refactor scope
- Notes:
  - Helper sort da duoc doi thanh `GetTradeActionSortTimeMs()` va chi tra ve broker `actionTimeMs`.
  - `AppendOpenActionFromSnapshot()` va `AppendCloseActionFromSnapshot()` deu luu ca hai nguon thoi gian: `actionTimeMs` tu broker/MT4 va `MeasuredTimestamp` tu local PC luc detect action.
  - `SeedBaselineOpenActions()` seed row voi `actionTimeMs` hop le nhung co `MeasuredTimestamp` rong; sau refactor, baseline row va live row cung dung chung primary key la broker `actionTimeMs`.
  - `RecalculateTradeActionDerivedFields()` luon `SortTradeActionsByTime()` truoc khi recalc, vi vay order cua table va order cua per-symbol derived-field pass dung chung mot mang da sort.
  - `ResolvePendingCloseActions()` co the append close row muon hon thoi diem close thuc te; sau moi lan sort, row nay co the di chuyen den vi tri phu hop voi sort key.
  - Contract dang duoc source-ap dung:
    - primary key = tang dan theo broker `actionTimeMs`
    - neu bang nhau = `open` truoc `close`
    - neu van bang nhau = `ticket` nho hon truoc
    - `MeasuredTimestamp` chi dung cho display va `MillisecondsSinceLastAction`, khong tham gia sort

### 6. Experts log review

- Files:
  - `MQL4/Logs/20260310.log`
  - `MQL4/Logs/20260311.log`
  - `MQL4/Logs/20260312.log`
- Result:
  - `PARTIAL PASS`
- Notes:
  - Khong thay chuoi `array out of range` hoac `zero divide` gan voi `TradeAction`.
  - Log lich su `20260311.log` cho thay EA da initialize/remove nhieu lan va da tung ghi cac event:
    - `TradeAction: Seeded 1 baseline open actions.`
    - `TradeAction: detected 1 new open action(s).`
    - `TradeAction: detected 1 close action(s) from snapshot diff.`
    - `TradeAction: started millisecond timer at 50/100/200/1000 ms.`
    - `TradeAction: timer cadence lagged to ...`
    - `TradeAction: timer refresh took 31958.020 ms (target 200 ms).`
  - Log `20260312.log` cua terminal active hien chi co:
    - `Expert TradeAction AUDCAD,H1: loaded successfully`
    - dump inputs tai `2026-03-12 08:53:59`
  - Chua co event trade/timer moi sau khi deploy build `2026-03-12 11:29:18`, nen current-build runtime validation van chua dong.
  - Khong tim thay evidence `queued pending close action(s)` hoac `resolved pending close action(s)` trong cac log hien co, nen pending-close reorder case van chua duoc chung minh.

### 7. Sprint 3 source review: timer-driven redraw policy

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

1. Manual MT4 execution tren build moi `TradeAction.ex4` timestamp `2026-03-12 11:29:18`
   - Chay M0-M2, S1-S6, va O1-O4 trong `docs/testing/task-3.3-manual-scenario-matrix.md`
   - Danh dau `PASS/FAIL` theo gia tri table thuc te
2. Runtime log review sau khi reload build moi
   - Can co log moi trong `MQL4/Logs/20260312.log` hoac log ngay tiep theo sau khi reload/reattach EA
   - Kiem tra xem build moi co phat sinh `started millisecond timer`, trade event, va runtime error hay khong
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
   - Doi chieu them voi lich su `20260311.log`: da tung co `started millisecond timer` va `timer cadence lagged`, nhung can chay lai tren build `2026-03-12 11:29:18`
5. Dirty redraw / flicker verification
   - Thu voi `InpRefreshIntervalMs = 100`, `200`, `500`
   - Resize chart khi khong co trade change va xac nhan table van redraw dung layout
   - Theo doi `Experts` xem co log `timer cadence lagged` hoac `timer refresh took` thuong xuyen hay khong; lich su `20260311.log` cho thay van con nguy co lag o interval nho

## Suggested next step

- Reload EA `TradeAction` tren MT4 sau ban compile `2026-03-12 11:29:18`.
- Chay lan luot M0-M2, S1-S6, va O1-O4.
- Ghi lai ket qua thuc te vao `docs/testing/task-3.3-manual-scenario-matrix.md`.
- Sau khi co log moi, review lai `20260312.log` de dong cac muc runtime cho current build.
