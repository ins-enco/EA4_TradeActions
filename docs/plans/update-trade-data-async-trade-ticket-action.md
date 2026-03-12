# UpdateTradeDataAsync: TradeTicketAction Calculation and Persistence

## Scope

This document explains how trade actions are detected, calculated, and saved when `UpdateTradeDataAsync` runs.

- Orchestrator call path:
  - `DataFetcher/DataFetcher.cs` -> `FetchTradeDataAsync(...)`
  - `DataFetcher/AppService.cs` -> `FetchMultipleTradesAsync(...)`
  - `DataFetcher/Implements/DataWorker.cs` -> `UpdateTradeDataAsync(CancellationToken token)`
- Action builder:
  - `DataFetcher/Implements/DataWorker.cs` -> `CreateTradeTicketAction(...)`
- Persistence:
  - `DataFetcher/Repository/DataRepository.cs` -> `InsertTradeTicketActions(...)`
  - `DataFetcher/Repository/Tables.cs` -> table `TradeTicketActions`

## 1) Input and Ticket Normalization

`UpdateTradeDataAsync` reads live trade books from MT4 client:

1. Check policy `WorkFlags.FetchTrades`.  
2. Fetch current tickets with `client.GetTradeBooksAsync(token)`.  
3. Convert `OpenTime` / `CloseTime` to UTC `DateTime` using ticks (no timezone conversion).  
4. Skip non-position ticket types (`item.Type >= TradeType.Balance`).  

For each ticket, a `TradeBook` snapshot is built (used only for in-memory open/close tracking).

## 2) Open/Close Detection Logic

`DataWorker` uses `previousTradebooks` dictionary (`ticketId -> last seen open TradeBook`) to detect state transitions.

### A. New ticket (`!previousTradebooks.ContainsKey(ticket)`)

- If current ticket is **open** (`!item.IsClosed`):
  - Create **Open** action.
- If current ticket is already **closed** when first seen:
  - No action is created (the open/close happened before this worker observed it).

### B. Existing tracked ticket

- If previously open and now closed:
  - Create **Close** action.
- Otherwise:
  - No action.

### C. Tracking update after each ticket

- If ticket is open: keep/update it in `previousTradebooks`.
- If ticket is closed: remove it from `previousTradebooks`.

## 3) TradeTicketAction Field Calculation

`CreateTradeTicketAction(...)` computes fields in this order.

### 3.1 Direction fields

- `TicketDirection` (original ticket type):
  - `Buy` if `ticketType == TradeType.Buy`, else `Sell`.
- `TradeDirection` (actual action direction):
  - For `Open`: same as `TicketDirection`.
  - For `Close`: opposite of `TicketDirection`.
    - Close Buy -> Sell
    - Close Sell -> Buy

### 3.2 Signed quantity

- `Quantity = +quantity` when `TradeDirection == Buy`
- `Quantity = -quantity` when `TradeDirection == Sell`

### 3.3 Exposure

Per-symbol running exposure is stored in `lastActionDataPerSymbol`.

- `previousExposure` defaults to `0` if no prior action for symbol.
- `Exposure = Round(previousExposure + signedQuantity, 10)`

### 3.4 Time since last action

- If prior action exists for the symbol:
  - `MillisecondsSinceLastAction = (ticketTimestamp - last.Timestamp).TotalMilliseconds`
- Else:
  - `MillisecondsSinceLastAction = 0`

### 3.5 PriceDifferenceFromPrevious and ProfitSinceStart

Initialization:

- `PriceDifferenceFromPrevious = double.NegativeInfinity`
- `newProfit = previousProfit` (from prior action; default `0`)

Computation only happens when:

- prior symbol action exists, and
- `Abs(previousExposure) > 0.000001`, and
- direction changed (Buy after Sell, or Sell after Buy).

Formulas:

- Buy after Sell:
  - `PriceDifferenceFromPrevious = Round(last.Price - price, 10)`
- Sell after Buy:
  - `PriceDifferenceFromPrevious = Round(price - last.Price, 10)`
- Then:
  - `ProfitSinceStart = Round(previousProfit + PriceDifferenceFromPrevious, 10)`

If direction is the same (Buy->Buy or Sell->Sell), price difference is left as `double.NegativeInfinity` and profit is unchanged.

## 4) Save Payload Mapping

Each `TradeTicketAction` record is mapped as:

- Identity/context:
  - `TicketID`, `Login`, `TradeAccountID`, `SymbolName`
- Timestamps:
  - `TicketTimestamp` = open time for Open action, close time for Close action
  - `MeasuredTimestamp` = `DateTime.UtcNow` at record creation
- Action identity:
  - `OpenOrClose`, `TicketDirection`, `TradeDirection`
- Metrics:
  - `Price`, `Quantity` (signed), `Exposure`, `MillisecondsSinceLastAction`,
    `PriceDifferenceFromPrevious`, `ProfitSinceStart`

After building the record, `lastActionDataPerSymbol[symbol]` is immediately updated with new timestamp, price, action direction, exposure, and cumulative profit.

## 4.1) Deterministic ordering contract for merged action logs

For consumers that render one merged action log across symbols and tickets, the ordering contract should be based on broker event time, not on measured record-creation time.

- Primary key:
  - `TicketTimestamp` ascending
  - For MT4 table parity work, this maps to broker `actionTimeMs`
- Tie-break 1:
  - `Open` before `Close`
- Tie-break 2:
  - lower `TicketID` before higher `TicketID`
- No grouping:
  - `SymbolName` does not participate in ordering
- `MeasuredTimestamp` role:
  - keep for diagnostics / UI display
  - keep as the source for elapsed-time fields such as `MillisecondsSinceLastAction`
  - do not use as the ordering key

If a close action is materialized later because history arrives after the initial detection pass, the row may be appended later in memory but should settle into the position dictated by `TicketTimestamp` after sorting.

## 5) Persistence Path

At end of loop in `UpdateTradeDataAsync`:

- If `tradeTicketActions.Count > 0`:
  - `repository.InsertTradeTicketActions(tradeTicketActions)`

Repository implementation:

- `DataRepository.InsertTradeTicketActions(...)` inserts each action row into `_tables.TradeTicketActions`.
- `Tables.ConnectSecondaryTables()` maps `_tables.TradeTicketActions` to DB table name `TradeTicketActions` with `AllowCreate`.

So persistence is per-record insert into table `TradeTicketActions`.

## 6) Restart Behavior (State Recovery)

When worker starts, `LoadPreviousState()` reconstructs state from DB:

- Rebuilds `previousTradebooks` for tickets that still have no Close action.
- Rebuilds `lastActionDataPerSymbol` from latest action per symbol.

This prevents duplicate Open actions after app restart and keeps exposure/profit continuity.
