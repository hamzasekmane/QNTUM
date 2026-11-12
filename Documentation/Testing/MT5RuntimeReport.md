# MT5 runtime validation report — Phase 2

**Status: BLOCKED — MT5 terminal/Strategy Tester unavailable.** No MQL5 test executable was run. No runtime pass is claimed.

No MT5 terminal, MetaEditor, Wine, tester agent or terminal data path was found in the available Linux environment. Exact terminal build, account/demo environment, symbols, test dates and runtime logs are unavailable. No broker connection was made and no orders were submitted.

The repository contains paired MQL5 suites for unit, integration, regression and validation, including execution, market pipeline, MTF pipeline, position recovery, repeated signals, risk, signal lifecycle, demo and real-account safety. Pair existence/static checks do not establish that suites can compile or execute.

| Suite category | Expected evidence | Actual status |
|---|---|---|
| Unit | Per-test results and terminal journal | BLOCKED, not run |
| Integration | Pipeline/execution/recovery results | BLOCKED, not run |
| Regression | Repeated signal / failures / previous signals | BLOCKED, not run |
| Configuration and safety validation | Actual MT5 inputs/account-mode behavior | BLOCKED, not run |
| Persistence/recovery | Restart/fault-injection terminal logs | BLOCKED, not run |

Required unblock: Windows MT5 Strategy Tester/terminal with isolated test data, exact build info, compiled test programs, deterministic fixture/config, and exported journal/test output. Keep all execution modes off during this validation. If uncertain state or reconciliation appears, stop.
