//+------------------------------------------------------------------+
//|                                                          QME.mqh |
//|  QuantumMarketEngine — umbrella include.                          |
//|                                                                   |
//|  Include this file from an EA and you get the complete engine.       |
//|  Include order matters in MQL5 (no forward declarations across        |
//|  translation units), so the order below is dependency order:           |
//|                                                                   |
//|    Core -> Data -> Account -> Analysis -> Zones -> Intelligence ->     |
//|    Strategy -> Risk -> Execution -> Persistence -> Runtime ->          |
//|    Monitoring -> Output                                               |
//|                                                                   |
//|  Every header carries its own include guard, so double inclusion is    |
//|  harmless.                                                        |
//+------------------------------------------------------------------+
#ifndef __QME_UMBRELLA_MQH__
#define __QME_UMBRELLA_MQH__

//--- 1. core -------------------------------------------------------
#include "Core/Constants.mqh"
#include "Core/Enums.mqh"
#include "Core/Types.mqh"
#include "Core/Utils.mqh"
#include "Core/ErrorCodes.mqh"
#include "Core/Logger.mqh"
#include "Core/EventTypes.mqh"
#include "Core/EventBus.mqh"
#include "Core/EventDispatcher.mqh"
#include "Core/EventScheduler.mqh"
#include "Core/EventLedger.mqh"
#include "Core/Funnel.mqh"
#include "Core/HistoryGuard.mqh"
#include "Core/Profiler.mqh"
#include "Core/Config.mqh"

//--- 2. data -------------------------------------------------------
#include "Data/AssetClassTuning.mqh"
#include "Data/BarSeries.mqh"
#include "Data/TimeframeContext.mqh"
#include "Data/TickProcessor.mqh"
#include "Data/IndicatorCache.mqh"
#include "Data/HistoryValidator.mqh"
#include "Data/DataQualityGuard.mqh"
#include "Data/DataSynchronizer.mqh"
#include "Data/MarketClock.mqh"
#include "Data/SymbolProfile.mqh"
#include "Data/MarketData.mqh"

//--- 3. account ----------------------------------------------------
#include "Account/AccountModeDetector.mqh"
#include "Account/SymbolSpecifications.mqh"
#include "Account/AccountState.mqh"
#include "Account/AccountContext.mqh"
#include "Account/BrokerCapabilities.mqh"
#include "Account/MarginManager.mqh"
#include "Account/TradingPermissions.mqh"

//--- 4. analysis ---------------------------------------------------
#include "Analysis/FactorCatalog.mqh"

//--- 5. zones ------------------------------------------------------
#include "Zones/ZoneTypes.mqh"
#include "Zones/ZoneIdentity.mqh"
#include "Zones/ZoneValidator.mqh"
#include "Zones/ZoneLifecycle.mqh"
#include "Zones/ZoneMerger.mqh"
#include "Zones/ZoneRanking.mqh"
#include "Zones/ZoneBuilder.mqh"
#include "Zones/ZoneBoard.mqh"
#include "Zones/ZoneEngine.mqh"
#include "Zones/TopZones.mqh"

//--- 6. intelligence -----------------------------------------------
#include "Intelligence/ClassPrior.mqh"
#include "Intelligence/AdaptiveWeights.mqh"
#include "Intelligence/ProbabilityModel.mqh"
#include "Intelligence/CausalValidator.mqh"
#include "Intelligence/ScoringEngine.mqh"
#include "Intelligence/MtfConfluenceEngine.mqh"
#include "Intelligence/ConfidenceCalibration.mqh"
#include "Intelligence/SignalQualityEngine.mqh"
#include "Intelligence/OutcomeAnalyzer.mqh"

//--- 7. strategy ---------------------------------------------------
#include "Strategy/MTF/EntryTypes.mqh"
#include "Strategy/MTF/EntryRig.mqh"
#include "Strategy/MTF/CandidateCollector.mqh"
#include "Strategy/MTF/CandidateClusterer.mqh"
#include "Strategy/MTF/EntryEngine.mqh"
#include "Strategy/MTF/PlanLifecycle.mqh"
#include "Strategy/SetupEngine.mqh"
#include "Strategy/SignalTypes.mqh"
#include "Strategy/SignalLifecycle.mqh"
#include "Strategy/SignalRegistry.mqh"
#include "Strategy/SignalDeduplicator.mqh"
#include "Strategy/SignalExpiry.mqh"
#include "Strategy/StrategyRegistry.mqh"
#include "Strategy/SignalEngine.mqh"
#include "Strategy/DecisionEngine.mqh"

//--- 8. risk -------------------------------------------------------
#include "Risk/RiskBudget.mqh"
#include "Risk/DailyLossGuard.mqh"
#include "Risk/DrawdownGuard.mqh"
#include "Risk/ConsecutiveLossGuard.mqh"
#include "Risk/PortfolioRisk.mqh"
#include "Risk/ExposureManager.mqh"
#include "Risk/CorrelationRisk.mqh"
#include "Risk/SpreadSessionGuard.mqh"
#include "Risk/NewsFilter.mqh"
#include "Risk/PreTradeValidator.mqh"
#include "Risk/RiskEngine.mqh"

//--- 9. execution --------------------------------------------------
#include "Execution/RetryPolicy.mqh"
#include "Execution/IdempotencyGuard.mqh"
#include "Execution/TradeRequestBuilder.mqh"
#include "Execution/ExecutionValidator.mqh"
#include "Execution/TradeJournal.mqh"
#include "Execution/ExecutionMonitor.mqh"
#include "Execution/PositionReconciler.mqh"
#include "Execution/OrderManager.mqh"
#include "Execution/ExecutionGateway.mqh"
#include "Execution/TransactionHandler.mqh"
#include "Execution/TradeManager.mqh"

//--- 10. persistence -----------------------------------------------
#include "Persistence/StateSerializer.mqh"
#include "Persistence/StateStore.mqh"
#include "Persistence/RuntimeMemory.mqh"
#include "Persistence/PositionStateStore.mqh"
#include "Persistence/SignalHistoryStore.mqh"
#include "Persistence/CheckpointManager.mqh"
#include "Persistence/StateRecovery.mqh"

//--- 11. runtime ---------------------------------------------------
#include "Runtime/AlgoContainers.mqh"
#include "Runtime/Scanner.mqh"
#include "Runtime/Scheduler.mqh"
#include "Runtime/CanonicalSnapshot.mqh"
#include "Runtime/ReplayEngine.mqh"
#include "Runtime/RuntimeController.mqh"
#include "Runtime/ShutdownManager.mqh"
#include "Runtime/Engine.mqh"

//--- 12. monitoring -------------------------------------------------
#include "Monitoring/ErrorTracker.mqh"
#include "Monitoring/PerformanceMetrics.mqh"
#include "Monitoring/ExecutionStatistics.mqh"
#include "Monitoring/HealthMonitor.mqh"
#include "Monitoring/RuntimeDiagnostics.mqh"
#include "Monitoring/SystemWatchdog.mqh"

//--- 13. output -----------------------------------------------------
#include "Output/AlertPort.mqh"
#include "Output/AlertGuard.mqh"
#include "Output/AlertEngine.mqh"
#include "Output/AlertBinding.mqh"
#include "Output/ExplanationEngine.mqh"
#include "Output/Dashboard.mqh"
#include "Output/VisualizationEngine.mqh"

//+------------------------------------------------------------------+
//| Version and identity helpers used by the EA and the diagnostics.  |
//+------------------------------------------------------------------+
string QmeVersion(void) { return(QME_BUILD_TAG); }

string QmeBanner(void)
  {
   return("QuantumMarketEngine " + QME_BUILD_TAG +
          " | " + IntegerToString(CFactorCatalog::Count()) + " factors" +
          " | symbols " + IntegerToString(QME_MAX_SYMBOLS) +
          " | signals " + IntegerToString(QME_MAX_SIGNALS));
  }

//--- true when the build supports everything the engine needs
bool QmePlatformSupported(string &why)
  {
   why = "";
   if(!MQLInfoInteger(MQL_OPTIMIZATION) && !MQLInfoInteger(MQL_TESTER))
     {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
         why = "terminal trading is disabled (this is not fatal for analysis mode)";
         return(true);
        }
     }
   if(MQLInfoInteger(MQL_DLLS_ALLOWED))
     {
      //--- not required, but a healthy terminal usually has it off for us
     }
   return(true);
  }

#endif // __QME_UMBRELLA_MQH__
//+------------------------------------------------------------------+
