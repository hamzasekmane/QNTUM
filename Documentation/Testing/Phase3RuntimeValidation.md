# Phase 3 — MT5 runtime validation

**Result: BLOCKED. No runtime tests were executed.**

## Environment check performed for Phase 3

At execution time the host reported `Linux 6.1.158+ x86_64`. `command -v` returned NOT_FOUND for `powershell.exe`, `pwsh`, `metaeditor64.exe`, `metaeditor`, `terminal64.exe`, `wine`, and `wine64`. The checkout contains 192 tracked `.mq5`/`.mqh` sources and 21 test `.mq5` programs. Availability of source files does not enable execution of MQL5 binaries on this host.

## Test evidence

| Test family | Programs present | Actual execution | Result |
|---|---:|---|---|
| Unit | 10 | Not run — MT5 unavailable | BLOCKED |
| Integration | 4 | Not run — MT5 unavailable | BLOCKED |
| Regression | 3 | Not run — MT5 unavailable | BLOCKED |
| Validation | 4 | Not run — MT5 unavailable | BLOCKED |
| Total | 21 | 0 | BLOCKED |

No test conditions, PASS/FAIL outputs, or terminal logs can be reported because no MQL5 EA was executed. The static suite's earlier 45/45 result is not Phase 3 evidence and was not substituted for runtime testing. No account was connected and no orders were sent.

## Required next action

Run the 21 compiled test EAs in an isolated Windows MT5 Strategy Tester, local agent only, disconnected from all broker accounts, with trading disabled. Preserve each test's `.set` configuration, terminal build, tester journal and per-assertion `CTestKit` output under a runtime log directory. Report skipped data-dependent assertions separately; no skipped mandatory assertion counts as a pass. Stop immediately on unexpected account access, order routing, unreconciled intent, or unsafe recovery state. See `MT5RuntimeExecutionPlan.md` for the procedure and `MT5RuntimeReport.md` for the runtime evidence checklist.

**Certification impact:** Phase 3 remains incomplete; overall status remains **NOT READY FOR DEMO TESTING**.
