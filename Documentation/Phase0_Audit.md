# QME — Phase 0 Repository Audit

Date: 2026-11-10
Branch: `arena/506455a6-qntum`
Baseline commit: `57e3b49 feat: initialize QuantumMarketEngine architecture`

## 1. Repository audit (evidence-based)

| Observation | Evidence |
|---|---|
| Total tracked files | 174 (`find . -path ./.git -prune -o -type f -print \| wc -l`) |
| Empty files (0 bytes) | **173** |
| Non-empty files | 1 — `README.md` (36 bytes, UTF-16LE, content `# QNTM`) |
| Total project text | 36 bytes |
| Build artefacts / MQL5 compiler | **none present** — no `metaeditor64.exe`, no `wine`, no `MetaTrader 5` install |
| Host | Linux x86_64 sandbox, `python3` + `node` available |

**Conclusion:** the repository is a *directory-and-filename skeleton only*. There is no prior code to
preserve, refactor, or break. There is also **no MQL5 compilation capability in this environment**;
therefore no compilation claim can be made here. See §6 for the executable static-verification
harness that replaces the compiler as far as is honestly possible.

## 2. Existing file inventory (all empty unless stated)

```
Root:            QME_Main.mq5, QME.mqh, README.md (non-empty)
Core/            15 files  (Types, Config, Constants, Enums, Utils, Logger, Profiler, Funnel,
                            EventTypes, EventBus, EventDispatcher, EventScheduler, EventLedger,
                            HistoryGuard, ErrorCodes)
Account/         7 files
Data/            11 files
Analysis/        33 files  (Market/6, Structure/6, Liquidity/8, PriceAction/8 + FactorCatalog)
Zones/           9 files
Intelligence/    9 files
Strategy/        14 files  (MTF/6 + 8 top-level)
Risk/            11 files
Execution/       11 files
Persistence/     7 files
Runtime/         8 files
Monitoring/      6 files
Output/          6 files
Tests/           16 files  (Unit/7, Integration/4, Regression/3, Validation/3)
Documentation/   9 files
```
No file was deleted or renamed. The skeleton is used verbatim as the build plan.

## 3. Empty-file inventory

173 of 173 skeleton files. Every file is populated by this implementation, in dependency order,
except where two skeleton names are proven redundant (see §5, "structural corrections").

## 4. Dependency map (implemented)

```
Constants ─> Enums ─> Utils ─> ErrorCodes ─> Types ─> Config ─> Logger ─> Profiler
                                                    │
        ┌───────────────────────────────────────────┴──────────────┐
        │                                                          │
   EventTypes ─> EventBus ─> EventDispatcher ─> EventScheduler      HistoryGuard
        │                        └─> EventLedger  └─> Funnel
        │
   Account: SymbolSpecifications ─> BrokerCapabilities ─> AccountModeDetector
            ─> TradingPermissions ─> MarginManager ─> AccountState ─> AccountContext
        │
   Data:    BarSeries ─> IndicatorCache ─> TimeframeContext ─> SymbolProfile
            ─> AssetClassTuning ─> DataQualityGuard ─> HistoryValidator
            ─> MarketClock ─> TickProcessor ─> MarketData (orchestrator)
        │
   Analysis: Market/(Regime,Bias,Trend,Momentum,Volatility,Session)
             Structure/(SwingDetector -> StructureMap -> StructureEngine -> Bos/Mss/Breakout)
             Liquidity/(LiquidityMap -> LiquidityEngine + Sweep/EqualHighLow/PdhPdl/Poc/VolumeProfile)
             PriceAction/(Candle -> CandlePattern/Reaction/Displacement/Location/Fvg/OrderBlock/PremiumDiscount)
        │
   Zones:   ZoneTypes ─> ZoneIdentity ─> ZoneBuilder ─> ZoneValidator ─> ZoneLifecycle
            ─> ZoneRanking ─> ZoneBoard ─> TopZones ─> ZoneEngine
        │
   Intelligence: ClassPrior/CausalValidator/AdaptiveWeights -> ScoringEngine
                 -> SignalQualityEngine -> ConfidenceCalibration -> MtfConfluenceEngine
                 ProbabilityModel -> OutcomeAnalyzer
        │
   Strategy: EntryTypes -> EntryRig; CandidateCollector -> CandidateClusterer
             -> SetupEngine -> EntryEngine -> PlanLifecycle -> SignalEngine
             -> SignalLifecycle/Registry/Deduplicator/Expiry -> DecisionEngine
        │
   Risk:    RiskBudget -> DailyLossGuard/DrawdownGuard/ConsecutiveLossGuard
            -> ExposureManager/CorrelationRisk/PortfolioRisk -> SpreadSessionGuard/NewsFilter
            -> PreTradeValidator -> RiskEngine
        │
   Execution: RetryPolicy -> IdempotencyGuard -> TradeRequestBuilder -> ExecutionValidator
              -> ExecutionGateway -> OrderManager/TradeManager -> TransactionHandler
              -> ExecutionMonitor -> PositionReconciler -> TradeJournal
        │
   Persistence: StateSerializer -> StateStore -> PositionStateStore/SignalHistoryStore
                -> CheckpointManager -> StateRecovery -> RuntimeMemory
        │
   Runtime: CanonicalSnapshot -> AlgoContainers -> Scanner -> Scheduler -> Engine
            -> RuntimeController -> ShutdownManager;  ReplayEngine
        │
   Monitoring: ErrorTracker -> PerformanceMetrics -> ExecutionStatistics
               -> HealthMonitor -> RuntimeDiagnostics -> SystemWatchdog
        │
   Output:  AlertPort -> AlertGuard -> AlertEngine -> AlertBinding
            VisualizationEngine -> Dashboard -> ExplanationEngine
```

No cycles: each arrow points only "downwards" in the list above, and every `.mqh` includes only
`Core/*` plus its own direct lower-level dependencies (verified automatically, §6).

## 5. Structural corrections (smallest maintainable)

1. **`Core/Types.mqh` vs `Zones/ZoneTypes.mqh`** — the specification places `TradingZone` in Core and
   zone enums in Zones. Keeping two copies of the zone record would guarantee divergence. Decision:
   the canonical `STradingZone` record and zone enums live in `Core/Types.mqh`/`Core/Enums.mqh`;
   `Zones/ZoneTypes.mqh` adds only zone-local material (merge policy, boundary geometry helpers,
   lifecycle transition table). No duplicated type.
2. **`Analysis/FactorCatalog.mqh`** is the single registry of scoring factors (id, weight, family,
   correlation group) so `ScoringEngine` and `AdaptiveWeights` never hard-code factor lists.
3. **`Strategy/MTF/*`** is kept as a subfolder (already present) and used for the entry-side pipeline;
   no new folders invented.
4. `#property strict` is placed in `QME_Main.mq5` only (it is an MQL4 compatibility directive; inside
   `.mqh` files it is inert and would only produce warnings).

## 6. Critical MQL5 compatibility risks & mitigations

| # | Risk | Mitigation implemented |
|---|---|---|
| R1 | No MQL5 compiler available here; syntax errors cannot be caught by compilation | `Tools/mql5check.py`: static verifier (include resolution, duplicate definitions, unknown class/struct/enum/enum-member references, missing method implementations, brace/paren balance, include guards, undeclared `input`) |
| R2 | Function pointers / delegates do not exist in MQL5 | Observer implemented with `virtual` interface classes (`IQmeEventSink`), not callbacks |
| R3 | Structs containing `string` cannot be binary-serialised | All persistence uses ANSI text key/value serialisation (`StateSerializer`) |
| R4 | Arrays of class objects need pointer arrays | All owned module arrays are `CFoo *m_items[]` with `new`/`delete` in `Shutdown()` |
| R5 | Enum type names for broker properties are easy to get wrong | Broker numerics stored as `int`/`long` and compared against documented constants only |
| R6 | `OrderSend` success ≠ position opened | Execution records `MqlTradeResult`, then reconciles via `OnTradeTransaction` + `PositionsTotal()` |
| R7 | Indicator handles must be released | `CIndicatorCache::Release()` called from every owning `Shutdown()` chain |
| R8 | Indicator data not ready (`BarsCalculated < needed`) | Every `CopyBuffer`/`CopyRates` result checked; data marked invalid, no decision taken |
| R9 | Repainting structure | Swings from **closed** bars only, with a confirmation delay (`swing_right_bars`) |
| R10 | `#include` path depth differs per file | Relative includes (`"../Core/Types.mqh"`), verified by the static checker |
| R11 | Timer/tick re-entrancy | `Engine` guard flags (`m_inTick`, `m_inTimer`) + idempotency fingerprints |
| R12 | Strategy Tester multi-symbol data limits | Scanner degrades gracefully: unavailable symbol → `QME_REJ_NO_DATA`, never fabricated |

## 7. Phase 1 implementation plan (executed next)

Interfaces defined before bodies; each file compilable at the end of the phase.

1. `Core/Constants.mqh` — version, limits, paths, tolerances (`const`, not macros, for type safety).
2. `Core/Enums.mqh` — all enumerations (side, account mode, regime, session, zone, signal lifecycle,
   rejection reasons, factors, severity, events, execution state).
3. `Core/Utils.mqh` — numeric/time/string helpers + enum→name tables.
4. `Core/ErrorCodes.mqh` — QME error enum ↔ retcode classification, broker retcode → text + recoverable flag.
5. `Core/Types.mqh` — the canonical records: `SCandle`, `SFactorScore`, `SFactorBreakdown`,
   `SStructureState`, `SLiquidityLevel`, `STradingZone`, `STradingSignal`, `STradeCandidate`,
   `STradePlan`, `SRiskAssessment`, `SExecutionResult`, `SPositionContext`, `SAccountContext`,
   `SMarketSnapshot`.
6. `Core/Config.mqh` — `SInputs` (all defaults safe: every trading switch `false`), `CConfig`
   with `Validate()` returning explicit errors.
7. `Core/Logger.mqh` — severity filter, ring buffer for dashboard, file sink, counters.
8. `Core/Profiler.mqh` — per-section microsecond timings (`GetMicrosecondCount`).
9. Account layer: `SymbolSpecifications`, `BrokerCapabilities`, `AccountModeDetector`,
   `TradingPermissions`, `MarginManager`, `AccountState`, `AccountContext`.
10. `Core/HistoryGuard.mqh` + `Core/Funnel.mqh` (pipeline accounting used by every later stage).
11. Static verification run + Phase 1 report.

---

## 8. Delivery status against this plan (as implemented)

The plan above was executed in order. Final tree: **182 MQL5 source files, all
non-empty, 25k+ lines**, plus 9 reports in `Documentation/`.

| Phase | Scope | Status |
|---|---|---|
| 0 | Audit, inventory, dependency map, interface proposal, risk register, this plan | done |
| 1 | `Core/` (15) + `Account/` (7) | done |
| 2 | `Data/` (11) | done |
| 3 | `Analysis/` (32 incl. `FactorCatalog`), `Zones/` (9) | done |
| 4 | `Intelligence/` (9) | done |
| 5 | `Strategy/` (14 incl. MTF) | done |
| 6 | `Risk/` (11) | done |
| 7 | `Execution/` (11) | done |
| 8 | `Persistence/` (7) | done |
| 9 | `Runtime/` (8), `Monitoring/` (6), `Output/` (7) | done |
| 10 | `QME.mqh`, `QME_Main.mq5`, `Tests/` (17 programs), documentation | done |

### Verification actually performed

```
$ python3 Tools/mql5check.py
scanned 182 files (182 implemented, 0 empty)
OK: no structural errors detected (this is NOT a compilation proof)
```

The checker validates include guards, brace/parenthesis balance, duplicate type
declarations, unknown identifiers, misplaced `input` declarations and empty
files. It is a structural check only.

### Verification NOT performed (and why)

* **Compilation** — no MetaEditor, no MT5 terminal, no Wine in the build
  environment. No compilation result is claimed anywhere in this repository.
* **Test execution** — the 17 test programs have never been run here. They are
  written to fail loudly (`INIT_FAILED`) and to `SKIP` (never pass) when the
  environment lacks market data.
* **Backtests / forward tests** — none exist and none are reported.

See `DeploymentGuide.md` for the exact MetaEditor commands and the ordered
progression from analysis mode to DEMO to REAL.

### Deviations from the plan, and why

| Decision | Reason |
|---|---|
| Added `Tests/TestKit.mqh` (not in the original inventory) | a shared assertion harness instead of 17 copies of the same code |
| `Risk/` has no dependency on `Strategy/` | the plan is rebuilt inside the risk engine; it removed a cycle and is re-validated by the 17-gate checklist |
| `CReplayEngine` replays *decisions*, not market data | market frames are not stored; the audit checks decision invariants, and the documentation says so explicitly |
| `CCorrelationRisk` is a heuristic table, not a covariance model | honest labelling beats a fake statistics module |
| `CNewsFilter` uses configured GMT windows only | no economic calendar is bundled or fabricated |
| `closeOnOppositeSignal` is accepted but not acted on | implementing it would add an automatic close path; it is marked reserved in the configuration reference rather than silently ignored |
