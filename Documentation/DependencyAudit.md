# Dependency Audit — QuantumMarketEngine

> Date: 2026-11-10. Generated from the actual `#include` graph and class
> declarations in the tree; edges counted per include line.

## Layer dependency edges (includes crossing layers)

| From | To | Includes | Assessment |
|---|---|---|---|
| Runtime | Core/Data/Account/Analysis/Zones/Intelligence/Strategy/Risk/Execution/Persistence/Monitoring/Output | 33/9/4/3/2/3/7/1/4/5/1/1 | composition root — expected |
| Strategy | Core 38, Intelligence 7, Account 4, Analysis 3, Zones 3, Risk 1 | | risk edge is the plan-validation call, documented in Phase0 audit |
| Analysis | Core 58, Data 28 | | clean |
| Risk | Core 28, Account 12, Data 1 | | clean |
| Execution | Core 39, Account 10 | | clean |
| Persistence | Core 22, Execution 2, Strategy 2 | | serialises execution/strategy records — accepted |
| Zones | Core 21, Data 3, Analysis 2 | | clean |
| Data | Core 35, Account 1 | | `SymbolProfile → SymbolSpecifications`; accepted (symbol metadata) |
| Monitoring | Core 18, Account 2, Execution 1, Runtime 1 | | `PerformanceMetrics → Runtime/AlgoContainers`; LOW note, containers could move to Core |
| Output | Core 19, Strategy 3, others 1 each | | explanation/report layer reads decision records — accepted |
| Account | Core 20 | | clean |
| Intelligence | Core 21, Analysis 3 | | clean |

No layer-level cycles: every edge flows toward Core, or into the Runtime
composition root. Include guards are present on every `.mqh`
(mql5check-verified), and the umbrella `QME.mqh` orders includes
Core → Account → Data → Analysis → Zones → Intelligence → Strategy →
Risk → Execution → Persistence → Runtime → Monitoring → Output.

## Class inventory (146)

| Class | Header |
|---|---|
| `CAccountContext` | `Account/AccountContext.mqh` |
| `CAccountModeDetector` | `Account/AccountModeDetector.mqh` |
| `CAccountState` | `Account/AccountState.mqh` |
| `CBrokerCapabilities` | `Account/BrokerCapabilities.mqh` |
| `CMarginManager` | `Account/MarginManager.mqh` |
| `CSymbolSpecifications` | `Account/SymbolSpecifications.mqh` |
| `CTradingPermissions` | `Account/TradingPermissions.mqh` |
| `CFactorCatalog` | `Analysis/FactorCatalog.mqh` |
| `CEqualHighLow` | `Analysis/Liquidity/EqualHighLow.mqh` |
| `CLiquidityEngine` | `Analysis/Liquidity/LiquidityEngine.mqh` |
| `CLiquidityMapBuilder` | `Analysis/Liquidity/LiquidityMap.mqh` |
| `CLiquiditySweep` | `Analysis/Liquidity/LiquiditySweep.mqh` |
| `CPdhPdlEngine` | `Analysis/Liquidity/PdhPdlEngine.mqh` |
| `CPocEngine` | `Analysis/Liquidity/PocEngine.mqh` |
| `CSessionLiquidity` | `Analysis/Liquidity/SessionLiquidity.mqh` |
| `CVolumeProfile` | `Analysis/Liquidity/VolumeProfile.mqh` |
| `CBiasEngine` | `Analysis/Market/BiasEngine.mqh` |
| `CMomentumEngine` | `Analysis/Market/MomentumEngine.mqh` |
| `CRegimeEngine` | `Analysis/Market/RegimeEngine.mqh` |
| `CSessionEngine` | `Analysis/Market/SessionEngine.mqh` |
| `CTrendEngine` | `Analysis/Market/TrendEngine.mqh` |
| `CVolatilityEngine` | `Analysis/Market/VolatilityEngine.mqh` |
| `CCandleEngine` | `Analysis/PriceAction/CandleEngine.mqh` |
| `CCandlePatternEngine` | `Analysis/PriceAction/CandlePatternEngine.mqh` |
| `CDisplacementEngine` | `Analysis/PriceAction/DisplacementEngine.mqh` |
| `CFvgEngine` | `Analysis/PriceAction/FvgEngine.mqh` |
| `CLocationEngine` | `Analysis/PriceAction/LocationEngine.mqh` |
| `COrderBlockEngine` | `Analysis/PriceAction/OrderBlockEngine.mqh` |
| `CPremiumDiscountEngine` | `Analysis/PriceAction/PremiumDiscountEngine.mqh` |
| `CReactionEngine` | `Analysis/PriceAction/ReactionEngine.mqh` |
| `CBosEngine` | `Analysis/Structure/BosEngine.mqh` |
| `CBreakoutEngine` | `Analysis/Structure/BreakoutEngine.mqh` |
| `CMssEngine` | `Analysis/Structure/MssEngine.mqh` |
| `CStructureEngine` | `Analysis/Structure/StructureEngine.mqh` |
| `CStructureMap` | `Analysis/Structure/StructureMap.mqh` |
| `CSwingDetector` | `Analysis/Structure/SwingDetector.mqh` |
| `CConfig` | `Core/Config.mqh` |
| `CEventBus` | `Core/EventBus.mqh` |
| `CEventDispatcher` | `Core/EventDispatcher.mqh` |
| `CEventLedger` | `Core/EventLedger.mqh` |
| `CEventScheduler` | `Core/EventScheduler.mqh` |
| `IQmeEventSink` | `Core/EventTypes.mqh` |
| `CFunnel` | `Core/Funnel.mqh` |
| `CLogger` | `Core/Logger.mqh` |
| `CProfiler` | `Core/Profiler.mqh` |
| `CAssetClassTuning` | `Data/AssetClassTuning.mqh` |
| `CBarSeries` | `Data/BarSeries.mqh` |
| `CDataQualityGuard` | `Data/DataQualityGuard.mqh` |
| `CDataSynchronizer` | `Data/DataSynchronizer.mqh` |
| `CHistoryValidator` | `Data/HistoryValidator.mqh` |
| `CIndicatorCache` | `Data/IndicatorCache.mqh` |
| `CMarketClock` | `Data/MarketClock.mqh` |
| `CMarketData` | `Data/MarketData.mqh` |
| `CSymbolProfile` | `Data/SymbolProfile.mqh` |
| `CTickProcessor` | `Data/TickProcessor.mqh` |
| `CTimeframeContext` | `Data/TimeframeContext.mqh` |
| `CExecutionGateway` | `Execution/ExecutionGateway.mqh` |
| `CExecutionMonitor` | `Execution/ExecutionMonitor.mqh` |
| `CExecutionValidator` | `Execution/ExecutionValidator.mqh` |
| `CIdempotencyGuard` | `Execution/IdempotencyGuard.mqh` |
| `COrderManager` | `Execution/OrderManager.mqh` |
| `CPositionReconciler` | `Execution/PositionReconciler.mqh` |
| `CRetryPolicy` | `Execution/RetryPolicy.mqh` |
| `CTradeJournal` | `Execution/TradeJournal.mqh` |
| `CTradeManager` | `Execution/TradeManager.mqh` |
| `CTradeRequestBuilder` | `Execution/TradeRequestBuilder.mqh` |
| `CTransactionHandler` | `Execution/TransactionHandler.mqh` |
| `CAdaptiveWeights` | `Intelligence/AdaptiveWeights.mqh` |
| `CCausalValidator` | `Intelligence/CausalValidator.mqh` |
| `CClassPrior` | `Intelligence/ClassPrior.mqh` |
| `CConfidenceCalibration` | `Intelligence/ConfidenceCalibration.mqh` |
| `CMtfConfluenceEngine` | `Intelligence/MtfConfluenceEngine.mqh` |
| `COutcomeAnalyzer` | `Intelligence/OutcomeAnalyzer.mqh` |
| `CProbabilityModel` | `Intelligence/ProbabilityModel.mqh` |
| `CScoringEngine` | `Intelligence/ScoringEngine.mqh` |
| `CSignalQualityEngine` | `Intelligence/SignalQualityEngine.mqh` |
| `CErrorTracker` | `Monitoring/ErrorTracker.mqh` |
| `CExecutionStatistics` | `Monitoring/ExecutionStatistics.mqh` |
| `CHealthMonitor` | `Monitoring/HealthMonitor.mqh` |
| `CPerformanceMetrics` | `Monitoring/PerformanceMetrics.mqh` |
| `CRuntimeDiagnostics` | `Monitoring/RuntimeDiagnostics.mqh` |
| `CSystemWatchdog` | `Monitoring/SystemWatchdog.mqh` |
| `CAlertBinding` | `Output/AlertBinding.mqh` |
| `CAlertEngine` | `Output/AlertEngine.mqh` |
| `CAlertGuard` | `Output/AlertGuard.mqh` |
| `CAlertPort` | `Output/AlertPort.mqh` |
| `CConsoleAlertPort` | `Output/AlertPort.mqh` |
| `CFileAlertPort` | `Output/AlertPort.mqh` |
| `CPushAlertPort` | `Output/AlertPort.mqh` |
| `CDashboard` | `Output/Dashboard.mqh` |
| `CExplanationEngine` | `Output/ExplanationEngine.mqh` |
| `CVisualizationEngine` | `Output/VisualizationEngine.mqh` |
| `CCheckpointManager` | `Persistence/CheckpointManager.mqh` |
| `CPositionStateStore` | `Persistence/PositionStateStore.mqh` |
| `CRuntimeMemory` | `Persistence/RuntimeMemory.mqh` |
| `CSignalHistoryStore` | `Persistence/SignalHistoryStore.mqh` |
| `CStateRecovery` | `Persistence/StateRecovery.mqh` |
| `CStateSerializer` | `Persistence/StateSerializer.mqh` |
| `CStateStore` | `Persistence/StateStore.mqh` |
| `CConsecutiveLossGuard` | `Risk/ConsecutiveLossGuard.mqh` |
| `CCorrelationRisk` | `Risk/CorrelationRisk.mqh` |
| `CDailyLossGuard` | `Risk/DailyLossGuard.mqh` |
| `CDrawdownGuard` | `Risk/DrawdownGuard.mqh` |
| `CExposureManager` | `Risk/ExposureManager.mqh` |
| `CNewsFilter` | `Risk/NewsFilter.mqh` |
| `CPortfolioSnapshot` | `Risk/PortfolioRisk.mqh` |
| `CPreTradeValidator` | `Risk/PreTradeValidator.mqh` |
| `CRiskBudget` | `Risk/RiskBudget.mqh` |
| `CRiskEngine` | `Risk/RiskEngine.mqh` |
| `CSpreadSessionGuard` | `Risk/SpreadSessionGuard.mqh` |
| `CQmeStringList` | `Runtime/AlgoContainers.mqh` |
| `CQmeTicketList` | `Runtime/AlgoContainers.mqh` |
| `CQmeRing` | `Runtime/AlgoContainers.mqh` |
| `CCanonicalSnapshot` | `Runtime/CanonicalSnapshot.mqh` |
| `CEngine` | `Runtime/Engine.mqh` |
| `CReplayEngine` | `Runtime/ReplayEngine.mqh` |
| `CRuntimeController` | `Runtime/RuntimeController.mqh` |
| `CSymbolRuntime` | `Runtime/Scanner.mqh` |
| `CScanner` | `Runtime/Scanner.mqh` |
| `CScheduler` | `Runtime/Scheduler.mqh` |
| `CShutdownManager` | `Runtime/ShutdownManager.mqh` |
| `CDecisionEngine` | `Strategy/DecisionEngine.mqh` |
| `CCandidateClusterer` | `Strategy/MTF/CandidateClusterer.mqh` |
| `CCandidateCollector` | `Strategy/MTF/CandidateCollector.mqh` |
| `CEntryEngine` | `Strategy/MTF/EntryEngine.mqh` |
| `CEntryRig` | `Strategy/MTF/EntryRig.mqh` |
| `CEntryTypes` | `Strategy/MTF/EntryTypes.mqh` |
| `CPlanLifecycle` | `Strategy/MTF/PlanLifecycle.mqh` |
| `CSetupEngine` | `Strategy/SetupEngine.mqh` |
| `CSignalDeduplicator` | `Strategy/SignalDeduplicator.mqh` |
| `CSignalEngine` | `Strategy/SignalEngine.mqh` |
| `CSignalExpiry` | `Strategy/SignalExpiry.mqh` |
| `CSignalLifecycle` | `Strategy/SignalLifecycle.mqh` |
| `CSignalRegistry` | `Strategy/SignalRegistry.mqh` |
| `CSignalTypes` | `Strategy/SignalTypes.mqh` |
| `CStrategyRegistry` | `Strategy/StrategyRegistry.mqh` |
| `CTestKit` | `Tests/TestKit.mqh` |
| `CTestSink` | `Tests/Unit/Test_Instrumentation.mqh` |
| `CTopZones` | `Zones/TopZones.mqh` |
| `CZoneBoard` | `Zones/ZoneBoard.mqh` |
| `CZoneBuilder` | `Zones/ZoneBuilder.mqh` |
| `CZoneEngine` | `Zones/ZoneEngine.mqh` |
| `CZoneIdentity` | `Zones/ZoneIdentity.mqh` |
| `CZoneLifecycle` | `Zones/ZoneLifecycle.mqh` |
| `CZoneRanking` | `Zones/ZoneRanking.mqh` |
| `CZoneValidator` | `Zones/ZoneValidator.mqh` |

Ownership and lifecycle notes:

- `CEngine` (Runtime/Engine.mqh) is the single composition root: it owns
  scanner, account, risk, execution gateway, registries, persistence,
  event bus/dispatcher/ledger, funnel and profiler by value, and drives
  Init → Cycle/OnTick/OnTimer → Deinit in that order.
- `CSymbolRuntime` (Runtime/Scanner.mqh) owns per-symbol timeframe
  contexts, bar series, analyses and the zone engine by value; the
  scanner owns runtimes by pointer (`new`/`delete` in Init/Shutdown).
- Structures (`S*`) are always passed by reference or copied; after this
  repair round no pointer to a structure exists anywhere in the tree.
- Class pointers are used only for: class objects in arrays
  (`CSymbolRuntime*`, alert ports, event sinks), and engine-owned
  collaborators wired via `Attach`/`Init` pointers — all non-owning
  except the scanner's runtimes.
