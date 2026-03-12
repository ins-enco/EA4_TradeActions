# Plan: Sort TradeActions By Action Time

## Overview
The current `TradeAction.mq4` implementation sorts the action log by `MeasuredTimestamp` when available and falls back to `actionTimeMs` only when `MeasuredTimestamp` is absent. That makes row order depend on local detection time even though the user-visible contract should be based on the broker/MT4 event time for open and close actions. This plan changes the ordering contract so the table always sorts ascending by `actionTimeMs`, then breaks ties with `open` before `close`, then lower `ticket` first, while keeping `MeasuredTimestamp` available for display and `MillisecondsSinceLastAction`.

## Scope
- In scope: update the action-log ordering contract in `TradeAction.mq4` so display order and recalculation order no longer depend on `MeasuredTimestamp`.
- In scope: preserve the existing `MeasuredTimestamp` column and the `MillisecondsSinceLastAction` formula that still depends on measured local time.
- In scope: verify deterministic ordering for mixed symbols, mixed tickets, baseline rows without measured timestamps, and delayed close-history resolution.
- In scope: update manual validation docs so MT4 testing can prove the new ordering behavior.
- Out of scope: changing derived-field formulas, changing table layout, changing retention/scroll limits, or filtering actions by chart symbol.

## Assumptions (if any)
1. Every `TradeActionRow` continues to have a valid `actionTimeMs` populated from `OrderOpenTime()` or `OrderCloseTime()` for both open and close rows.
2. `actionTimeMs` remains second-resolution because it is derived from MT4 `datetime`, so same-second collisions across symbols and tickets are expected and must be resolved by the tie-break rules.
3. It is acceptable that a close row discovered later through pending-history resolution can be inserted earlier in the table if its broker close time is earlier than later-detected actions.
4. `MeasuredTimestamp` remains useful for diagnostics and for `MillisecondsSinceLastAction`, even though it will no longer control row ordering.

## Current ordering snapshot
- `SortTradeActionsByTime()` currently compares `GetTradeActionSequenceTimeMs(...)`, which prioritizes `measuredTimestampMs` when `hasMeasuredTimestamp == true` and only falls back to `actionTimeMs` otherwise.
- Newly detected open and close rows call `SetMeasuredTimestampNow()` before append, so in practice many rows are ordered by local detection time rather than broker action time.
- Seeded baseline rows call `ClearMeasuredTimestamp()`, so baseline rows are currently ordered by `actionTimeMs` while live rows are often ordered by measured local time.
- `RecalculateTradeActionDerivedFields()` sorts the whole log before recalculating derived values, so any ordering change affects both the table and the per-symbol recomputation pass.

## Target ordering contract
1. Primary key: ascending `actionTimeMs`
2. First tie-break: `open` before `close`
3. Second tie-break: lower `ticket` before higher `ticket`
4. No ordering by `symbolName`
5. No ordering by `MeasuredTimestamp`

## Sprint 1: Lock The New Ordering Contract
**Goal**: Make the new sort behavior explicit in code-review terms and in manual validation before changing the comparator.
**Demo/Validation**:
- Command(s): review `TradeAction.mq4`, `docs/testing/task-3.3-manual-scenario-matrix.md`, and `docs/testing/sprint-3-validation-report.md`.
- Verify: the planned ordering rules are written down with clear expected outcomes for mixed symbols, same-second ties, and delayed close resolution.

### Task 1.1: Map every code path that depends on action ordering
- **Location**:
  - `TradeAction.mq4`
- **Description**: Audit the current ordering flow from append paths through `SortTradeActionsByTime()`, `RecalculateTradeActionDerivedFields()`, and table rendering so the refactor changes the comparator without accidentally changing unrelated measured-time logic.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - The audit identifies all call sites that depend on sorted `g_tradeActions`.
  - The audit explicitly separates ordering concerns from `MeasuredTimestamp` display and `MillisecondsSinceLastAction` calculations.
  - The audit notes where a row discovered late can be reinserted into an older broker-time slot after sorting.
- **Validation**:
  - Cross-check the audit against `SortTradeActionsByTime()`, `GetTradeActionSequenceTimeMs()`, `RecalculateTradeActionDerivedFields()`, and `DrawTable()`.
  - Confirm no ordering-dependent path is left undocumented.

### Task 1.2: Expand the manual scenario matrix for ordering cases
- **Location**:
  - `docs/testing/task-3.3-manual-scenario-matrix.md`
- **Description**: Add explicit scenarios for ordering across multiple symbols and tickets, with emphasis on same-second events, baseline rows without `MeasuredTimestamp`, and a close row whose history appears after a later event was already displayed.
- **Dependencies**:
  - `Task 1.1`
- **Complexity**: 4
- **Acceptance criteria**:
  - The matrix includes at least one multi-symbol sequence where two or more actions share the same broker-second.
  - The matrix includes a same-ticket open/close pair that shares the same `actionTimeMs` and proves `open` appears before `close`.
  - The matrix includes a pending-close case that documents the expected row movement once history data becomes available.
- **Validation**:
  - Review the matrix and confirm every branch of the new ordering contract has a written expected result.
  - Confirm the scenarios can be executed manually in MT4 without hidden assumptions.

### Task 1.3: Document the ordering contract and user-facing implications
- **Location**:
  - `docs/testing/sprint-3-validation-report.md`
  - `docs/plans/update-trade-data-async-trade-ticket-action.md`
- **Description**: Prepare the documentation changes needed to explain that table order follows broker action time, not measured local detection time, while the measured timestamp column still remains visible.
- **Dependencies**:
  - `Task 1.2`
- **Complexity**: 3
- **Acceptance criteria**:
  - The docs explain the new primary sort key and both tie-break rules.
  - The docs call out that `MeasuredTimestamp` is still used for diagnostics and for `MillisecondsSinceLastAction`.
  - The docs mention the expected behavior when a close row is resolved later from `MODE_HISTORY`.
- **Validation**:
  - Review the doc text against the target contract and confirm there is no wording that still implies measured-time ordering.
  - Confirm the documentation stays consistent with the existing column definitions.

## Sprint 2: Refactor The Comparator To Use Broker Action Time
**Goal**: Replace measured-time ordering with an explicit broker-time comparator while keeping derived-field and rendering behavior deterministic.
**Demo/Validation**:
- Command(s): compile `TradeAction.mq4` in MetaEditor after each comparator-related edit.
- Verify: `TradeAction.ex4` builds cleanly and the sorted log order matches the new contract in code review.

### Task 2.1: Replace sequence-time lookup with action-time-only comparison
- **Location**:
  - `TradeAction.mq4`
- **Description**: Remove the measured-time priority from the ordering helper by either rewriting `GetTradeActionSequenceTimeMs()` to return `actionTimeMs` only or replacing it with a new helper whose name matches the new contract.
- **Dependencies**:
  - `Task 1.3`
- **Complexity**: 4
- **Acceptance criteria**:
  - The sort helper no longer checks `hasMeasuredTimestamp` or `measuredTimestampMs`.
  - The helper name and comments clearly describe broker-time ordering.
  - No remaining comparator path uses `MeasuredTimestamp` as an ordering input.
- **Validation**:
  - Code review confirms that only `actionTimeMs` feeds the primary sort key.
  - Build succeeds with `0 errors, 0 warnings`.

### Task 2.2: Keep deterministic tie-break behavior for same-second collisions
- **Location**:
  - `TradeAction.mq4`
- **Description**: Preserve and clarify the tie-break rules inside `SortTradeActionsByTime()` so rows with equal `actionTimeMs` always sort `open` before `close`, then by ascending `ticket`.
- **Dependencies**:
  - `Task 2.1`
- **Complexity**: 3
- **Acceptance criteria**:
  - `open` rows sort before `close` rows when `actionTimeMs` matches.
  - Equal-time rows of the same open/close type sort by ascending `ticket`.
  - No extra symbol-based tie-break is introduced.
- **Validation**:
  - Walk through a same-second open/close example in code review and confirm the final order.
  - Build succeeds after the comparator update.

### Task 2.3: Audit recalculation and baseline behavior under the new ordering
- **Location**:
  - `TradeAction.mq4`
- **Description**: Review `RecalculateTradeActionDerivedFieldsCore()`, `TrimTradeActionLog()`, and baseline seeding to confirm they still behave correctly when sort order is driven only by broker action time.
- **Dependencies**:
  - `Task 2.2`
- **Complexity**: 5
- **Acceptance criteria**:
  - Derived-field recomputation still processes rows in a deterministic order.
  - Baseline rows without `MeasuredTimestamp` remain valid because they already have `actionTimeMs`.
  - Trim/rebaseline logic remains correct after the comparator change.
- **Validation**:
  - Re-sort and recalc the log in code review and confirm no path assumes measured-time order.
  - Build succeeds after any compatibility adjustments.

### Task 2.4: Update comments and render-state reasoning to match the new contract
- **Location**:
  - `TradeAction.mq4`
- **Description**: Refresh inline comments and any sort-related naming so future maintenance does not confuse render ordering with measured-time diagnostics.
- **Dependencies**:
  - `Task 2.3`
- **Complexity**: 2
- **Acceptance criteria**:
  - `SortTradeActionsByTime()` comment block matches the final comparator.
  - Any helper name tied to the old measured-time logic is updated or removed.
  - The code makes it clear that `MeasuredTimestamp` affects display and elapsed-time fields, not sort order.
- **Validation**:
  - Read the edited comments and helper names in a cold review and confirm the behavior is obvious without digging through call sites.

## Sprint 3: Validate Mixed-Symbol Ordering In MT4
**Goal**: Prove the new ordering in real MT4 scenarios and catch regressions caused by delayed history, retention, or redraw behavior.
**Demo/Validation**:
- Command(s): compile `TradeAction.mq4`, attach the EA to a demo chart, and execute the ordering scenarios in `docs/testing/task-3.3-manual-scenario-matrix.md`.
- Verify: the rendered order matches broker action time, tie-break rules behave deterministically, and the `Experts` tab stays free of runtime errors.

### Task 3.1: Execute mixed-symbol and same-second ordering scenarios
- **Location**:
  - `docs/testing/task-3.3-manual-scenario-matrix.md`
  - `TradeAction.mq4`
- **Description**: Run the new manual scenarios with multiple symbols and tickets so the table order can be checked directly against MT4 open/close timestamps and ticket numbers.
- **Dependencies**:
  - `Task 2.4`
- **Complexity**: 5
- **Acceptance criteria**:
  - Multi-symbol actions are ordered by `actionTimeMs`, not by `MeasuredTimestamp`.
  - Same-second rows follow `open -> close -> lower ticket`.
  - Baseline rows and newly detected rows coexist in the correct chronological order.
- **Validation**:
  - Compare table order against MT4 `Trade` and `Account History` timestamps plus ticket IDs.
  - Record PASS or FAIL per scenario in the manual matrix.

### Task 3.2: Regression-check pending close resolution and row movement
- **Location**:
  - `TradeAction.mq4`
  - `docs/testing/task-3.3-manual-scenario-matrix.md`
- **Description**: Verify that when close-history data appears later, the appended close row is sorted into the correct broker-time position rather than staying at the append position.
- **Dependencies**:
  - `Task 3.1`
- **Complexity**: 4
- **Acceptance criteria**:
  - A delayed close row lands in the correct action-time slot after sorting.
  - No duplicate close rows appear during pending-resolution retries.
  - The resulting order remains deterministic across repeated timer cycles.
- **Validation**:
  - Exercise a close event where history is delayed by at least one timer cycle and observe the row movement.
  - Inspect the `Experts` tab for duplicate detection logs or runtime errors.

### Task 3.3: Regression-check retention, scrolling, and redraw stability
- **Location**:
  - `TradeAction.mq4`
- **Description**: Confirm the new ordering still cooperates with retained-log trimming, visible-row windowing, scroll buttons, and redraw hashing.
- **Dependencies**:
  - `Task 3.2`
- **Complexity**: 4
- **Acceptance criteria**:
  - Trimming retained rows does not corrupt ordering of the surviving tail.
  - Scrolling older/newer rows still traverses a stable chronological order.
  - Redraw behavior does not flicker or miss updates when rows are re-ordered by broker action time.
- **Validation**:
  - Generate enough actions to scroll the table and confirm each viewport remains correctly ordered.
  - Review the rendered table after repeated timer cycles and confirm no stale order remains on screen.

## Testing Strategy
- Static/code review: verify every sort comparison now uses `actionTimeMs` as the only primary time source.
- Build: compile `TradeAction.mq4` in MetaEditor after each sprint milestone and require `0 errors, 0 warnings`.
- Manual MT4 ordering scenarios: execute mixed-symbol, same-second, baseline, and delayed-history cases from `docs/testing/task-3.3-manual-scenario-matrix.md`.
- Regression: repeat retention/scroll scenarios to confirm the comparator change did not destabilize viewport behavior or row reordering after timer refreshes.

## Risks & gotchas
- `actionTimeMs` has only second-level resolution, so ties will be more common than under measured local milliseconds; the tie-break rules must therefore be treated as part of the contract, not as an implementation detail.
- A close row discovered later from `MODE_HISTORY` can move upward into an earlier broker-time slot after the next sort; this is correct under the new contract but can surprise users if the behavior is not documented.
- `MeasuredTimestamp` and `MillisecondsSinceLastAction` may no longer visually "line up" with row order in fast sequences, because they remain local-detection concepts while sorting becomes broker-time based.
- The EA currently collects trackable orders across symbols because the symbol filter is commented out, so manual validation must account for account-wide mixed-symbol ordering rather than assuming chart-symbol isolation.
- Any helper or comment that still mentions measured-time priority can mislead future maintenance even if the comparator code is correct.

## Rollback plan
- Revert the comparator/helper changes in `TradeAction.mq4` to restore measured-time-first ordering if the new contract causes incorrect sequences or unacceptable user confusion.
- Revert the ordering-specific doc changes so the written contract matches the restored behavior.
- Re-run the pre-change compile and manual smoke scenarios to confirm rollback restored the prior ordering semantics.
