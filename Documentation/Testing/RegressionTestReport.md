# Regression test report

**Date:** 2026-11-10. **Result:** repository static suite passes; MQL5 compilation/runtime status is unknown.

## Executed

- `python3 test_system.py` — **45/45 checks passed**.
- `python3 Tools/mql5check.py` — 192 source units scanned; no structural errors detected (tool explicitly says not a compiler proof).
- `python3 Tools/mql5fields.py` — 0 suspicious member access heuristics.
- `python3 Tools/mql5calls.py` — 0 arity mismatches.
- `git diff --check` — passed for the documentation-only changes in this task.

Static suite verifies entry points, nonempty sources, safety defaults, several historical regressions (FVG capacity, signal expiry, analysis-only execution guard, data validity/top-down path, dispatcher reset, quote-session gaps, candidate validity/repeated internal rejection, pipeline and release audit assertions), and 21 paired MQL5 test programs.

Phase 2 rerun output is archived at `Documentation/Testing/Phase2StaticVerification.log`.

## Not executed

No MetaEditor compilation, MQL5 unit/integration/regression program, MT5 Strategy Tester, live/demo broker operation, persistence fault injection, memory test, or performance benchmark was run. Thus passing static tests do not satisfy runtime validation criteria. No tests were removed or weakened. There were no source-code fixes in this audit, so no fix-specific regression test was added.
