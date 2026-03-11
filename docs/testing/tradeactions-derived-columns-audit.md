# TradeActions Derived Columns Audit

## Muc tieu

- Khoa contract cho 4 cot `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, `ProfitSinceStart` truoc khi sua code.
- Ghi ro diem dang tinh sai trong `TradeAction.mq4` de Sprint 2 chi can refactor theo danh sach nay.
- Chot cach bieu dien gia tri "khong co" cho `PriceDifferenceFromPrevious` de tranh nham voi `0`.

## Contract da khoa

1. `signedQuantity`
   - `Buy = +quantity`
   - `Sell = -quantity`
2. `Exposure`
   - `Round(previousExposure + signedQuantity, 10)`
   - `previousExposure` la exposure cua action truoc do cung `symbolName`, mac dinh `0`
3. `MillisecondsSinceLastAction`
   - Neu symbol da co action truoc do: `ticketTimestamp - last.Timestamp`
   - Neu chua co: `0`
4. `PriceDifferenceFromPrevious`
   - Mac dinh: `N/A`
   - Chi tinh khi da co action truoc do cung symbol, `previousExposure != 0`, va huong hien tai nguoc voi huong action truoc
   - `Buy sau Sell = last.Price - price`
   - `Sell sau Buy = price - last.Price`
5. `ProfitSinceStart`
   - Mac dinh giu `previousProfit`
   - Neu co `PriceDifferenceFromPrevious`: `Round(previousProfit + PriceDifferenceFromPrevious, 10)`

## Current write points va mismatch

### Exposure

- Write points hien tai:
  - `TradeAction.mq4:470`
  - `TradeAction.mq4:573-578`
  - `TradeAction.mq4:848-849`
  - `TradeAction.mq4:950-951`
  - helper `TradeAction.mq4:982-1006`
- Hien tai:
  - `AppendOpenActionFromSnapshot` va `AppendCloseActionFromSnapshot` doc `g_tradeActions[g_tradeActionCount - 1]` o `TradeAction.mq4:463-468` va `TradeAction.mq4:566-571`, nen lay row cuoi cung toan cuc.
  - `RecalculateTradeActionDerivedFieldsCore` dung `runningExposure` toan cuc o `TradeAction.mq4:840-849`.
  - `SeedBaselineOpenActions` cung seed exposure theo bien chay toan cuc o `TradeAction.mq4:931-951`.
  - Khong co helper `Round(..., 10)`.
- Lech contract:
  - Chua tinh theo action truoc do cua cung symbol.
  - Chua su dung `signedQuantity` la nguon su that duy nhat.
  - Chua lam tron 10 chu so thap phan truoc khi luu.

### MillisecondsSinceLastAction

- Write points hien tai:
  - `TradeAction.mq4:473-475`
  - `TradeAction.mq4:582-584`
  - `TradeAction.mq4:851-853`
  - `TradeAction.mq4:954-956`
- Hien tai:
  - Tat ca cac nhanh deu so voi row/action truoc do trong log toan cuc.
- Lech contract:
  - Contract can action truoc do cua cung symbol.
  - Neu sau nay log giu nhieu symbol, gia tri se bi lech ngay ca khi timestamp dung.

### PriceDifferenceFromPrevious

- Write points hien tai:
  - `TradeAction.mq4:477-479`
  - `TradeAction.mq4:586-588`
  - `TradeAction.mq4:855-857`
  - `TradeAction.mq4:957-959`
- Hien tai:
  - Gia tri mac dinh dang la `0.0`.
  - Neu co row truoc do thi code luon tinh `currentPrice - previousExecutionPrice`.
  - Khong kiem tra `previousExposure != 0`.
  - Khong kiem tra dao huong `Buy <-> Sell`.
- Lech contract:
  - Contract can trang thai `N/A` khi khong du dieu kien tinh.
  - Contract co 2 cong thuc bat doi xung:
    - `Buy sau Sell = last.Price - price`
    - `Sell sau Buy = price - last.Price`
  - Logic hien tai chi dua vao row lien truoc, khong dua vao previous action state cua cung symbol.

### ProfitSinceStart

- Write points hien tai:
  - `TradeAction.mq4:481`
  - `TradeAction.mq4:590`
  - `TradeAction.mq4:859`
  - `TradeAction.mq4:960`
- Hien tai:
  - Dang gan bang `AccountEquity() - g_equityAtAttach`.
- Lech contract:
  - Contract khong dung equity snapshot.
  - Contract can `previousProfit` theo symbol va chi cong them khi `PriceDifferenceFromPrevious` co gia tri.

### Renderer va van de "N/A"

- Write points hien tai:
  - `TradeAction.mq4:212-214`
- Hien tai:
  - `DoubleToString(action.priceDifferenceFromPrevious, Digits)` va `DoubleToString(action.profitSinceStart, 2)` luon render so.
- He qua:
  - Neu tiep tuc luu `0.0` cho `PriceDifferenceFromPrevious`, UI se khong phan biet duoc "khong co gia tri" va "co gia tri bang 0".

## Quyet dinh cho gia tri "khong co"

- Chon cach bieu dien bang co `bool hasPriceDifferenceFromPrevious` trong `TradeActionRow`.
- `priceDifferenceFromPrevious` chi duoc xem la hop le khi co nay la `true`.
- Khi `hasPriceDifferenceFromPrevious == false`:
  - bo qua cong thuc cong don vao `ProfitSinceStart`
  - renderer in `N/A` hoac chuoi rong, khong in `0.00000`
- Khong chon sentinel so hoc nhu `0`, `EMPTY_VALUE`, hay mot so rat lon vi:
  - de bi render sai thanh mot gia tri hop le
  - de bi cong/tru nham trong `ProfitSinceStart`
  - kho doc trong log va kho kiem soat khi trim/recalculate

## Thu tu sua code o Sprint 2

1. Tao helper `signedQuantity` va helper round 10 chu so thap phan.
2. Them state per-symbol cho last direction, last timestamp, last price, last exposure, last profit.
3. Viet lai `RecalculateTradeActionDerivedFieldsCore` theo contract.
4. Giam append-time assignment trong `AppendOpenActionFromSnapshot`, `AppendCloseActionFromSnapshot`, `SeedBaselineOpenActions`.
5. Cap nhat `DrawTable` de hien thi `N/A` cho `PriceDifferenceFromPrevious` khi co `hasPriceDifferenceFromPrevious == false`.

## Tai lieu lien quan

- `docs/plans/tradeactions-derived-columns-fix-plan.md`
- `docs/plans/update-trade-data-async-trade-ticket-action.md`
- `docs/testing/task-3.3-manual-scenario-matrix.md`
