# Task 3.3 Manual Scenario Matrix (TradeAction)

## Muc tieu

- Xac nhan 4 loai action deu duoc ghi dung len table:
  - open buy -> `OpenOrClose=open`, `TradeDirection=buy`
  - open sell -> `OpenOrClose=open`, `TradeDirection=sell`
  - close buy -> `OpenOrClose=close`, `TradeDirection=sell`
  - close sell -> `OpenOrClose=close`, `TradeDirection=buy`
- Xac nhan cac cot `Ticket`, `Symbol Name`, `ExecutionPrice`, `Profit` khop voi Terminal (`Trade`/`Account History`).
- Xac nhan 4 cot derived field follow contract moi:
  - `Exposure = Round(previousExposure + signedQuantity, 10)`
  - `MillisecondsSinceLastAction = 0` cho action dau tien cua symbol, nguoc lai = chenhlech ms so voi action truoc do cung symbol
  - `PriceDifferenceFromPrevious = N/A` neu khong du dieu kien, chi tinh khi `previousExposure != 0` va direction dao chieu
  - `ProfitSinceStart` giu `previousProfit`, chi cong them `PriceDifferenceFromPrevious` khi cot nay co gia tri
- Xac nhan khong co runtime error trong tab `Experts` khi chay scenario.

## Pre-check tu dong (CLI)

- Date: `2026-03-11`
- Build command:
  - `metaeditor.exe /compile:.../TradeAction.mq4 /log:.../metaeditor-mt4-compile.log`
- Build result:
  - `Result: 0 errors, 0 warnings`
- Build artifact:
  - `TradeAction.ex4` timestamp `2026-03-11 10:22:03`

## Sprint 3 status

- CLI/source validation:
  - `PASS`
  - Xem them `docs/testing/sprint-3-validation-report.md`
- Manual MT4 execution:
  - `PENDING`
  - Chua co bang chung trade tay tren build moi sau khi compile luc `2026-03-11 10:22:03`

## Cau hinh test thu cong

1. Attach EA `TradeAction` vao 1 chart symbol de test (vi du `EURUSD`).
2. Dam bao table da hien va dang trong trang thai "No trade actions recorded since attach" neu chua co action.
3. Dung 1 account demo va volume nho (vi du `0.01`) de mo/ dong nhanh.
4. Sau moi action, doi it nhat 1 tick de EA cap nhat table.

## Quy uoc ghi nhan ket qua

- Ghi `N/A` khi cot dang o trang thai "khong co gia tri", khong duoc thay bang `0`.
- Ghi `>0` neu chi can xac nhan milliseconds duong, khong can dung gia tri tuyet doi.
- Neu test bang gia thuc te khong dat dung gia mau, thay gia tri cu the vao cong thuc cung hang va doi chieu ket qua theo cong thuc, khong doi theo con so mau.

## Scenario Matrix

| ID | Thao tac | Dieu kien truoc do | Row moi ky vong | Exposure ky vong | Milliseconds ky vong | PriceDiff ky vong | ProfitSinceStart ky vong | Ket qua thuc te |
|---|---|---|---|---|---|---|---|---|
| S1 | Mo lenh BUY dau tien `0.10` | Symbol chua co action nao | `open`, `buy`, `Ticket Direction=BUY` | `0.10` | `0` | `N/A` | `0` | Pending |
| S2 | Dong lenh BUY cua S1 | Row truoc la `buy`, `previousExposure=0.10` | `close`, `sell`, `Ticket Direction=BUY` | `0.00` | `>0` | `closePrice - openPrice` | `0 + PriceDiff` | Pending |
| S3 | Mo them 1 lenh BUY `0.10` khi da co 1 BUY dang mo | Row truoc la `buy`, `previousExposure > 0` | `open`, `buy`, `Ticket Direction=BUY` | `previousExposure + 0.10` | `>0` | `N/A` | `giu previousProfit` | Pending |
| S4 | Sau khi vua dong 1 SELL va symbol da flat, mo SELL moi `0.10` | Row truoc la `buy` nhung `previousExposure=0` | `open`, `sell`, `Ticket Direction=SELL` | `-0.10` | `>0` | `N/A` | `giu previousProfit` | Pending |
| S5 | Mo lenh SELL dau tien `0.10` | Symbol chua co action nao | `open`, `sell`, `Ticket Direction=SELL` | `-0.10` | `0` | `N/A` | `0` | Pending |
| S6 | Dong lenh SELL cua S5 | Row truoc la `sell`, `previousExposure=-0.10` | `close`, `buy`, `Ticket Direction=SELL` | `0.00` | `>0` | `last.Price - price` | `0 + PriceDiff` | Pending |

## Worked examples

### Example A: Buy 0.1 @ 1.1000, roi close o 1.1050

| Step | Action | TradeDirection | signedQuantity | Exposure | PriceDiff | ProfitSinceStart |
|---|---|---|---|---|---|---|
| A1 | Mo BUY `0.10` tai `1.1000` | `buy` | `+0.10` | `0.10` | `N/A` | `0` |
| A2 | Dong BUY do tai `1.1050` | `sell` | `-0.10` | `0.00` | `1.1050 - 1.1000 = 0.0050` | `0.0050` |

### Example B: Hai action cung huong Buy

| Step | Action | TradeDirection | signedQuantity | Exposure | PriceDiff | ProfitSinceStart |
|---|---|---|---|---|---|---|
| B1 | Mo BUY `0.10` tai `1.2000` | `buy` | `+0.10` | `0.10` | `N/A` | `0` |
| B2 | Mo them BUY `0.10` tai `1.2020` | `buy` | `+0.10` | `0.20` | `N/A` | `0` |

### Example C: Direction dao chieu nhung previousExposure = 0

| Step | Action | TradeDirection | signedQuantity | Exposure | PriceDiff | ProfitSinceStart |
|---|---|---|---|---|---|---|
| C1 | Mo SELL `0.10` tai `1.3000` | `sell` | `-0.10` | `-0.10` | `N/A` | `0` |
| C2 | Dong SELL do tai `1.2950` | `buy` | `+0.10` | `0.00` | `1.3000 - 1.2950 = 0.0050` | `0.0050` |
| C3 | Mo SELL moi `0.10` tai `1.2960` | `sell` | `-0.10` | `-0.10` | `N/A` | `0.0050` |

## Checklist doi chieu cot

Danh dau `PASS/FAIL` sau khi chay toi thieu S1-S6 va doi chieu them voi Example A-C.

| Cot | Rule doi chieu | Status | Ghi chu |
|---|---|---|---|
| OpenOrClose | open khi mo ticket, close khi dong ticket | Pending | |
| TradeDirection | close thi dao chieu so voi ticket goc | Pending | |
| Ticket Direction | BUY/SELL theo ticket goc, khong doi khi close | Pending | |
| Ticket | Trung ticket tren tab Trade/History | Pending | |
| Symbol Name | Trung symbol chart / symbol order | Pending | |
| ExecutionPrice | open: OrderOpenPrice, close: OrderClosePrice | Pending | |
| Profit | close: `OrderProfit + Swap + Commission` | Pending | |
| Exposure | `Round(previousExposure + signedQuantity, 10)` theo action truoc do cung symbol | Pending | |
| MillisecondsSinceLastAction | `0` o action dau tien cua symbol, nguoc lai = chenhlech ms so voi action truoc do cung symbol | Pending | |
| PriceDifferenceFromPrevious | `N/A` neu khong du dieu kien; chi tinh khi `previousExposure != 0` va direction dao chieu | Pending | |
| ProfitSinceStart | Mac dinh giu `previousProfit`; chi cong them `PriceDifferenceFromPrevious` khi cot nay co gia tri | Pending | |

## Experts log check

1. Mo tab `Experts` tren MT4.
2. Chay du S1-S6.
3. Xac nhan khong co dong `error`/`array out of range`/`zero divide`.

Ket qua:

- Experts runtime error: Pending
- Ghi chu:

## Ket luan Task 3.3

- Trang thai hien tai: `CLI/source validation done, waiting for manual MT4 execution`.
- Da co validation report cho build moi o `docs/testing/sprint-3-validation-report.md`.
- Can ban chay tay S1-S6 trong MT4 sau khi reload build `TradeAction.ex4` timestamp `2026-03-11 10:22:03` de dong dau `PASS/FAIL`.
