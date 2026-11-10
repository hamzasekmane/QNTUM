# QuantumMarketEngine — Class Responsibilities

Every class below exists in the repository today. The contract column states what
the class is allowed to decide; anything not listed there is out of its scope.

## Core

| Class / free functions | Contract |
|---|---|
| `CConfig` | validates `SInputs`; never enables a switch; exposes policy predicates |
| `CLogger` | severity-filtered log to console + file; must never throw |
| `CEventLedger` | records significant events; read-only for consumers |
| `CEventBus` / `CEventDispatcher` / `CEventScheduler` | internal publish/subscribe and deferred delivery |
| `CFunnel` | per-stage counters so nothing is dropped without trace |
| `CProfiler`, `CHistoryGuard` | timing and history sanity |
| free `Qme*` helpers | pure functions: formatting, classification, geometry predicates |

## Data

| Class | Contract |
|---|---|
| `CBarSeries` | closed-bar access, gap detection; refuses to invent bars |
| `CTimeframeContext` | indicators and ATR for one symbol/timeframe |
| `CTickProcessor`, `CIndicatorCache` | tick normalisation, indicator reuse |
| `CHistoryValidator`, `CDataQualityGuard` | data is fresh/complete/plausible |
| `CDataSynchronizer` | one evaluation per closed bar |
| `CMarketClock` | server/GMT/local time and offset |
| `CSymbolProfile` | per-symbol spec + tuning bundle |
| `CMarketData` | registry of symbols and their snapshots |

## Account

| Class | Contract |
|---|---|
| `CAccountModeDetector` | classifies DEMO/CONTEST/REAL; **UNKNOWN is a real outcome** |
| `CSymbolSpecifications` | loads and normalises broker constraints |
| `CAccountState` | day start, peak, streak; syncs from history |
| `CAccountContext` | snapshot of the account, refreshed, authoritative |
| `CBrokerCapabilities` | session open, side support, filling mode |
| `CMarginManager` | required vs free margin |
| `CTradingPermissions` | **the only** authorization gate; all-or-nothing |

## Analysis

Each engine is a static `Evaluate`/`Detect` over a context or a series. None of
them may send, size or store anything. `CFactorCatalog` owns the 14 factors,
their families and default weights; `SMarketAnalysis` is the single per-symbol
per-timeframe result struct.

## Zones

| Class | Contract |
|---|---|
| `CZoneIdentity` | deterministic hash `symbol:tf:side:source:loBucket:hiBucket` |
| `CZoneValidator` | rejects malformed, expired, invalidated zones |
| `CZoneLifecycle` | advances state from closed bars only |
| `CZoneMerger` | merges overlapping same-side zones, keeps evidence |
| `CZoneRanking` | `0.35*strength + 0.25*confidence + 0.20*freshness + 0.20*proximity` |
| `CZoneBoard` | bounded collection with pruning |
| `CZoneEngine` | per-symbol facade: update, best zone, top zones |

## Intelligence

| Class | Contract |
|---|---|
| `CFactorCatalog` | registry of factors and default weights |
| `CClassPrior` | base rates by setup type |
| `CAdaptiveWeights` | bounded weight adaptation, `allowLiveUpdates` default `false` |
| `CProbabilityModel` | refuses to estimate below 50 samples; Wilson bounds |
| `CCausalValidator` | evidence must precede the decision time |
| `CScoringEngine` | family-capped 0..100 score with explicit penalty |
| `CMtfConfluenceEngine` | multi-timeframe agreement; silence is not agreement |
| `CConfidenceCalibration` | bucket-based calibration of stated confidence |
| `CSignalQualityEngine` | composite quality with RR and data components |
| `COutcomeAnalyzer` | realised outcomes per playbook/factor |

## Strategy

| Class | Contract |
|---|---|
| `CCandidateCollector` | one hypothesis per side from the best zone + evidence |
| `CCandidateClusterer` | one merged candidate per side, max evidence |
| `CSetupEngine` | hard rejections (data, HTF, confluence, confirmations, location) |
| `CEntryEngine` | entry confirmation and staleness check |
| `CEntryRig` | stop/target geometry that fails rather than guesses |
| `CPlanLifecycle` | plan creation/validation |
| `CSignalLifecycle` | **the only** state mutator; refuses illegal transitions |
| `CSignalRegistry` | live signals, fingerprint uniqueness, bounded capacity |
| `CSignalDeduplicator` | cooldown per fingerprint, persisted |
| `CSignalExpiry` | time/price/zone expiry |
| `CStrategyRegistry` | playbooks and their realised statistics |
| `CSignalEngine` | pipeline + funnel statistics |
| `CDecisionEngine` | turns a signal into APPROVED/DEFERRED/REJECTED through risk |

## Risk

| Class | Contract |
|---|---|
| `CRiskBudget` | `volume = NormalizeVolume(riskMoney / lossPerLot)`, rounds down |
| `CDailyLossGuard` / `CDrawdownGuard` / `CConsecutiveLossGuard` | account-level stops |
| `CPortfolioSnapshot` | broker positions with risk and notional |
| `CExposureManager` | count, per-symbol and portfolio notional limits |
| `CCorrelationRisk` | directional cluster limit (heuristic, documented) |
| `CSpreadSessionGuard` | spread caps (absolute and vs ATR) and session policy |
| `CNewsFilter` | configured GMT blackout windows only |
| `CPreTradeValidator` | 17-step checklist, first failure wins |
| `CRiskEngine` | sizing + validation; never returns a plan that failed |

## Execution

| Class | Contract |
|---|---|
| `CRetryPolicy` | which broker answers may be retried, and never after a timeout |
| `CIdempotencyGuard` | one execution per intent, survives restart |
| `CTradeRequestBuilder` | plan → `MqlTradeRequest`; refuses illegal geometry |
| `CExecutionValidator` | local validation + server `OrderCheck` |
| `COrderManager` | the only `OrderSend` for new orders |
| `CExecutionGateway` | the authorized path: idempotency → permissions → build → validate → send → reconcile |
| `CTransactionHandler` | attributes `OnTradeTransaction` events to this magic |
| `CPositionReconciler` | broker truth vs engine belief |
| `CTradeManager` | stop/target maintenance; **refuses to widen a stop** |
| `CTradeJournal` | append-only CSV evidence |
| `CExecutionMonitor` | counters and the last execution fact |

## Persistence / Runtime / Monitoring / Output

| Class | Contract |
|---|---|
| `CStateSerializer`, `CStateStore` | versioned, escaped, atomic (tmp + move) state file |
| `CCheckpointManager` | cadence and failure accounting |
| `CPositionStateStore`, `CSignalHistoryStore`, `CRuntimeMemory` | bounded, serialisable collections |
| `CStateRecovery` | compose/apply one document; foreign or wrong-version docs are ignored |
| `CScanner` | the analysis factory; owns contexts, series, zones per symbol |
| `CScheduler` | all cadence decisions, testable without market data |
| `CCanonicalSnapshot` | deterministic digest of a decision cycle |
| `CReplayEngine` | records decisions and audits invariants |
| `CRuntimeController` | operating mode; can only reduce activity |
| `CShutdownManager` | ordered shutdown with a summary |
| `CEngine` | orchestration only |
| `CErrorTracker`, `CPerformanceMetrics`, `CExecutionStatistics` | measured facts |
| `CHealthMonitor`, `CRuntimeDiagnostics`, `CSystemWatchdog` | verdicts and support text |
| `CAlertPort` + ports, `CAlertGuard`, `CAlertEngine`, `CAlertBinding` | delivery with rate limiting |
| `CExplanationEngine` | plain-language explanations with numbers |
| `CDashboard`, `CVisualizationEngine` | chart output; read-only |

## Rules that hold across all classes

1. A class may only *reduce* what is permitted; authorisation belongs to
   `CTradingPermissions`.
2. A class may not invent data. Missing input → invalid result + reason.
3. A class may not swallow a failure. Every failure path sets a reason string.
4. A class may not widen a protective stop or remove one.
5. A class may not send an order except `COrderManager` (new orders) and
   `CTradeManager` (SLTP and closes).
