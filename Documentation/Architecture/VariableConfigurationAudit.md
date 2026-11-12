# Variable and configuration audit

## Scope and status

A literal semantic audit of every global/member/local variable in 192 MQL5 sources is not complete. This report distinguishes verified facts from required follow-up; it does not fabricate a variable-by-variable pass. `Core/Config.mqh`, `QME_Main.mq5`, key runtime/data/signal/execution/persistence owners and safety defaults were inspected. Static tools passed but are heuristic.

## Configuration safety

`test_system.py` verifies defaults: `InpAnalysisOnly=true`, `InpEnableDemoTrading=false`, `InpEnableRealTrading=false`, `InpRealTradingArmed=false`, `InpCloseOnOppositeSignal=false`. These values remain unchanged. Input-to-config propagation, all bounds, and accepted-but-ignored parameters have not been exhaustively verified; do not infer that every input is effective from this test.

## High-value owned state reviewed

| State | Type / owner / initialization and mutation | Risk and evidence |
|---|---|---|
| Indicator handles and periods | integer handles/periods in `CIndicatorCache`; `Reset` assigns invalid handles/default periods; `Init` creates and `Release` releases handles. | `Ready` checks BarsCalculated; series/value reads guard negative shifts/counts and CopyBuffer result. MT5 handle lifecycle still requires terminal tests. |
| Scanner session and runtime snapshots | `SSessionResult` and analysis/snapshot records owned by `CScanner` / symbol runtime; cleared or assigned during initialization/scan. | Closed-bar/data-valid gates present in current flow; full member-by-member lifetime/staleness audit remains open. |
| Bounded registries | Fixed-capacity/count members in signal/zone/event/runtime storage. | Bounds reduce unbounded growth; all malformed persistence inputs and integer conversions need runtime/fuzz tests. |
| Execution authorization/config | Config and authorization state flow through controller/validator/gateway. | Static guards confirm analysis-only hard block/defaults and authorization recheck strings; no live/demo execution was attempted. |

## Verified checks and open concerns

- `mql5check.py`: structural/include/type heuristic clean; `mql5fields.py`: zero suspicious member accesses; `mql5calls.py`: zero call-arity mismatches.
- Those tools do not establish uninitialized member safety, narrowing overflow, floating-point tolerances, pointer lifetime, shadowing, persistence coverage, or thread/concurrency behavior.
- No cross-thread mutation was identified in the reviewed event-driven path, but a formal concurrency audit was not performed. Do not claim thread safety based on this.
- The unusual `Value` parameters `period` and `smoothed` are accepted but not referenced in the inspected function body; they appear informational/legacy. No behavior change made; verify all call sites before any API cleanup.
- Array indices and dynamic resize failures require MQL5 runtime stress tests. General project-wide proof of no unsafe index remains open.

## Required completion method

Generate per-file declarations/reads/writes and review critical state against owner, initialization/reset, mutation, consumer, persistence requirement and bounds. Prioritize `Core/Config`, `Runtime/Engine` and `Scanner`, `Execution/*`, `Persistence/*`, signal registries and market buffers. For each finding preserve code location and test. No thresholds or strategy semantics changed in this audit.
