# QNTUM test report — Phase 1

## Environment
Python static tests/tools available. No MetaEditor, MT5 terminal, broker account, or state file. Results below are actual local command output, not MQL compilation or runtime evidence.

## Executed tests

| Test | Status | Actual result / what it verifies |
|---|---|---|
| `python3 test_system.py` (Phase 1 baseline) | **Passed** | Exit 0; output: `TOTAL: 49/49 passed, 0 failed`; `RESULT: static level OK`; explicit warning says not MetaEditor compile/test proof. Checks entrypoint/source nonempty, three Python static heuristics, safety input defaults, source-string regressions, and MQL test presence/pairing. Most checks are source/string or file-presence checks, not behavior. |
| `python3 test_system.py` (after QME-AUD-03) | **Passed** | 50/50 passed, including new source-level assertion that recovery preflight precedes live mutation and that MQL late-failure fixture exists. Not behavioral MQL evidence. |
| `python3 test_system.py` (after QME-AUD-05) | **Passed** | Exit 0; `TOTAL: 51/51 passed, 0 failed`; includes static counter-semantics assertion only, not scanner behavior. |
| `python3 test_system.py` (after QME-AUD-08) | **Passed** | Exit 0; `TOTAL: 52/52 passed, 0 failed`; includes a source-string check only for the corrected API comment and known TradeManager calls. |
| `python3 Tools/mql5check.py`, `mql5fields.py`, `mql5calls.py` (after QME-AUD-03) | **Passed** | 197 sources structurally scanned, no empty files; 0 suspicious field accesses; 0 arity mismatches. Heuristics only. |
| `git diff --check` (after QME-AUD-03) | **Passed** | No whitespace errors. |
| `python3 Tools/mql5check.py` | **Passed** | `scanned 197 files (197 implemented, 0 empty)`; `OK: no structural errors detected (this is NOT a compilation proof)`. Heuristic structural/include/type checks. |
| `python3 Tools/mql5fields.py` | **Passed** | `0 suspicious member access(es); this is a heuristic, not a compiler`. Heuristic only. |
| `python3 Tools/mql5calls.py` | **Passed** | `0 arity mismatch(es); this is a heuristic, not a compiler`. Heuristic only. |
| 23 `Tests/**/*.mq5` MQL test programs | **Not verifiable in this environment** | Files exist and are paired with `.mqh` suites according to Python checks; not compiled or executed. Their presence is not a pass. |
| MetaEditor compile of `QME_Main.mq5` | **Blocked** | MetaEditor unavailable. Need full compiler log and build number. |
| MT5 integration/regression/validation suites | **Blocked** | MT5 unavailable. Need compile/run logs and tester/account mode. Tests must use Strategy Tester or Demo analysis-only; do not enable execution. |
| Broker state reconciliation | **Blocked** | No `qme_state.txt`, Common Files listing, broker orders/deals/positions, or unresolved intents available. Cannot declare clean start/recovery. |

## Coverage quality and gaps
- `test_system.py` 49 assertions are predominantly source scans, literal-string checks, defaults checks, static tool invocation, and test pairing. They do not execute MQL5 logic.
- Existing MQL tests cover unit/integration/regression/validation areas (including execution, market pipeline, MTF, position recovery, repeated signals, risk, signal lifecycle, zones, real-account safety, restart recovery), but this environment cannot establish their outcomes.
- Missing/insufficient demonstrated coverage identified in Phase 1: recovery parser rollback on each corrupt section; payload/account/server/magic identity mismatch; legacy/scoped file matrix and exact OnInit outcomes; atomic write interruption/rename failures in MT5; mixed TF readiness vs snapshot-valid counters and scan epochs; clock skew/future tick/disconnect boundaries; full lifecycle from init through deinit/reinit with recovery fault; direct TradeManager call-path authorization and protection behavior.

## Defaults and change discipline
Source inspection and the passing static default assertions confirm current source defaults remain `InpEnableDemoTrading=false`, `InpEnableRealTrading=false`, `InpRealTradingArmed=false`, `InpAnalysisOnly=true`. No source code or inputs were modified in this Phase 1 audit. No compile/runtime success is claimed.
