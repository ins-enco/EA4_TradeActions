# Plan: Move Table Refresh To OnTimer

## Overview
The current EA refreshes trade data and redraws the chart table from `OnTick()`, so refresh cadence depends on market activity for the attached chart symbol.  
The target behavior is a timer-driven refresh loop that polls trade state and redraws the table every configurable `N` milliseconds by using `EventSetMillisecondTimer(...)` and `OnTimer()`.  
This plan keeps the existing trade-action detection and table rendering logic, but moves periodic orchestration out of `OnTick()`, adds timer lifecycle management, and validates that the UI still updates on quiet charts with no incoming ticks.

## Scope
- In scope: introduce a configurable refresh interval in milliseconds and initialize a millisecond timer during EA startup.
- In scope: move periodic `RefreshOpenTicketSnapshot(true)` and `DrawTable()` execution from `OnTick()` to `OnTimer()`.
- In scope: refactor shared refresh logic so `OnInit()` and `OnTimer()` reuse one orchestration path.
- In scope: remove temporary `OnTick()` timing instrumentation and the current duplicate refresh/draw calls after the timer path is in place.
- In scope: add timer cleanup, re-entry protection, and basic diagnostics for timer setup or cadence drift.
- Out of scope: changing column formulas, redesigning the table UI, persisting state across terminal restart, or rewriting the open/close detection model.

## Assumptions (if any)
1. The target MT4 build supports `EventSetMillisecondTimer(...)` for Expert Advisors on the deployment machines.
2. Polling `MODE_TRADES` and `MODE_HISTORY` from `OnTimer()` is acceptable even when no chart tick arrives.
3. A default timer interval around `200 ms` is acceptable as the initial configurable value, with bounds to prevent overly aggressive redraw frequency.
4. Existing pending-close resolution remains valid under timer polling, even if broker history population lags slightly after a close event.

## Sprint 1: Introduce Timer Configuration And Shared Refresh Flow
**Goal**: Define a single refresh pipeline and add timer configuration without changing trade-action formulas.
**Demo/Validation**:
- Command(s): compile `TradeAction.mq4` in MetaEditor.
- Verify: EA still initializes, seeds baseline actions, and renders the table once on attach with no runtime errors.

### Task 1.1: Add configurable timer interval input
- **Location**:
  - `TradeAction.mq4`
- **Description**: Add an input such as `InpRefreshIntervalMs` plus a small normalization helper so the EA can clamp invalid values to a safe minimum and maximum before starting the timer.
- **Dependencies**:
  - `none`
- **Complexity**: 2
- **Acceptance criteria**:
  - Refresh cadence is configurable in milliseconds from EA inputs.
  - Invalid values are normalized to documented bounds instead of silently creating unstable behavior.
  - The chosen effective interval is available to logging and lifecycle code.
- **Validation**:
  - Build succeeds after introducing the input and helper.
  - Code review confirms there is one canonical source for the effective timer interval.

### Task 1.2: Extract a shared refresh orchestrator
- **Location**:
  - `TradeAction.mq4`
- **Description**: Create a helper such as `RefreshTradeActionView(bool detectNewActions, bool redrawTable)` or similar so `OnInit()` and `OnTimer()` can reuse the same refresh pipeline instead of duplicating `RefreshOpenTicketSnapshot(...)` and `DrawTable()`.
- **Dependencies**:
  - `Task 1.1`
- **Complexity**: 4
- **Acceptance criteria**:
  - Baseline initialization and periodic refresh use the same orchestration helper.
  - The helper keeps refresh responsibilities explicit: snapshot polling, derived-field recalculation, and optional redraw.
  - Current temporary `OnTick()` timing code is identified for removal during the migration.
- **Validation**:
  - Build succeeds after extracting the helper.
  - Attach-time behavior remains equivalent to the current one-time render path.

### Task 1.3: Add timer lifecycle management
- **Location**:
  - `TradeAction.mq4`
- **Description**: Start the millisecond timer in `OnInit()` after initial state setup, and stop it in `OnDeinit()` by calling `EventKillTimer()` exactly once per EA lifecycle.
- **Dependencies**:
  - `Task 1.2`
- **Complexity**: 4
- **Acceptance criteria**:
  - `OnInit()` starts the timer only after baseline state is ready.
  - `OnDeinit()` always releases the timer before clearing chart objects.
  - Timer setup failure is logged clearly and results in a predictable fallback or init failure path.
- **Validation**:
  - Build succeeds with `OnTimer()` declaration and lifecycle hooks.
  - Attach/detach the EA and confirm no timer-related runtime errors appear in `Experts`.

## Sprint 2: Move Periodic Refresh From OnTick To OnTimer
**Goal**: Make `OnTimer()` the sole periodic driver for snapshot refresh and table redraw.
**Demo/Validation**:
- Command(s): attach EA to a quiet chart, leave the market idle, then open/close trades from another chart or terminal panel.
- Verify: the table updates within the configured timer interval even when the attached chart symbol does not receive fresh ticks.

### Task 2.1: Implement the `OnTimer()` refresh path
- **Location**:
  - `TradeAction.mq4`
- **Description**: Move periodic calls to `RefreshOpenTicketSnapshot(true)` and `DrawTable()` into `OnTimer()` through the shared orchestration helper while keeping `OnInit()` responsible for the initial seeded render.
- **Dependencies**:
  - `Task 1.3`
- **Complexity**: 5
- **Acceptance criteria**:
  - `OnTimer()` becomes the regular refresh path for both data polling and UI redraw.
  - Open/close action detection still appends rows correctly when polled from timer events.
  - The table continues to show the latest retained rows and empty state exactly as before.
- **Validation**:
  - Open a trade while the chart is quiet and confirm the row appears without waiting for a chart tick.
  - Close a tracked trade and confirm pending-close resolution still works under timer polling.

### Task 2.2: Remove refresh responsibility from `OnTick()`
- **Location**:
  - `TradeAction.mq4`
- **Description**: Delete the current timing instrumentation and duplicate refresh/draw sequence from `OnTick()`, then reduce `OnTick()` to either a no-op stub or a minimal compatibility hook with no table-refresh responsibility.
- **Dependencies**:
  - `Task 2.1`
- **Complexity**: 3
- **Acceptance criteria**:
  - `OnTick()` no longer calls `RefreshOpenTicketSnapshot(true)` or `DrawTable()`.
  - `OnTick()` no longer emits interval/exec debug spam during normal operation.
  - There is exactly one periodic refresh owner in the EA: `OnTimer()`.
- **Validation**:
  - Run with active ticks and confirm no duplicate refresh side effects or duplicate log messages remain.
  - Code review confirms the timer path is the only recurring redraw trigger.

### Task 2.3: Add timer re-entry and cadence safeguards
- **Location**:
  - `TradeAction.mq4`
- **Description**: Add a small runtime guard (for example a boolean in-progress flag and/or last-run timestamp) so the EA behaves safely when redraw time approaches or exceeds the configured timer interval.
- **Dependencies**:
  - `Task 2.2`
- **Complexity**: 5
- **Acceptance criteria**:
  - Timer re-entry cannot corrupt shared arrays or cause overlapping refresh work.
  - If actual processing time exceeds the requested interval, behavior degrades safely instead of stacking redraw work.
  - Optional debug logging can surface timer slippage when diagnosing performance.
- **Validation**:
  - Temporarily configure a very small interval and confirm the EA remains stable with no object corruption or runtime errors.
  - Verify no duplicate rows are appended during rapid timer firing.

## Sprint 3: Tune Performance And Verify Timer-Driven Behavior
**Goal**: Keep redraw behavior stable and efficient under fixed-interval polling.
**Demo/Validation**:
- Command(s): run manual checks at multiple timer intervals such as `100`, `200`, and `500` ms.
- Verify: the table remains readable, does not flicker excessively, and preserves correct action semantics.

### Task 3.1: Reduce unnecessary redraw churn
- **Location**:
  - `TradeAction.mq4`
- **Description**: Review whether the timer path should always redraw the table or only redraw when relevant state changes (trade-action count/content, panel width, or empty/non-empty state) so fixed-interval polling does not recreate objects more often than needed.
- **Dependencies**:
  - `Task 2.3`
- **Complexity**: 6
- **Acceptance criteria**:
  - Polling cadence remains timer-driven even if full redraws are skipped when nothing visible changed.
  - Chart object churn is reduced enough to avoid obvious flicker or CPU spikes at practical intervals.
  - The chosen redraw policy is documented in code comments or plan follow-up notes.
- **Validation**:
  - Compare behavior at `100 ms` and `500 ms` intervals and confirm the chart remains stable.
  - Resize the chart and confirm layout still redraws correctly when needed.

### Task 3.2: Validate timer-driven update scenarios
- **Location**:
  - `TradeAction.mq4`
  - `docs/testing/sprint-3-validation-report.md`
- **Description**: Execute a focused scenario matrix that verifies timer-driven refresh on quiet charts, normal charts, and trade open/close transitions, then capture observed results in the existing validation notes if the project keeps manual evidence there.
- **Dependencies**:
  - `Task 3.1`
- **Complexity**: 4
- **Acceptance criteria**:
  - Quiet-chart scenario proves the table updates without relying on new ticks for the attached symbol.
  - Open and close actions still map correctly to all derived columns.
  - Deinitialization removes timer resources and leaves no stale chart objects behind.
- **Validation**:
  - Record requested interval versus observed update lag in `Experts` or manual notes.
  - Confirm attach, runtime refresh, and detach each complete without errors.

## Testing Strategy
- Unit: keep timer interval normalization, refresh guard, and orchestration helper small enough for deterministic code review and localized debugging.
- Integration: compile `TradeAction.mq4`, attach to a chart, and verify initialization, timer startup, periodic refresh, and deinitialization.
- Manual: test at multiple intervals (`100`, `200`, `500` ms) on both active and quiet symbols, then compare chart output with Terminal Trade/History tabs.
- Regression: verify open/close detection, derived columns, pending-close resolution, and empty-state rendering remain unchanged after timer migration.

## Risks & gotchas
- MT4 timer events are not a hard real-time scheduler; effective cadence can drift above the configured `N` milliseconds when the terminal is busy.
- If one timer event is still queued or executing, additional timer events may be coalesced rather than stacked, so observed refresh spacing may exceed the requested interval.
- `DrawTable()` currently clears and recreates many chart objects; aggressive timer intervals can increase CPU usage or visible flicker.
- `MODE_HISTORY` may still populate one polling cycle later after a close, so the existing pending-close queue remains important even after moving away from tick-driven refresh.
- If `EventSetMillisecondTimer(...)` is unavailable or unstable on a target terminal build, the implementation may need a fallback path or explicit initialization failure.

## Rollback plan
- Keep the old `OnTick()` refresh path recoverable in local history until the timer path is validated on the target terminal.
- If timer-driven refresh proves unstable, temporarily disable the timer and restore `OnTick()` as the periodic refresh owner.
- Revert only `TradeAction.mq4` if the migration introduces regressions; existing action-detection logic can remain untouched while the scheduling layer is rolled back.
