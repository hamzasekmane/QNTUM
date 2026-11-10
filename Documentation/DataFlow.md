# QuantumMarketEngine — Data Flow

## 1. One symbol, five timeframes

```
D1  context   → regime, volatility envelope, HTF context
H4  bias      → directional bias (SBiasResult)
H1  structure → swings, BOS, MSS, structure trend
M15 setup     → zones, premium/discount, liquidity targets
M5  entry     → trigger, candle facts, pattern, displacement, spread
```

`CScanner` owns five `CTimeframeContext` + `CBarSeries` per symbol and produces
one `SMarketAnalysis` per slot. Nothing is carried between symbols.

```
CBarSeries.Refresh()          closed bars, gap-checked
CTimeframeContext.Refresh()   ATR, EMA, RSI, averages
        │
        ├── CTrendEngine::Evaluate        → STrendResult
        ├── CMomentumEngine::Evaluate     → SMomentumResult
        ├── CVolatilityEngine::Evaluate   → SVolatilityResult
        ├── CRegimeEngine::Evaluate       → SRegimeResult
        ├── CBiasEngine::Evaluate         → SBiasResult
        ├── CStructureEngine::Evaluate    → SStructureState
        ├── CBosEngine / CMssEngine / CBreakoutEngine → SStructureEvent
        ├── CLiquidityEngine::Evaluate    → SLiquidityAnalysis
        ├── CLiquiditySweep::Best         → SSweepResult
        ├── CVolumeProfile::Build         → SVolumeProfile
        ├── CFvgEngine / COrderBlockEngine→ SFvgRecord[] / SOrderBlockRecord[]
        ├── CCandleEngine / CCandlePatternEngine / CDisplacementEngine
        ├── CLocationEngine / CPremiumDiscountEngine
        └── CReactionEngine::AtLevel      → SReactionResult
                │
                ▼
          SMarketAnalysis  (valid flag = structure && liquidity && trend && bias)
```

## 2. Data quality gate

`CDataQualityGuard::Evaluate(ctx, spreadPoints, quality)` on the entry timeframe.
A symbol whose data is stale, incomplete or whose spread is abnormal is skipped
before any strategy work. The reason is logged once per change, not per tick.

## 3. Zones

```
SMarketAnalysis (setup, entry)
        │
        ├── CZoneBuilder::FromOrderBlocks
        ├── CZoneBuilder::FromFvgs
        └── (liquidity/PDH-PDL/session/VP sources via CZoneBuilder)
                │
                ▼
        CZoneBoard.AddOrMerge(z, mergeOverlapPct)
                │   identity = symbol:tf:side:source:loBucket:hiBucket
                ▼
        CZoneLifecycle::Update(closed bar only)
                │
                ▼
        CZoneRanking::Score → BestForSide / TopForSide
```

Zone state machine: `FRESH → TESTED → MITIGATED`, with terminal
`INVALIDATED`/`EXPIRED`. A zone never returns to a previous state.

## 4. Signal pipeline

```
CZoneEngine.BestZone(side, price, atr, now, 2.0 ATR)
        │
        ▼
CCandidateCollector::Collect      ≤1 hypothesis per side ("why now")
        │  evidence = 14 factors, each 0..1
        ▼
CCandidateClusterer::Merge        exactly ≤1 candidate per side
        │  primary = highest timeframe, evidence = max per factor
        ▼
CMtfConfluenceEngine::Evaluate    agreement across tf views
        │
        ▼
CSetupEngine::Evaluate            hard rejections:
        │                         data, HTF alignment, confluence, confirmations,
        │                         location inside the zone
        ▼
CEntryEngine::Confirm             trigger + staleness (>0.75 ATR drift = dead)
        │
        ▼
CScoringEngine::Score             family-capped 0..100 minus penalty
        │
        ▼
CSignalQualityEngine::Evaluate    0.45*score + 0.25*confluence + 0.20*rr + 0.10*data
        │
        ▼
CSignalRegistry::Add              fingerprint uniqueness, capacity
```

Every rejection carries an `ENUM_QME_REJECT`; `CSignalEngine::Stats()` exposes
`hypotheses / merged / setupFail / entryFail / qualityFail / approved`, so the
funnel is auditable rather than mysterious.

## 5. Decision and risk

```
STradingSignal
   │
   ▼ CDecisionEngine::Decide
   │    ├── score floor re-check
   │    └── CRiskEngine::Evaluate
   │             ├── CRiskBudget::VolumeForRisk      (rounds DOWN; 0 ⇒ refuse)
   │             ├── plan built with normalised prices
   │             └── CPreTradeValidator::Validate    17 checks, first failure wins
   ▼
SDecision { verdict, reason, note, plan, risk }
```

The 17 checks, in order: config → plan validity → account mode → permissions →
symbol tradable → broker session → session policy → news → spread → risk per
trade → daily loss → drawdown → loss streak → positions/duplicates → exposure →
correlation → margin.

## 6. Execution

```
SDecision(APPROVED)
   │
   ▼ CExecutionGateway::Execute
   │   1 CIdempotencyGuard::CanExecute      (one execution per intent)
   │   2 CTradingPermissions::Authorize     (independent re-authorization)
   │   3 CTradeRequestBuilder::Build        (SL and TP mandatory)
   │   4 CExecutionValidator::Full          (local + OrderCheck)
   │   5 CIdempotencyGuard::Begin           (claim the intent)
   │   6 COrderManager::Send                (retry policy, latency)
   │   7 CPositionReconciler (if ambiguous) (broker truth wins)
   │   8 CTradeJournal / CExecutionMonitor
   ▼
SExecutionResult → signal EXECUTED → position tracked
```

## 7. Persistence

```
CEngine ──compose──> CStateRecovery::Compose
                       [ACCT] state;…        (CAccountState)
                       [POS]  pos;…          (CPositionStateStore)
                       [SIG]  sig;…          (CSignalHistoryStore)
                       [DEDUP] fp;…          (CSignalDeduplicator)
                       [IDEM] idem;…         (CIdempotencyGuard)
                       [MEM]  mem.…          (CRuntimeMemory)
                            │
                            ▼
                     CCheckpointManager::Save
                            │  CStateStore::Write
                            ▼
                  QME/qme_state.tmp → qme_state.txt   (atomic replace)
```

On start: `CStateRecovery::Apply` → version check → sections → **then**
`CPositionStateStore::ReconcileWithBroker`, because the broker may have closed
positions while the terminal was off.

## 8. Output flow

```
CEngine state ──> SDashboardData ──> CDashboard (chart labels)
             ──> CExplanationEngine (text with numbers)
             ──> CAlertEngine ──> CAlertGuard ──> ports (console/file/push)
             CScanner zones ──> CVisualizationEngine (rectangles, levels)
```

The output layer consumes; it never writes back into strategy or risk.
