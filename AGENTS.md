# Repository Guidelines

## Project Structure & Module Organization
`TradeAction.mq4` is the single MT4 Expert Advisor source file. Keep new work grouped by responsibility: inputs and layout constants near the top, shared structs together, and behavior split into focused helpers for snapshot diffing, derived-field recalculation, timer refresh, and table drawing. `TradeAction.mqproj` stores MetaEditor project settings. `TradeAction.ex4` is the compiled artifact and should be rebuilt when source changes. Planning notes live in `docs/plans/`; manual validation assets and audit notes live in `docs/testing/`.

## Build, Test, and Development Commands
- `"C:\\Path\\To\\metaeditor.exe" /compile:"D:\\data\\source\\EA4_TradeActions\\TradeAction.mq4" /log:"D:\\data\\source\\EA4_TradeActions\\metaeditor-mt4-compile.log"` builds the EA; require `0 errors, 0 warnings`.
- Open `TradeAction.mqproj` in MetaEditor when you need the project UI or terminal-linked settings.
- After compiling, attach `TradeAction.ex4` to a demo MT4 chart and verify refresh behavior with inputs such as `InpRefreshIntervalMs` and `InpVisibleRows`.

## Coding Style & Naming Conventions
Use `#property strict` and preserve the existing MQL4 layout: 3-space indentation, opening braces on the next line, aligned declarations in input/constant blocks, and small helper functions with descriptive names. Follow current naming patterns: `Inp...` for user-configurable inputs, `TA_...` for constants, `g_...` for globals, `PascalCase` for structs/functions, and descriptive `camelCase` for locals.

## Testing Guidelines
This repo currently relies on compile validation plus manual MT4 checks rather than automated unit tests. For every behavior change:
- compile cleanly in MetaEditor;
- run the affected scenarios in `docs/testing/task-3.3-manual-scenario-matrix.md` (`M0-M2`, `S1-S6`);
- update `docs/testing/sprint-3-validation-report.md` when the expected behavior or evidence changes.
Always compare table values against MT4 Terminal Trade/History data and review the `Experts` log for runtime errors.

## Commit & Pull Request Guidelines
Recent history mixes a strong semantic example (`feat: support configurable visible rows and scrolling in TradeActions table`) with vague one-word subjects. Prefer semantic, imperative commits such as `fix: preserve measured timestamps during trim`; avoid messages like `test` or `ads`. PRs should summarize the user-visible behavior change, list the manual scenarios run, record compile status, and include a screenshot when table layout or columns change.

## Configuration & Safety
Use a demo account for manual trade validation. Do not commit broker credentials, terminal-specific secrets, or disposable local logs unless they are required as review evidence.
