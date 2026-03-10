# Plan: Track Open And Close Trade Actions In Chart Table

## Overview
The current `TradeAction.mq4` table only reads `MODE_TRADES`, so it shows active tickets and always sets `OpenOrClose=open`.  
The target behavior is an action log where each ticket can produce two rows: one open action and one close action.  
This plan introduces a stable event-tracking layer, then updates rendering to show action rows with consistent direction rules (`open buy -> buy`, `open sell -> sell`, `close buy -> sell`, `close sell -> buy`).

## Scope
- In scope: track open and close actions for current symbol tickets, map `OpenOrClose` and `TradeDirection`, and render rows in the chart table.
- In scope: compute existing columns (`ExecutionPrice`, `Exposure`, `Profit`, `Ticket`, `Symbol Name`, `Ticket Direction`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, `ProfitSinceStart`) from action events.
- Out of scope: persistent storage across terminal restart, multi-chart synchronization, and UI redesign outside current table layout.

## Assumptions (if any)
1. Tracking starts when the EA attaches; pre-existing open orders at attach time are seeded as `open` actions.
2. The table continues to focus on the current chart symbol (`OrderSymbol() == Symbol()`).
3. `MODE_HISTORY` contains closed trade details needed for close action enrichment on subsequent ticks.

## Open And Close Trade Actions In Chart Table: Column Formula Contract
This section aligns table formulas with `update-trade-data-async-trade-ticket-action.md` sections **2) Open/Close Detection Logic** and **3) TradeTicketAction Field Calculation**.

1. Action row creation gate (per ticket):
   - If ticket is first seen and is open: append one `open` action row.
   - If ticket was tracked as open and is now closed: append one `close` action row.
   - If ticket is first seen but already closed: append nothing.
   - If ticket remains open without state transition: append nothing.

2. Column formulas for each appended action row:
   - `OpenOrClose`:
     - `open` for first-seen open ticket.
     - `close` for tracked open -> closed transition.
   - `TradeDirection`:
     - `open`: same as ticket type.
     - `close`: opposite of ticket type (`close buy -> sell`, `close sell -> buy`).
   - `ExecutionPrice`:
     - `open`: ticket open price.
     - `close`: ticket close price from `MODE_HISTORY`.
   - `Exposure`:
     - `signedLots = +lots` when `TradeDirection=buy`, otherwise `-lots`.
     - `Exposure = Round(previousExposure + signedLots, 10)` where `previousExposure` defaults to `0`.
   - `Profit`:
     - `open`: `0` (no realized profit at open event time).
     - `close`: realized net profit from history (`OrderProfit + OrderSwap + OrderCommission`).
   - `Ticket`:
     - `OrderTicket()`.
   - `Symbol Name`:
     - `OrderSymbol()`.
   - `Ticket Direction`:
     - `BUY` when ticket type is buy, otherwise `SELL`.
   - `MillisecondsSinceLastAction`:
     - If prior symbol action exists: `(currentActionTime - previousActionTime).TotalMilliseconds`.
     - Else: `0`.
   - `PriceDifferenceFromPrevious`:
     - Initialize to `double.NegativeInfinity`.
     - Recompute only when prior symbol action exists, `Abs(previousExposure) > 0.000001`, and action direction changed.
     - If `buy` after previous `sell`: `Round(previousPrice - currentPrice, 10)`.
     - If `sell` after previous `buy`: `Round(currentPrice - previousPrice, 10)`.
   - `ProfitSinceStart`:
     - Initialize with `previousProfitSinceStart` (default `0`).
     - If `PriceDifferenceFromPrevious` is recomputed: `Round(previousProfitSinceStart + PriceDifferenceFromPrevious, 10)`.
     - If direction does not change: keep previous value unchanged.

## Sprint 1: Define Action Model And Runtime State
**Goal**: Create a data model for action rows and runtime snapshots for ticket tracking.
**Demo/Validation**:
- Command(s): compile `TradeAction.mq4` in MetaEditor.
- Verify: EA initializes without runtime errors and keeps the existing table visible.

### Task 1.1: Add TradeAction row schema and storage
- **Location**:
  - `TradeAction.mq4`
- **Description**: Add a `TradeAction` data structure and global containers to store ordered action rows, including all table columns plus action timestamp metadata.
- **Dependencies**:
  - `none`
- **Complexity**: 4
- **Acceptance criteria**:
  - Action schema includes explicit `OpenOrClose` and `TradeDirection` fields.
  - Schema supports all current table columns without losing existing output capabilities.
  - Direction mapping rules are captured in one helper function to avoid duplicated logic.
- **Validation**:
  - Build succeeds after introducing new types and globals.
  - Code review confirms one canonical mapping helper for open/close direction.

### Task 1.2: Add open-ticket snapshot model
- **Location**:
  - `TradeAction.mq4`
- **Description**: Add a snapshot representation for currently open BUY/SELL tickets and helper routines to capture current snapshot state per tick.
- **Dependencies**:
  - `Task 1.1`
- **Complexity**: 5
- **Acceptance criteria**:
  - Snapshot includes ticket id, type, lots, symbol, open price, and open time.
  - Snapshot capture filters to BUY/SELL and current symbol only.
  - Snapshot helper is independent from UI drawing.
- **Validation**:
  - Build succeeds with snapshot helpers.
  - Logging or debug checks confirm snapshot size matches expected open tickets.

### Task 1.3: Seed baseline state on EA attach
- **Location**:
  - `TradeAction.mq4`
- **Description**: Initialize action tracking at `OnInit` by reading existing open tickets and seeding initial `open` actions so the table has a consistent start state.
- **Dependencies**:
  - `Task 1.2`
- **Complexity**: 3
- **Acceptance criteria**:
  - Existing open BUY/SELL tickets at attach time generate initial `open` actions.
  - Baseline snapshot is stored for the next tick diff.
  - No duplicate seed rows appear when no new events occur.
- **Validation**:
  - Attach EA with existing positions and confirm one seeded `open` row per ticket.
  - Leave chart running without trading and confirm no additional rows are appended.

## Sprint 2: Detect Open And Close Events
**Goal**: Detect ticket lifecycle changes each tick and append correct action rows.
**Demo/Validation**:
- Command(s): run on demo account or strategy tester visual mode while opening and closing BUY/SELL tickets.
- Verify: each lifecycle event adds one action row with correct `OpenOrClose` and `TradeDirection`.

### Task 2.1: Detect open actions from snapshot diff
- **Location**:
  - `TradeAction.mq4`
- **Description**: Compare current open snapshot vs previous snapshot to detect newly opened tickets and append `open` actions with open-price metadata.
- **Dependencies**:
  - `Task 1.3`
- **Complexity**: 6
- **Acceptance criteria**:
  - Newly appeared BUY ticket appends `OpenOrClose=open`, `TradeDirection=buy`.
  - Newly appeared SELL ticket appends `OpenOrClose=open`, `TradeDirection=sell`.
  - Duplicate `open` rows are prevented across repeated ticks.
- **Validation**:
  - Open one BUY and one SELL; verify exactly two new rows with expected direction mapping.
  - Keep terminal idle for several ticks; verify row count remains unchanged.

### Task 2.2: Detect close actions and enrich from order history
- **Location**:
  - `TradeAction.mq4`
- **Description**: Detect tickets removed from open snapshot, locate corresponding closed orders in `MODE_HISTORY`, and append `close` actions with close price/time/profit.
- **Dependencies**:
  - `Task 2.1`
- **Complexity**: 8
- **Acceptance criteria**:
  - Closing BUY ticket appends `OpenOrClose=close`, `TradeDirection=sell`.
  - Closing SELL ticket appends `OpenOrClose=close`, `TradeDirection=buy`.
  - Close row includes close execution price and realized profit values from history order record.
- **Validation**:
  - Open and then close one BUY; verify a second row appears with close/sell semantics.
  - Open and then close one SELL; verify a second row appears with close/buy semantics.

### Task 2.3: Recalculate derived metrics on action sequence
- **Location**:
  - `TradeAction.mq4`
- **Description**: Compute `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, `Profit`, and `ProfitSinceStart` from ordered action rows using per-symbol last-action state and direction-change rules.
- **Dependencies**:
  - `Task 2.2`
- **Complexity**: 7
- **Acceptance criteria**:
  - `Exposure` uses `Round(previousExposure + signedLots, 10)` with signed lots derived from `TradeDirection`.
  - `MillisecondsSinceLastAction` is `0` for first action per symbol and delta-to-previous for subsequent actions.
  - `PriceDifferenceFromPrevious` only recalculates when action direction flips and prior exposure is non-zero; otherwise remains `double.NegativeInfinity`.
  - `ProfitSinceStart` is cumulative by action sequence (`previous + priceDifference` when recalculated), not equity snapshot delta.
  - `Profit` is `0` at open actions and realized net profit at close actions from history records.
- **Validation**:
  - Execute sequence `open buy -> close buy -> open sell -> close sell` and verify formula outputs match the column contract.
  - Verify same-direction consecutive actions do not change `PriceDifferenceFromPrevious` or `ProfitSinceStart`.

## Sprint 3: Render Stable Action Table And Verify Scenarios
**Goal**: Drive table rendering from action log and validate expected behavior for all four action types.
**Demo/Validation**:
- Command(s): attach EA to chart, perform scenario matrix (open buy, open sell, close buy, close sell), observe table rows.
- Verify: latest rows are readable, ordered, and semantically correct.

### Task 3.1: Refactor DrawTable to use action log rows
- **Location**:
  - `TradeAction.mq4`
- **Description**: Replace direct iteration over `OrdersTotal()` in table body rendering with a render path that reads the action log (latest `TA_MAX_ROWS` rows).
- **Dependencies**:
  - `Task 2.3`
- **Complexity**: 6
- **Acceptance criteria**:
  - Table body shows action log rows, not only currently open tickets.
  - Existing headers and alignment remain intact.
  - Empty-state message appears only when no actions were recorded since attach.
- **Validation**:
  - Start with no trades and verify empty state.
  - Perform one open/close cycle and verify two rows remain visible after close.

### Task 3.2: Stabilize ordering and row retention policy
- **Location**:
  - `TradeAction.mq4`
- **Description**: Enforce deterministic ordering (oldest-to-newest or newest-to-oldest, documented) and bounded retention so the UI remains stable under frequent trading.
- **Dependencies**:
  - `Task 3.1`
- **Complexity**: 5
- **Acceptance criteria**:
  - Display order is deterministic and documented in code comments.
  - Retention rule keeps recent rows within configured max without rendering artifacts.
  - Column values remain tied to the correct row after trimming.
- **Validation**:
  - Generate more than `TA_MAX_ROWS` actions and verify only retained rows are shown.
  - Confirm no object overlap or stale text after repeated updates.

### Task 3.3: Execute manual scenario matrix and acceptance checklist
- **Location**:
  - `TradeAction.mq4`
  - `TradeAction.mqproj`
- **Description**: Run a final manual matrix covering the four action types and verify each column meaning against expected outcomes.
- **Dependencies**:
  - `Task 3.2`
- **Complexity**: 4
- **Acceptance criteria**:
  - Matrix confirms all mappings:
  - open buy -> open/buy
  - open sell -> open/sell
  - close buy -> close/sell
  - close sell -> close/buy
  - Ticket, symbol, price, and profit columns are consistent with terminal order data.
- **Validation**:
  - Complete a test log with at least one full lifecycle for BUY and SELL tickets.
  - Confirm there are no runtime errors in Experts log during scenario execution.

## Testing Strategy
- Unit: isolate helper routines for direction mapping, snapshot diff, and derived metrics using deterministic input arrays where possible.
- Integration: compile and run in strategy tester visual mode to validate event detection and UI updates on tick flow.
- E2E/manual: execute live-demo scenario matrix on chart and compare table values with MT4 Terminal Trade/History tabs.

## Risks & gotchas
- `MODE_HISTORY` population timing may lag by one tick after close; close-event lookup should tolerate delayed availability.
- Partial closes can produce broker-specific behavior (same ticket lot reduction vs close/reopen patterns), which may require follow-up normalization.
- `OrderSelect` iteration order is not guaranteed stable, so sorting by action timestamp is required for deterministic rows.
- Recreating all chart objects every tick may flicker on high-frequency symbols; keep object naming and update cadence efficient.
- EA reattach resets in-memory action log; this is acceptable for current scope but should be documented to users.

## Rollback plan
- Keep the previous open-orders rendering path behind a temporary toggle input until action-log path is verified.
- If event tracking causes unstable output, switch toggle back to legacy rendering and disable append logic.
- Revert only `TradeAction.mq4` to last known stable commit if both rendering paths fail in production demo.
