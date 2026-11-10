//+------------------------------------------------------------------+
//|                                                     QME_Main.mq5 |
//|  QuantumMarketEngine — Expert Advisor entry point.                |
//|                                                                   |
//|  THIS FILE IS THE ONLY PLACE WITH:                                |
//|    * `#property` directives;                                     |
//|    * `input` variables;                                          |
//|    * MQL5 event handlers.                                        |
//|                                                                   |
//|  SAFETY DEFAULTS: every trading switch is false. On a fresh chart  |
//|  the EA runs in analysis mode, analyses and explains, and never     |
//|  sends an order.                                                    |
//+------------------------------------------------------------------+
#property copyright   "QuantumMarketEngine"
#property version     "1.00"
#property description "Autonomous multi-symbol market engine. Analysis-only by default."
#property strict

#include "QME.mqh"

//--- inputs ---------------------------------------------------------
input group "=== 1. Runtime ==="
input ENUM_QME_SEVERITY InpLogLevel            = QME_LOG_INFO;   // Log level
input bool              InpLogToFile           = true;           // Write log file
input bool              InpLogCycleDetail      = false;          // Log every cycle detail
input bool              InpEnableDashboard     = true;           // On-chart dashboard
input int               InpDashboardRefreshSec = 2;              // Dashboard refresh (s)

input group "=== 2. Scope ==="
input string            InpSymbolList          = "EURUSD,GBPUSD,USDJPY,XAUUSD"; // Symbols (comma separated)
input ulong             InpMagicNumber               = 20261110;       // Magic number
input int               InpScanIntervalMs      = 5000;           // Scan interval (ms)
input int               InpBarsContext         = 400;            // Bars per context

input group "=== 3. Timeframes ==="
input ENUM_TIMEFRAMES   InpTfContext           = PERIOD_D1;      // Context timeframe
input ENUM_TIMEFRAMES   InpTfBias              = PERIOD_H4;      // Bias timeframe
input ENUM_TIMEFRAMES   InpTfStructure         = PERIOD_H1;      // Structure timeframe
input ENUM_TIMEFRAMES   InpTfSetup             = PERIOD_M15;     // Setup timeframe
input ENUM_TIMEFRAMES   InpTfEntry             = PERIOD_M5;      // Entry timeframe

input group "=== 4. Trading authorization (all false by default) ==="
input bool              InpEnableDemoTrading   = false;          // Enable DEMO trading
input bool              InpEnableRealTrading   = false;          // Enable REAL trading
input bool              InpRealTradingArmed    = false;          // Arm REAL trading (second switch)
input long              InpExpectedRealAccountLogin = 0;         // Expected REAL account login (0 = none)
input bool              InpAnalysisOnly        = true;           // Analysis only (never trades)

input group "=== 5. Direction ==="
input bool              InpAllowBuy            = true;           // Allow long trades
input bool              InpAllowSell           = true;           // Allow short trades

input group "=== 6. Risk ==="
input double            InpRiskPerTradePct     = 0.5;            // Risk per trade (% of equity)
input double            InpMaximumDailyLossPercent     = 3.0;            // Max daily loss (%)
input double            InpMaximumDrawdownPercent      = 10.0;           // Max drawdown (%)
input int               InpMaximumPositions        = 3;              // Max concurrent positions
input int               InpMaxPositionsPerSymbol = 1;            // Max positions per symbol
input double            InpMaxSymbolExposurePct = 5.0;           // Max symbol notional (% of equity)
input double            InpMaxPortfolioExposurePct = 12.0;       // Max portfolio notional (%)
input int               InpMaxConsecutiveLosses = 3;             // Max consecutive losses
input double            InpMinimumRiskReward               = 1.5;            // Minimum reward:risk
input double            InpMaximumSpreadPoints     = 0.0;            // Max spread in points (0 = off)
input double            InpMaximumSpreadAtrRatio   = 0.15;           // Max spread / ATR
input bool              InpSessionFilterEnabled = false;         // Enable session filter
input bool              InpAllowSessionAsia    = true;           // Allow Asia session
input bool              InpAllowSessionLondon  = true;           // Allow London session
input bool              InpAllowSessionNewYork = true;           // Allow New York session
input bool              InpAllowSessionOverlap = true;           // Allow London/NY overlap
input bool              InpNewsFilterEnabled   = false;          // Enable news blackout
input int               InpNewsBlackoutMinutes = 30;             // Blackout minutes either side
input string            InpNewsBlackoutWindows = "";             // GMT windows HH:MM-HH:MM;...

input group "=== 7. Strategy ==="
input double            InpMinScore            = 55.0;           // Minimum score (0..100)
input double            InpMinConfluence       = 0.40;           // Minimum MTF confluence
input bool              InpRequireHtfAlignment = true;           // Require HTF alignment
input int               InpMaxSignalsPerDay    = 12;             // Max signals per day
input int               InpSignalExpiryMinutes = 240;            // Signal expiry (minutes)
input int               InpCooldownSecPerSymbol = 900;           // Per-symbol cooldown (s)
input int               InpZoneMaxAgeHours     = 72;             // Zone max age (hours)
input double            InpZoneMergeOverlapPct = 60.0;           // Zone merge overlap (%)

input group "=== 8. Execution ==="
input int               InpMaximumRetries          = 2;              // Max transient retries
input int               InpRetryDelayMs        = 500;            // Retry base delay (ms)
input int               InpDeviationPoints     = 20;             // Max price deviation (points)
input bool              InpCloseOnOppositeSignal = false;        // Close opposite position on new signal
input double            InpBreakEvenAtR        = 0.0;            // Move stop to break-even at N x R (0 = off)
input bool              InpProfileCycles       = false;          // Measure cycle timings
input bool              InpTradeJournalEnabled = true;           // Write trade journal CSV

input group "=== 9. Persistence ==="
input bool              InpPersistState        = true;           // Persist state between runs
input int               InpCheckpointSec       = 30;             // Checkpoint interval (s)

//--- globals --------------------------------------------------------
CLogger                g_logger;
CEngine                g_engine;
CDashboard             g_dashboard;
CVisualizationEngine   g_visual;
CAlertEngine           g_alerts;
CConsoleAlertPort      g_portConsole;
CFileAlertPort         g_portFile;
CPushAlertPort         g_portPush;
CErrorTracker          g_errors;
CPerformanceMetrics    g_perf;
CSystemWatchdog        g_watchdog;
SDashboardData         g_dashData;
string                 g_initError = "";
datetime               g_started = 0;
long                   g_ticks = 0;

//+------------------------------------------------------------------+
//| Build SInputs from the input variables.                           |
//+------------------------------------------------------------------+
void BuildInputs(SInputs &in)
  {
   in.logLevel              = InpLogLevel;
   in.logToFile             = InpLogToFile;
   in.logCycleDetail        = InpLogCycleDetail;
   in.enableDashboard       = InpEnableDashboard;
   in.dashboardRefreshSec   = InpDashboardRefreshSec;

   in.symbolList            = InpSymbolList;
   in.magic                 = InpMagicNumber;
   in.scanIntervalMs        = InpScanIntervalMs;
   in.barsContext           = InpBarsContext;

   in.tfContext             = InpTfContext;
   in.tfBias                = InpTfBias;
   in.tfStructure           = InpTfStructure;
   in.tfSetup               = InpTfSetup;
   in.tfEntry               = InpTfEntry;

   in.enableDemoTrading     = InpEnableDemoTrading;
   in.enableRealTrading     = InpEnableRealTrading;
   in.realTradingArmed      = InpRealTradingArmed;
   in.expectedRealAccountLogin = InpExpectedRealAccountLogin;
   in.analysisOnly          = InpAnalysisOnly;

   in.allowBuy              = InpAllowBuy;
   in.allowSell             = InpAllowSell;

   in.riskPerTradePct       = InpRiskPerTradePct;
   in.maxDailyLossPct       = InpMaximumDailyLossPercent;
   in.maxDrawdownPct        = InpMaximumDrawdownPercent;
   in.maxPositions          = InpMaximumPositions;
   in.maxPositionsPerSymbol = InpMaxPositionsPerSymbol;
   in.maxSymbolExposurePct  = InpMaxSymbolExposurePct;
   in.maxPortfolioExposurePct = InpMaxPortfolioExposurePct;
   in.maxConsecutiveLosses  = InpMaxConsecutiveLosses;
   in.minRR                 = InpMinimumRiskReward;
   in.maxSpreadPoints       = InpMaximumSpreadPoints;
   in.maxSpreadAtrRatio     = InpMaximumSpreadAtrRatio;
   in.sessionFilterEnabled  = InpSessionFilterEnabled;
   in.allowSessionAsia      = InpAllowSessionAsia;
   in.allowSessionLondon    = InpAllowSessionLondon;
   in.allowSessionNewYork   = InpAllowSessionNewYork;
   in.allowSessionOverlap   = InpAllowSessionOverlap;
   in.newsFilterEnabled     = InpNewsFilterEnabled;
   in.newsBlackoutMinutes   = InpNewsBlackoutMinutes;
   in.newsBlackoutWindows   = InpNewsBlackoutWindows;

   in.minScore              = InpMinScore;
   in.minConfluence         = InpMinConfluence;
   in.requireHtfAlignment   = InpRequireHtfAlignment;
   in.maxSignalsPerDay      = InpMaxSignalsPerDay;
   in.signalExpiryMinutes   = InpSignalExpiryMinutes;
   in.cooldownSecPerSymbol  = InpCooldownSecPerSymbol;
   in.zoneMaxAgeHours       = InpZoneMaxAgeHours;
   in.zoneMergeOverlapPct   = InpZoneMergeOverlapPct;

   in.maxRetries            = InpMaximumRetries;
   in.retryDelayMs          = InpRetryDelayMs;
   in.deviationPoints       = InpDeviationPoints;
   in.closeOnOppositeSignal = InpCloseOnOppositeSignal;
   in.breakEvenAtR          = InpBreakEvenAtR;
   in.profileCycles         = InpProfileCycles;
   in.tradeJournalEnabled   = InpTradeJournalEnabled;

   in.persistState          = InpPersistState;
   in.checkpointSec         = InpCheckpointSec;
  }

//+------------------------------------------------------------------+
//| Dashboard composition.                                             |
//+------------------------------------------------------------------+
void RefreshDashboard(void)
  {
   if(!InpEnableDashboard) return;

   CScanner *sc = g_engine.ScannerRef();
   CAccountContext *acc = g_engine.Account();
   CRuntimeController *ctl = g_engine.Controller();
   SAccountContext a = acc.Snapshot();

   QmeDashboardClear(g_dashData);
   g_dashData.title = QmeBanner();
   g_dashData.mode = ctl.Describe();
   g_dashData.account = "equity " + QmeFmtMoney(a.equity) +
                        " (" + QmeFmtMoney(a.balance) + ")" +
                        "  free " + QmeFmtMoney(a.freeMargin) +
                        "  mode " + QmeAccountModeName(a.mode);
   g_dashData.session = (sc != NULL) ? QmeSessionName(sc.Session().session) : "n/a";
   g_dashData.scanner = (sc != NULL) ? sc.Describe() : "n/a";
   g_dashData.signals = "total " + IntegerToString((int)g_engine.History().Count()) +
                        "  trades " + IntegerToString((int)g_engine.Trades()) +
                        "  replay " + IntegerToString(g_engine.Replay().Count());
   g_dashData.risk = g_engine.Risk().Describe();
   g_dashData.execution = g_engine.Gateway().Describe();
   g_dashData.persistence = g_engine.History().Describe();
   g_dashData.performance = g_perf.Describe();
   g_dashData.alerts = g_alerts.Describe();
   g_dashData.lastDecision = g_engine.Status();
   g_dashData.footer = "InpMagicNumber " + IntegerToString((long)InpMagicNumber) +
                       "  errors " + IntegerToString((int)g_errors.Total()) +
                       "  v" + QME_BUILD_TAG;

   g_dashboard.Update(g_dashData);
  }

//+------------------------------------------------------------------+
//| Health + watchdog + alerts each timer tick.                        |
//+------------------------------------------------------------------+
void Housekeeping(void)
  {
   const datetime now = TimeCurrent();
   CScanner *sc = g_engine.ScannerRef();
   datetime lastData = 0;
   if(sc != NULL)
     {
      CSymbolRuntime *rt0 = sc.At(0);
      if(rt0 != NULL) lastData = rt0.snapshot.time;
     }

   //--- watchdog first: it may pause trading on a stall
   SWatchdogVerdict w = g_watchdog.Evaluate(now, now, lastData, g_errors);
   if(w.action == QME_WATCH_PAUSE)
      g_engine.Controller().Pause(w.reason);
   else if(w.action == QME_WATCH_FAULT)
      g_engine.Controller().Fault(w.reason);

   //--- health
   const datetime lastCheckpoint = InpPersistState ? now : 0;
   SHealthReport h = CHealthMonitor::Evaluate(*g_engine.Account(), InpMagicNumber, lastData, 300,
                                              lastCheckpoint, 1800, g_errors.Total(), 50);
   if(h.status != QME_HEALTH_OK)
     {
      string key = "", title = "", text = "";
      CAlertBinding::HealthChanged(h, key, title, text);
      g_alerts.Notify(h.status == QME_HEALTH_CRITICAL ? QME_LOG_CRITICAL : QME_LOG_WARN,
                      key, title, text);
     }

   //--- visuals
   if(InpEnableDashboard)
     {
      g_visual.DrawBias(Symbol(),
                        sc != NULL && sc.At(0) != NULL ? sc.At(0).snapshot.bias : QME_SIDE_NONE,
                        sc != NULL && sc.At(0) != NULL ? sc.At(0).snapshot.biasScore : 0.0,
                        InpTfBias);
     }
  }

//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_started = TimeCurrent();
   g_ticks = 0;
   g_initError = "";

   //--- 1. inputs -> configuration source
   SInputs in;
   QmeInputsDefaults(in);
   BuildInputs(in);

   //--- 2. logger (must exist before anything else logs)
   g_logger.Init(in, g_initError);
   g_log = GetPointer(g_logger);
   QmeLogMsg(QME_LOG_INFO, "Main", QmeBanner());
   QmeLogMsg(QME_LOG_INFO, "Main", "starting on " + _Symbol + " " + QmeTfName(_Period));

   //--- 3. engine
   if(!g_engine.Init(in, g_initError))
     {
      Print(QME_TAG, " INIT FAILED: ", g_initError);
      QmeLogMsg(QME_LOG_CRITICAL, "Main", "init failed: " + g_initError);
      g_log = NULL;
      return(INIT_FAILED);
     }

   //--- 4. output layer
   g_dashboard.Init(InpEnableDashboard, 10, 22, 470);
   g_visual.Init(InpEnableDashboard, 8);
   g_alerts.Init(QME_LOG_WARN, 300, 3, 60);
   g_portConsole.Enable(true);
   g_alerts.Add(GetPointer(g_portConsole));
   if(g_portFile.Init("qme_alerts.csv"))
      g_alerts.Add(GetPointer(g_portFile));
   g_portPush.Enable(false);            // push off by default (user opt-in)
   g_alerts.Add(GetPointer(g_portPush));

   g_perf.Init(100, 250.0);
   g_watchdog.Init(MathMax(InpScanIntervalMs / 1000 * 6, 60), 300, 50);
   g_errors.Reset();

   //--- 5. timers
   EventSetTimer(1);

   Print(QME_TAG, " READY. ", g_engine.Controller().Describe());
   RefreshDashboard();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   const string reasonText = "deinit reason " + IntegerToString(reason);
   if(g_engine.Ready())
      g_engine.Deinit(reasonText);

   g_visual.Shutdown();
   g_dashboard.Shutdown();
   g_alerts.Shutdown();

   QmeLogMsg(QME_LOG_INFO, "Main", "stopped after " +
             IntegerToString((int)(TimeCurrent() - g_started)) + "s, " +
             IntegerToString((int)g_ticks) + " ticks");
   g_logger.Shutdown();
   if(g_log == GetPointer(g_logger)) g_log = NULL;
  }

//+------------------------------------------------------------------+
void OnTick(void)
  {
   g_ticks++;
   g_perf.CycleBegin();
   const bool ok = g_engine.OnTick();
   g_perf.CycleEnd();

   if(!ok)
      g_errors.Report(QME_ERRC_INTERNAL, "cycle failed");

   //--- dashboard refresh is throttled by its own interval
   static datetime lastDash = 0;
   if(InpEnableDashboard && (TimeCurrent() - lastDash) >= MathMax(InpDashboardRefreshSec, 1))
     {
      lastDash = TimeCurrent();
      RefreshDashboard();
      CScanner *sc = g_engine.ScannerRef();
      if(sc != NULL)
        {
         CSymbolRuntime *rt = sc.Find(Symbol());
         if(rt != NULL)
            g_visual.DrawZones(Symbol(), rt.zones, TimeCurrent());
        }
     }
  }

//+------------------------------------------------------------------+
void OnTimer(void)
  {
   if(!g_engine.Ready()) return;
   g_engine.OnTimer();
   Housekeeping();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_engine.Ready()) return;
   g_engine.OnTransaction(trans, request, result);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   //--- a double click on an alert object opens the diagnostics in the log
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam, "qme_dash_") != 0) return;

   const SHealthReport h = CHealthMonitor::Evaluate(*g_engine.Account(), InpMagicNumber,
                                                    TimeCurrent(), 300, TimeCurrent(), 1800,
                                                    g_errors.Total(), 50);
   Print(CRuntimeDiagnostics::Compose(*g_engine.Config(), *g_engine.Account(),
                                      g_engine.Status(), g_engine.ScannerRef().Describe(),
                                      g_engine.Risk().Describe(), g_engine.Gateway().Describe(),
                                      "persistence on", g_engine.Controller().Describe(),
                                      h, g_errors, g_perf, *g_engine.ExecStats()));
  }
//+------------------------------------------------------------------+
