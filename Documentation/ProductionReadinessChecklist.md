# QNTUM Production Readiness Checklist, Test Plan & Rollout Runbook

**System:** `QuantumMarketEngine` (`QME_Main.mq5`)  
**Branch:** `arena/19807fc5-qntum`  
**Date:** 2026-11-16  
**Overall Release Status:** **READY FOR MT5 BUILD & DEMO SOAK** (`MetaEditor` compile & MT5 Strategy Tester runtime currently `UNVERIFIED` on Linux sandbox). **DO NOT enable REAL trading until Stages 1–3 below pass with saved logs.**

---

## 1. Phase 5 — Verification & Test Matrix

| Check / Suite | Scope | Current Sandbox Result | Windows MT5 Build 6251 Requirement |
|---|---|---|---|
| `python3 test_system.py --verbose` | Static structure, `mql5check.py` (197 files), `mql5fields.py`, `mql5calls.py`, safety defaults, regression guards, 23 test pairs | **PASS (`53/53`)** | Re-run after any pull/edit |
| `git diff --check` | Whitespace / patch hygiene | **PASS (`0` errors)** | N/A |
| `QME_Main.mq5` MetaEditor compile | Full MQL5 compilation (`#property strict`) | `UNVERIFIED` | Must compile **0 errors, 0 warnings** |
| Unit Suites (`10` EAs in `Tests/Unit/*.mq5`) | Algorithms, Canonical, Entry, Expiry (incl. cross-symbol), FVG safety, HashIndex, Instrumentation, Liquidity, Risk (incl. leveraged exposure + freezeLevel), Scoring, SignalLifecycle, Structure, Zones (incl. partial analysis) | `UNVERIFIED` | Run all 10 in Strategy Tester; **0 FAIL** |
| Integration Suites (`4` EAs in `Tests/Integration/*.mq5`) | Execution (no order sent), MarketPipeline (quote-session gaps), MtfPipeline (market-entry filter), PositionRecovery (atomic row rejection + late IDEM failure) | `UNVERIFIED` | Run all 4 in Strategy Tester; **0 FAIL** |
| Regression Suites (`3` EAs in `Tests/Regression/*.mq5`) | ExecutionFailures, PreviousSignals, RepeatedSignals | `UNVERIFIED` | Run all 3 in Strategy Tester; **0 FAIL** |
| Validation Suites (`3` EAs in `Tests/Validation/*.mq5`) | DemoTrading, RealAccountSafety, RestartRecovery | `UNVERIFIED` | Run all 3 in Strategy Tester; **0 FAIL** |

### Fault-Injection Scenarios to Execute on Isolated DEMO
1. **Disconnect / Reconnect:** Disable network while EA is running -> verify `TickProcessor`/`AccountContext` blocks new entries immediately and `PositionStateStore::ReconcileWithBroker` retains tracked open positions (`0` false closures).
2. **AutoTrading Toggle:** Disable terminal AutoTrading -> verify `CAccountContext::Refresh` fast path detects revocation on the very next cycle (`< 1s`) and `CRuntimeController` transitions to `PAUSED`.
3. **Corrupt Checkpoint Recovery:** Inject a malformed row into `[POS]` or `[IDEM]` in `MQL5\Files` common folder (`FILE_COMMON\QME\...`) -> verify `CStateRecovery::Apply` refuses the file, `m_recoveryBlocked=true`, no trades are placed, and existing file is preserved.
4. **Legacy Unscoped State Guard:** Place `qme_state.txt` in `FILE_COMMON\QME\` -> verify `m_recoveryBlocked=true` blocks execution until reconciled.
5. **Weekend Opening (Monday 00:00–04:00 Server Time):** Verify `H4`/`H1` do not falsely trip `QME_DQ_FLAG_STALE` when broker quote sessions cover the weekend gap, while still catching unscheduled weekday freezes.
6. **Multi-Symbol Partial Availability:** Configure one invalid/unsynced symbol alongside valid symbols -> verify `CScanner::Init` logs an error for the bad symbol without aborting `OnInit()`.

---

## 2. Phase 6 — Go / No-Go Production Gate

Every item below MUST be `YES` before advancing to the next stage:
- [ ] `QME_Main.mq5` and all `23` `Tests/*/*.mq5` compile with `0` errors in MetaEditor.
- [ ] All `23` test EAs pass (`0` FAIL; no mandatory assertion SKIPPED).
- [ ] `QME_Main.mq5` runs on **an isolated sub-account** (no other EAs like `QATS` or manual orders sharing the account, because `CPreTradeValidator` safely blocks when foreign positions or active orders exist).
- [ ] Broker symbol names match `InpSymbolList` (add broker suffixes such as `.m` or `.pro` if required).
- [ ] Shipped defaults remain fail-closed (`InpAnalysisOnly=true`, `InpEnableDemoTrading=false`, `InpEnableRealTrading=false`, `InpRealTradingArmed=false`).
- [ ] Backtest (multi-year, Every Tick based on real ticks, realistic spread/commission/slippage) meets target drawdown `< InpMaximumDrawdownPercent` (`10%`) and positive expectancy out-of-sample.

---

## 3. Staged Rollout Plan

1. **Stage 1 — Compile & Offline Test Verification (Day 0):**
   - Compile `QME_Main.mq5` and `Tests/*/*.mq5` in MetaEditor build 6251+.
   - Execute all 23 test EAs in Strategy Tester (local agent, disconnected).
2. **Stage 2 — DEMO Analysis-Only Observation (Days 1–3):**
   - Attach `QME_Main.mq5` to a dedicated DEMO account with shipped defaults (`InpAnalysisOnly=true`).
   - Verify `scanner fullyValid=N/N`, signal funnel counts, zone generation, zero unintended errors, and clean Monday open transition.
3. **Stage 3 — DEMO Supervised Trading Soak (Min. 2 Weeks / >= 30 Closed Trades):**
   - Set `InpAnalysisOnly=false`, `InpEnableDemoTrading=true` (keep `InpEnableRealTrading=false`, `InpRealTradingArmed=false`).
   - Verify `OrderCheck`, market fill execution, SL/TP attachment, `OnTradeTransaction`, `SyncFromHistory` consecutive-loss tracking, and restart recovery.
4. **Stage 4 — REAL Micro-Lot Canary (Only After Written Sign-Off on Stage 3):**
   - On a dedicated live account with minimum risk (`InpRiskPerTradePct <= 0.25%`–`0.5%`, `InpMaximumPositions <= 2`):
   - Set `InpAnalysisOnly=false`, `InpEnableDemoTrading=false`, `InpEnableRealTrading=true`, `InpRealTradingArmed=true`, and `InpExpectedRealAccountLogin=<EXACT_LOGIN>`.
   - Monitor first 10 trades against `qme_journal_*.csv` and `qme_alerts.csv`.

---

## 4. Incident & Rollback Runbook

### Immediate Kill-Switch (< 5 Seconds)
1. Click **Algo Trading** OFF on the MT5 toolbar (immediately blocks `CAccountContext` and `OrderSend`), **OR** set `InpAnalysisOnly = true` in EA inputs.
2. Verify no unresolved orders remain in MT5 Toolbox -> **Trade** tab; inspect any open position and confirm SL/TP are present on the broker server.

### Recovery Block / Unresolved Intent (`recovery=BLOCKED`)
1. **Do NOT delete** the state file under `Terminal\Common\Files\QME\` blindly.
2. Reconcile MT5 **Account History** and **Trade** tabs against `qme_journal_*.csv` to confirm whether any `IN_FLIGHT` order executed at the broker.
3. Only after verifying broker state is flat/consistent, archive or remove the blocked/legacy file and restart in `InpAnalysisOnly=true` first.

### Code Rollback
- Revert to baseline commit `d18337d602c9e8af8941aec1b2041cec06296782` if an unrecoverable regression appears in MT5, recompile `QME_Main.mq5`, and restart in `InpAnalysisOnly=true`.
