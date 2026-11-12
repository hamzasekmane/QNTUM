# Controlled demo readiness

## Decision: NOT READY FOR DEMO TESTING (not certified)

This is an evidence decision, not a finding that all source code is defective. Requested gates remain unmet: MetaEditor compilation, MT5 runtime tests, demo authorization/controlled execution proof, performance measurement, persistence/recovery fault injection, and end-to-end execution-intent idempotency under restart/unknown outcome.

## Safety status verified statically

`InpAnalysisOnly=true`; `InpEnableDemoTrading=false`; `InpEnableRealTrading=false`; `InpRealTradingArmed=false`. Existing static suite checks the analysis-only validator block and authorization-related guards. No account was connected, no credentials requested, no broker calls or orders submitted, and no trading mode was enabled. Risk thresholds and SL/TP or execution protections were not changed.

## Required gates before controlled demo

1. Compile `QME_Main.mq5` and all 21 test programs with the target MetaEditor build; archive compiler logs.
2. Execute unit, integration, regression, validation, restart-recovery and execution-failure suites on MT5/Strategy Tester; record all failures.
3. Inject interrupted/corrupt/missing persistence and unknown broker outcomes; demonstrate fail-closed and reconciliation.
4. Verify explicit demo authorization, all risk/SL/TP checks, no duplicate orders across restart/registry eviction, and no automatic real-mode transition.
5. Profile a representative multi-symbol scan in MT5 and keep real trading disabled.

Compilation and runtime status are **NOT VERIFIED**, not pass. Do not attach a live account or treat static suite success as demo authorization.
