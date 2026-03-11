# Plan: Audit And Fix TradeActions Derived Columns

## Overview
The current `TradeAction.mq4` implementation calculates `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, and `ProfitSinceStart` from the most recent row in the global action list, then recomputes them again with the same global assumptions. That diverges from the target contract, which is per-symbol, uses signed quantity from `TradeDirection`, and only derives price/profit deltas when the symbol already had exposure and the direction flips. This plan first locks down a reproducible verification matrix, then refactors derived-field calculation into one per-symbol pass, and finally validates the result against the example `Buy 0.1 @ 1.1000` -> `Sell 0.1 @ 1.1050`.

## Scope
- In scope: audit the current formulas for `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, and `ProfitSinceStart` in `TradeAction.mq4`.
- In scope: align the runtime calculation with the contract already captured in `docs/plans/update-trade-data-async-trade-ticket-action.md`.
- In scope: keep `Quantity` as an internal signed value used for calculation only, with no new UI column in the chart table.
- In scope: update manual verification steps so MT4 validation can prove each derived column row by row.
- Out of scope: persistence outside the EA process, redesigning the table layout, or changing unrelated columns such as `Ticket`, `SymbolName`, or `TicketDirection`.

## Assumptions (if any)
1. `MillisecondsSinceLastAction` should default to `0` when the symbol has no prior action, matching the existing project docs even though the user message omitted the final literal.
2. The chart table continues to display one retained action log, but derived values are computed from the last action state of the same `symbolName`, not blindly from the immediately previous row.
3. `PriceDifferenceFromPrevious` should be treated as "no value" when its gate conditions are not met, and the renderer may need a display helper so "no value" is not shown as a misleading numeric zero.
4. MQL4 will need a local helper equivalent to `Math.Round(value, 10)` because the file currently has no precision-rounding utility.

## Current mismatch snapshot
- `AppendOpenActionFromSnapshot` and `AppendCloseActionFromSnapshot` read `g_tradeActions[g_tradeActionCount - 1]` for prior exposure, prior timestamp, and prior price, so they use the last row globally instead of the last row for the same symbol.
- `RecalculateTradeActionDerivedFieldsCore` repeats the same global-row assumption and always sets `priceDifferenceFromPrevious = action.executionPrice - previousExecutionPrice`, even when exposure is already flat or the direction did not change.
- `profitSinceStart` is currently tied to `AccountEquity() - g_equityAtAttach`, which does not match the required cumulative price-difference logic.
- `SeedBaselineOpenActions` also seeds exposure, time delta, price delta, and profit from a global running state, so attach-time rows can already start from the wrong contract.

## Formula contract to verify
1. `signedQuantity`
   - `Buy = +quantity`
   - `Sell = -quantity`
2. `Exposure`
   - `Exposure = Round(previousExposure + signedQuantity, 10)`
   - `previousExposure` comes from the previous action of the same symbol and defaults to `0`
3. `MillisecondsSinceLastAction`
   - If the symbol has a previous action: `ticketTimestamp - last.Timestamp`
   - Otherwise: `0`
4. `PriceDifferenceFromPrevious`
   - Default: no value
   - Calculate only when the symbol has a previous action, `previousExposure != 0`, and the current direction is opposite to the previous action direction
   - `Buy after Sell: last.Price - price`
   - `Sell after Buy: price - last.Price`
5. `ProfitSinceStart`
   - Default: keep `previousProfit`
   - If `PriceDifferenceFromPrevious` exists: `Round(previousProfit + PriceDifferenceFromPrevious, 10)`

## Sprint 1: Lock The Audit Contract
**Goal**: Make the verification criteria explicit before changing the code so each derived column can be checked against a deterministic scenario matrix.
**Demo/Validation**:
- Command(s): review `TradeAction.mq4`, `docs/plans/update-trade-data-async-trade-ticket-action.md`, and `docs/testing/task-3.3-manual-scenario-matrix.md` side by side.
- Verify: every target formula and gate condition has a written test case and an expected row outcome.

### Task 1.1: Map current calculation points to the target contract
- **Location**:
  - `TradeAction.mq4`
  - `docs/plans/update-trade-data-async-trade-ticket-action.md`
- **Description**: Document which functions currently assign or recompute each derived column, then mark where the live code deviates from the per-symbol and direction-change contract.
- **Dependencies**:
  - none
- **Complexity**: 3
- **Acceptance criteria**:
  - The audit identifies all write points for `Exposure`, `MillisecondsSinceLastAction`, `PriceDifferenceFromPrevious`, and `ProfitSinceStart`.
  - The audit calls out the global-last-row dependency in append, recalc, and seed paths.
  - The audit captures the difference between current equity-based profit tracking and the required cumulative price-difference tracking.
- **Validation**:
  - Cross-check line locations in `TradeAction.mq4` against the contract section in `docs/plans/update-trade-data-async-trade-ticket-action.md`.
  - Confirm no derived-column write path is left undocumented.

### Task 1.2: Expand the manual scenario matrix for derived-column rules
- **Location**:
  - `docs/testing/task-3.3-manual-scenario-matrix.md`
- **Description**: Extend the existing manual test matrix with explicit expected values for the four target columns, including the user example and edge cases where price difference must stay empty.
- **Dependencies**:
  - `Task 1.1`
- **Complexity**: 4
- **Acceptance criteria**:
  - The matrix includes first-action, same-direction, opposite-direction, and flat-exposure transitions.
  - The matrix includes the example `open buy 0.1 @ 1.1000` followed by `close sell 0.1 @ 1.1050` with expected `Exposure=0` and `PriceDifferenceFromPrevious=0.005`.
  - The matrix states expected behavior when there is no prior action for the symbol.
- **Validation**:
  - Review the matrix and confirm each formula branch in the contract has at least one scenario.
  - Confirm the expected column values can be read without interpreting hidden assumptions.

### Task 1.3: Decide the internal representation for "no value"
- **Location**:
  - `TradeAction.mq4`
- **Description**: Choose how the code distinguishes a real numeric zero from "no value" for `PriceDifferenceFromPrevious` while keeping the chart table readable and avoiding ambiguous output.
- **Dependencies**:
  - `Task 1.1`
- **Complexity**: 3
- **Acceptance criteria**:
  - The plan selects one representation strategy for unavailable price difference data.
  - The chosen strategy can survive recalculation, trimming, and table rendering without being mistaken for `0.0`.
  - The chosen strategy does not require adding a visible `Quantity` column.
- **Validation**:
  - Review the chosen strategy against `DrawTable` formatting and confirm it can render "no value" distinctly.
  - Confirm the strategy does not break numeric accumulation in `ProfitSinceStart`.

## Sprint 2: Refactor Derived-Field Calculation
**Goal**: Move the derived-column logic into one deterministic per-symbol calculation pass and remove the current split between append-time guesses and global-row recomputation.
**Demo/Validation**:
- Command(s): compile `TradeAction.mq4` in MetaEditor after each refactor step.
- Verify: the EA still records open/close actions, and derived columns are produced from the new per-symbol engine rather than from append-time shortcuts.

### Task 2.1: Introduce per-symbol running state and signed-quantity helpers
- **Location**:
  - `TradeAction.mq4`
- **Description**: Add a small internal state model keyed by `symbolName` that stores the last action direction, last timestamp, last price, last exposure, and last cumulative profit, plus helpers for signed quantity and rounding to 10 decimals.
- **Dependencies**:
  - `Task 1.3`
- **Complexity**: 6
- **Acceptance criteria**:
  - Signed quantity is derived from `TradeDirection`, not from ticket identity alone.
  - The rounding helper is used for `Exposure`, `PriceDifferenceFromPrevious`, and `ProfitSinceStart`.
  - The state model supports per-symbol lookups during a single recalculation pass.
- **Validation**:
  - Build succeeds with the new helpers and state structure.
  - Code review confirms the state stores exactly the values needed by the target formulas.

### Task 2.2: Rewrite `RecalculateTradeActionDerivedFieldsCore` around the contract
- **Location**:
  - `TradeAction.mq4`
- **Description**: Replace the current global running exposure, previous timestamp, and previous price logic with a pass that resolves the previous action state for the same symbol and applies the contract gates before assigning each derived field.
- **Dependencies**:
  - `Task 2.1`
- **Complexity**: 8
- **Acceptance criteria**:
  - `Exposure` is recalculated as `Round(previousExposure + signedQuantity, 10)` per symbol.
  - `MillisecondsSinceLastAction` uses the previous action timestamp for the same symbol and defaults to `0`.
  - `PriceDifferenceFromPrevious` is only assigned when prior symbol action exists, prior exposure is non-zero, and direction flips.
  - `ProfitSinceStart` carries forward the previous per-symbol profit and only changes when a price difference is produced.
- **Validation**:
  - Run through the example sequence manually in code review and confirm the computed values match the contract.
  - Re-sort and recalc the full action log and confirm the output is deterministic.

### Task 2.3: Simplify append and seed paths so raw rows stay raw
- **Location**:
  - `TradeAction.mq4`
- **Description**: Remove or minimize append-time assignments that guess derived values from the current tail row, then let the centralized recalculation pass populate those fields for open actions, close actions, and attach-time seeded rows.
- **Dependencies**:
  - `Task 2.2`
- **Complexity**: 7
- **Acceptance criteria**:
  - `AppendOpenActionFromSnapshot`, `AppendCloseActionFromSnapshot`, and `SeedBaselineOpenActions` stop depending on `g_tradeActions[g_tradeActionCount - 1]` for derived-field correctness.
  - Derived values are populated consistently after sorting and recalculation.
  - The seed path follows the same formula contract as live open/close events.
- **Validation**:
  - Build succeeds after removing the duplicated append-time formulas.
  - Attach the EA with existing open trades and confirm seeded rows are recalculated without runtime errors.

### Task 2.4: Update table formatting for unavailable derived values
- **Location**:
  - `TradeAction.mq4`
- **Description**: Adjust row-to-string formatting so unavailable `PriceDifferenceFromPrevious` is rendered distinctly from numeric zero, while preserving current formatting for the rest of the table.
- **Dependencies**:
  - `Task 2.3`
- **Complexity**: 4
- **Acceptance criteria**:
  - A missing `PriceDifferenceFromPrevious` does not display as `0.00000` unless the real computed value is zero.
  - Numeric formatting still respects `Digits` for prices and stable precision for exposure/profit output.
  - No column title or layout change is required.
- **Validation**:
  - Review the table output for first-action rows and same-direction rows and confirm the absence state is visually distinct.
  - Confirm rows with real zero values still render as numeric zero.

## Sprint 3: Validate Against MT4 Scenarios
**Goal**: Prove the refactor against the documented formulas and guard against regressions in ordering, retention, and history-based close detection.
**Demo/Validation**:
- Command(s): compile `TradeAction.mq4`, attach the EA to a demo chart, and execute the manual scenarios in `docs/testing/task-3.3-manual-scenario-matrix.md`.
- Verify: every checked row matches the contract and the `Experts` tab stays free of runtime errors.

### Task 3.1: Execute the derived-column scenario matrix
- **Location**:
  - `docs/testing/task-3.3-manual-scenario-matrix.md`
  - `TradeAction.mq4`
- **Description**: Run the updated manual scenarios and mark actual values for the four target columns, with special attention to first action, opposite-direction close, and same-direction sequences.
- **Dependencies**:
  - `Task 2.4`
- **Complexity**: 5
- **Acceptance criteria**:
  - The scenario matrix records PASS or FAIL for each derived-column checkpoint.
  - The user example passes with the expected `0.005` price difference and cumulative profit update.
  - Same-direction scenarios prove that price difference remains unavailable and profit stays unchanged.
- **Validation**:
  - Compare MT4 table output row by row against the expected values written in the matrix.
  - Capture any mismatch with the exact action sequence and observed column values.

### Task 3.2: Regression-check sorting, trimming, and close detection
- **Location**:
  - `TradeAction.mq4`
- **Description**: Verify that the per-symbol recalculation still behaves correctly after action sorting, retention trimming, and delayed history availability for close actions.
- **Dependencies**:
  - `Task 3.1`
- **Complexity**: 6
- **Acceptance criteria**:
  - Recalculation after `SortTradeActionsByTime` produces stable values.
  - Log trimming does not corrupt the baseline needed to recompute retained rows.
  - Pending-close resolution still appends a close row once history data is available.
- **Validation**:
  - Exercise repeated open/close actions until the retained log tail is used and confirm no exposure drift appears.
  - Inspect the `Experts` tab for array errors, invalid values, or repeated close rows.

## Testing Strategy
- Static/code review: verify every assignment to the four derived columns now flows through the contract-based recalculation path.
- Build: compile `TradeAction.mq4` in MetaEditor after each sprint milestone and require `0 errors, 0 warnings`.
- Manual MT4 scenarios: execute the expanded matrix in `docs/testing/task-3.3-manual-scenario-matrix.md`, including the user example and same-direction edge cases.
- Regression: repeat attach-time seeding, history-delayed close detection, and retained-log trimming to confirm the refactor did not break event capture.

## Risks & gotchas
- MQL4 has no native generic dictionary, so per-symbol state must use a simple struct array or another deterministic lookup pattern; careless indexing can introduce subtle recalculation bugs.
- `Round(..., 10)` needs an explicit helper in MQL4; using display formatting alone is not enough because the contract affects subsequent arithmetic.
- If "no value" is stored as `0.0`, the UI will hide real logic errors by making unavailable price differences look valid.
- `TrimTradeActionLog` currently stores a single exposure baseline; if retained rows can ever mix symbols, the baseline strategy may need to evolve alongside the per-symbol refactor.
- MT4 history rows can appear one tick later than the close event, so validation must cover the pending-close path instead of assuming immediate history availability.

## Rollback plan
- Revert only the derived-field refactor in `TradeAction.mq4` if the new engine causes incorrect rows or runtime instability.
- Keep the expanded scenario matrix so the original bug remains documented even if the code rollback is needed.
- Re-run the pre-refactor compile and manual smoke scenarios to confirm the rollback restored the prior behavior before attempting another fix iteration.
