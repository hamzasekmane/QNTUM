# Phase 2 certification report

**Certification decision: NOT READY for demo trading.** The user-supplied MetaEditor report supports a compile-pass finding for 25 targets, but runtime safety, behavioral equivalence and performance remain unverified.

## Evidence status

| Gate | Status | Evidence / limitation |
|---|---|---|
| Static checks | PASS (prior workspace run) | `python3 test_system.py`: 49/49; `mql5check.py`, `mql5fields.py`, `mql5calls.py` reported no indicators; `git diff --check` clean. These are static checks, not native execution. |
| Native compilation | PASS for reported snapshot; CURRENT BRANCH UNVERIFIED | User-supplied MetaEditor output reports 25 total, 0 failed, 0 errors, 0 warnings, including `QME_Main.mq5`, 23 test EAs and the hash benchmark. The log does not identify source revision; subsequent edits to `QME_Main.mq5` and `Runtime/Engine.mqh` are therefore not proven compiled. See `Documentation/Testing/MetaEditorBuildReport.md`. |
| MT5 runtime tests | NOT VERIFIED | No Strategy Tester execution logs/results supplied. Compiling test EAs does not run them. |
| Restart/recovery and execution safety | NOT VERIFIED | No runtime evidence for persistence, idempotency, recovery, or risk/validator invariants. |
| Performance / benchmark | NOT VERIFIED | Benchmark EA compile is not a benchmark result; no repeated native measurements or comparison evidence. |
| Algorithm integration/completeness | PARTIAL / NOT CERTIFIED | Presence of reusable primitives does not establish integration in production paths or equivalence to existing behavior. Consult algorithm catalog and integration map. |
| Demo readiness | NO-GO | Keep analysis-only ON; demo/real/real arming OFF. No live or demo trading authorization is implied. |

## Required gates before reconsidering demo

1. Identify exact source revision and MetaEditor/terminal builds corresponding to the supplied compile log; retain the complete raw log.
2. Execute the 23 test EAs in a disconnected, isolated Strategy Tester with trading disabled. Preserve configuration and full logs; resolve failures without weakening tests.
3. Exercise restart/recovery, duplicate-signal, risk, execution-validator and failure scenarios; verify the existing safety invariants remain unchanged.
4. Perform repeated native benchmark trials after warm-up against the baseline, under comparable settings; document distributions and correctness/equivalence checks. Do not replace production algorithms absent measured benefit and equivalence.
5. Reassess each of the 20 requested algorithms individually with implementation, integration, static/native test, compile, runtime and performance status distinguished.

## Recovery-blocked signal preview

A fail-closed, signal-only preview path is available when persisted-state recovery is blocked **only if** `analysisOnly=true`, `enableDemoTrading=false`, `enableRealTrading=false`, and `realTradingArmed=false`. It can scan and emit signal previews, but defers all decisions before risk/execution, does not submit orders, and does not save/overwrite the unresolved checkpoint. Runtime remains FAULT/recovery-blocked; preview availability is not operational or demo-trading readiness. If any of the three trading switches is enabled, scans remain blocked. This path has static checks only; it requires exact-revision MetaEditor compilation and MT5 validation before use.

Until these gates have evidence, retain all trading protections and do not claim the system is demo-ready.
