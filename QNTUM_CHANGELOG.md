# QNTUM controlled remediation changelog

## QME-AUD-03 — Preflight checkpoint sections before live state mutation
- **Commit:** `83836a9`.
- **Files:** `Persistence/StateRecovery.mqh`; `Tests/Integration/Test_PositionRecovery.mqh`; `test_system.py`; `QNTUM_ROOT_CAUSE_REPORT.md`; `QNTUM_REMEDIATION_PLAN.md`; `QNTUM_TEST_REPORT.md`.
- **Change:** stage account and each non-empty persisted section in isolated temporary objects before applying any section to the live recovery targets. Added an MQL regression for valid restore and invalid late IDEM section, checking live account and tracked positions remain unchanged. Added a source-level Python check for preflight ordering.
- **Why:** the former parser could mutate account/position/history/dedup before a later invalid idempotency section returned `loaded=false`.
- **Verification:** `python3 test_system.py` 50/50; `Tools/mql5check.py` scanned 197 sources with no structural errors; `mql5fields.py` 0 suspicious accesses; `mql5calls.py` 0 arity mismatches; `git diff --check` clean. These are static/heuristic checks only. The new MQL test was not compiled or run.
- **MetaEditor files to compile/run:** compile `QME_Main.mq5` and `Tests/Integration/Test_PositionRecovery.mq5`; run the latter in MT5 Strategy Tester or a safe Demo analysis-only test environment. No trading authorization should be enabled. Verify valid payload restores normally and malformed `[IDEM]` causes `loaded=false` without changing seeded live account/position state.
- **Limit:** existing section deserializers may accept some malformed rows when other rows are valid; this change only ensures section-level deserializer failures occur before live mutation, not strict validation of every field/line.

## QME-AUD-05 — Separate scanner analysis-complete and data-valid counts
- **Commit:** this commit (`QME-AUD-05 distinguish scanner validity counters`).
- **Files:** `Runtime/Scanner.mqh`; `test_system.py`; `QNTUM_ROOT_CAUSE_REPORT.md`; `QNTUM_REMEDIATION_PLAN.md`; `QNTUM_TEST_REPORT.md`.
- **Change:** increment `analysed` whenever a symbol refresh/analysis completes; increment `dataValid` only if the resulting snapshot passes the full data-valid gate. No validity gates changed.
- **Why:** the two reported counters previously had identical increment conditions and were therefore duplicates.
- **Verification:** static source-level regression and full Python/static-tool checks; no MQL compile/runtime proof.
- **MetaEditor files to compile/run:** compile `QME_Main.mq5` and `Tests/Integration/Test_MarketPipeline.mq5`; verify a mixed scan where analysis returns a snapshot but one quality/tick condition fails yields `lastAnalysed > lastDataValid`, and verify a refresh failure does not masquerade as current validity.

## QME-AUD-08 — Clarify entry versus position-management OrderSend ownership
- **Commit:** this commit (`QME-AUD-08 clarify OrderSend ownership comment`).
- **Files:** `Execution/OrderManager.mqh`; `test_system.py`; `QNTUM_ROOT_CAUSE_REPORT.md`; `QNTUM_REMEDIATION_PLAN.md`; `QNTUM_TEST_REPORT.md`.
- **Change:** corrected the OrderManager header comment to say it submits new entry orders; explicitly identifies TradeManager's separate position protection/close requests. No execution behavior changed.
- **Why:** the previous “only place that calls OrderSend” assertion contradicted two direct TradeManager call sites.
- **Verification:** static source assertion and Python checks; terminal tests not run. The broader ownership/authorization review remains open.
- **MetaEditor files to compile/run:** `QME_Main.mq5`, `Tests/Integration/Test_Execution.mq5`, `Tests/Integration/Test_PositionRecovery.mq5`; ensure existing-position protection remains operable while new entries remain blocked under analysis-only and recovery-blocked conditions.
