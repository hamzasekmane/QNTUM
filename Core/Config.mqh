//+------------------------------------------------------------------+
//|                                                     Config.mqh   |
//|  QuantumMarketEngine — configuration aggregate + validation.      |
//|                                                                   |
//|  OWNERSHIP: one instance owned by CEngine, published as g_cfg.    |
//|  RULE: every trading switch defaults to FALSE. Validation never    |
//|  enables anything; it can only reject a configuration.             |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_CONFIG_MQH__
#define __QME_CORE_CONFIG_MQH__

#include "Constants.mqh"
#include "Enums.mqh"
#include "Types.mqh"
#include "Utils.mqh"
#include "ErrorCodes.mqh"

//+------------------------------------------------------------------+
//| Raw inputs. Populated from `input` variables in QME_Main.mq5.     |
//| .mqh files never declare `input` variables.                       |
//+------------------------------------------------------------------+
struct SInputs
  {
   //--- runtime / logging
   ENUM_QME_SEVERITY logLevel;
   bool              logToFile;
   bool              logCycleDetail;
   bool              enableDashboard;
   int               dashboardRefreshSec;

   //--- scope
   string            symbolList;
   ulong             magic;
   int               scanIntervalMs;
   int               barsContext;

   //--- timeframes: context -> bias -> structure -> setup -> entry
   ENUM_TIMEFRAMES   tfContext;
   ENUM_TIMEFRAMES   tfBias;
   ENUM_TIMEFRAMES   tfStructure;
   ENUM_TIMEFRAMES   tfSetup;
   ENUM_TIMEFRAMES   tfEntry;

   //--- trading authorization (ALL FALSE BY DEFAULT)
   bool              enableDemoTrading;
   bool              enableRealTrading;
   bool              realTradingArmed;
   long              expectedRealAccountLogin;
   bool              analysisOnly;

   //--- directional permissions
   bool              allowBuy;
   bool              allowSell;

   //--- risk
   double            riskPerTradePct;
   double            maxDailyLossPct;
   double            maxDrawdownPct;
   int               maxPositions;
   int               maxPositionsPerSymbol;
   double            maxSymbolExposurePct;
   double            maxPortfolioExposurePct;
   int               maxConsecutiveLosses;
   double            minRR;
   double            maxSpreadPoints;      // 0 = disabled
   double            maxSpreadAtrRatio;    // spread / ATR cap
   bool              sessionFilterEnabled;
   bool              allowSessionAsia;
   bool              allowSessionLondon;
   bool              allowSessionNewYork;
   bool              allowSessionOverlap;
   bool              newsFilterEnabled;
   int               newsBlackoutMinutes;
   string            newsBlackoutWindows;  // "HH:MM-HH:MM;HH:MM-HH:MM" GMT

   //--- strategy
   double            minScore;
   double            minConfluence;
   bool              requireHtfAlignment;
   int               maxSignalsPerDay;
   int               signalExpiryMinutes;
   int               cooldownSecPerSymbol;
   int               zoneMaxAgeHours;
   double            zoneMergeOverlapPct;

   //--- execution
   int               maxRetries;
   int               retryDelayMs;
   int               deviationPoints;
   bool              closeOnOppositeSignal;
   double            breakEvenAtR;         // 0 = disabled; otherwise move SL to entry at N x R
   bool              tradeJournalEnabled;
   bool              profileCycles;

   //--- persistence
   bool              persistState;
   int               checkpointSec;
  };

//--- safe defaults: identical to the `input` defaults in QME_Main.mq5
void QmeInputsDefaults(SInputs &in)
  {
   in.logLevel              = QME_LOG_INFO;
   in.logToFile             = true;
   in.logCycleDetail        = false;
   in.enableDashboard       = true;
   in.dashboardRefreshSec   = 2;

   in.symbolList            = "EURUSD,GBPUSD,USDJPY,XAUUSD";
   in.magic                 = 20261110;
   in.scanIntervalMs        = 5000;
   in.barsContext           = QME_DEFAULT_BARS_CONTEXT;

   in.tfContext             = PERIOD_D1;
   in.tfBias                = PERIOD_H4;
   in.tfStructure           = PERIOD_H1;
   in.tfSetup               = PERIOD_M15;
   in.tfEntry               = PERIOD_M5;

   in.enableDemoTrading     = false;
   in.enableRealTrading     = false;
   in.realTradingArmed      = false;
   in.expectedRealAccountLogin = 0;
   in.analysisOnly          = true;

   in.allowBuy              = true;
   in.allowSell             = true;

   in.riskPerTradePct       = 0.5;
   in.maxDailyLossPct       = 3.0;
   in.maxDrawdownPct        = 10.0;
   in.maxPositions          = 3;
   in.maxPositionsPerSymbol = 1;
   in.maxSymbolExposurePct  = 5.0;
   in.maxPortfolioExposurePct = 12.0;
   in.maxConsecutiveLosses  = 3;
   in.minRR                 = QME_MIN_RR_DEFAULT;
   in.maxSpreadPoints       = 0.0;
   in.maxSpreadAtrRatio     = 0.15;
   in.sessionFilterEnabled  = false;
   in.allowSessionAsia      = true;
   in.allowSessionLondon    = true;
   in.allowSessionNewYork   = true;
   in.allowSessionOverlap   = true;
   in.newsFilterEnabled     = false;
   in.newsBlackoutMinutes   = 30;
   in.newsBlackoutWindows   = "";

   in.minScore              = QME_SCORE_MIN_DEFAULT;
   in.minConfluence         = 0.4;
   in.requireHtfAlignment   = true;
   in.maxSignalsPerDay      = 12;
   in.signalExpiryMinutes   = 240;
   in.cooldownSecPerSymbol  = 900;
   in.zoneMaxAgeHours       = 72;
   in.zoneMergeOverlapPct   = 60.0;

   in.maxRetries            = 2;
   in.retryDelayMs          = 500;
   in.deviationPoints       = 20;
   in.closeOnOppositeSignal = false;
   in.breakEvenAtR          = 0.0;
   in.tradeJournalEnabled   = true;
   in.profileCycles         = false;

   in.persistState          = true;
   in.checkpointSec         = 30;
  }

//+------------------------------------------------------------------+
//| CConfig                                                          |
//|  Holds the validated configuration and answers policy questions.  |
//|  Inputs:  SInputs (raw, from the EA).                             |
//|  Outputs: validated accessors + explicit error strings.            |
//+------------------------------------------------------------------+
class CConfig
  {
public:
   SInputs           In;          // read-only by convention: only Init() writes it
   bool              initialized;

                     CConfig(void) { initialized = false; QmeInputsDefaults(In); }

   //--- validate and adopt; returns false with a precise reason on failure
   bool              Init(const SInputs &src, string &err);

   //--- symbol list parsing (deduplicated, capacity-checked)
   int               Symbols(string &out[]);

   //--- is this timeframe used by the pipeline?
   bool              IsPipelineTimeframe(const ENUM_TIMEFRAMES tf);

   //--- ordered higher-to-lower list of used timeframes (index 0 = highest)
   int               PipelineTimeframes(ENUM_TIMEFRAMES &out[]);

   //--- session policy
   bool              SessionAllowed(const ENUM_QME_SESSION s) const;

   //--- is the GMT time inside a manual blackout window?
   bool              InBlackoutWindow(const datetime gmtTime) const;

   //--- trading authorization flags (checked again at execution time)
   bool              DemoTradingEnabled() const { return(In.enableDemoTrading && !In.analysisOnly); }
   bool              RealTradingEnabled() const { return(In.enableRealTrading && In.realTradingArmed && !In.analysisOnly); }

private:
   bool              m_blackoutsParsed;
   int               m_blackoutStart[QME_MAX_SYMBOLS];  // minutes from midnight
   int               m_blackoutEnd[QME_MAX_SYMBOLS];
   int               m_blackoutCount;

   bool              ParseBlackouts(string &err);
   bool              Fail(string &err, const string msg);
  };

//------------------------------------------------------------------//
bool CConfig::Fail(string &err, const string msg)
  {
   err = msg;
   return(false);
  }

//------------------------------------------------------------------//
bool CConfig::Init(const SInputs &src, string &err)
  {
   In = src;
   err = "";
   initialized = false;

   //--- scope
   string syms[];
   const int n = QmeSplitList(In.symbolList, syms, QME_MAX_SYMBOLS);
   if(n <= 0)
      return(Fail(err, "symbolList is empty"));
   if(n > QME_MAX_SYMBOLS)
      return(Fail(err, "symbolList exceeds QME_MAX_SYMBOLS"));

   //--- volumes / risk ranges
   if(In.riskPerTradePct <= 0.0 || In.riskPerTradePct > 10.0)
      return(Fail(err, "riskPerTradePct must be in (0,10]"));
   if(In.maxDailyLossPct <= 0.0 || In.maxDailyLossPct > 50.0)
      return(Fail(err, "maxDailyLossPct must be in (0,50]"));
   if(In.maxDrawdownPct <= 0.0 || In.maxDrawdownPct > 90.0)
      return(Fail(err, "maxDrawdownPct must be in (0,90]"));
   if(In.maxDailyLossPct > In.maxDrawdownPct)
      return(Fail(err, "maxDailyLossPct must not exceed maxDrawdownPct"));
   if(In.maxPositions < 1 || In.maxPositions > 100)
      return(Fail(err, "maxPositions must be in [1,100]"));
   if(In.maxPositionsPerSymbol < 1 || In.maxPositionsPerSymbol > In.maxPositions)
      return(Fail(err, "maxPositionsPerSymbol must be in [1,maxPositions]"));
   if(In.maxSymbolExposurePct <= 0.0 || In.maxSymbolExposurePct > 100.0)
      return(Fail(err, "maxSymbolExposurePct must be in (0,100]"));
   if(In.maxPortfolioExposurePct <= 0.0 || In.maxPortfolioExposurePct > 100.0)
      return(Fail(err, "maxPortfolioExposurePct must be in (0,100]"));
   if(In.maxSymbolExposurePct > In.maxPortfolioExposurePct)
      return(Fail(err, "maxSymbolExposurePct must not exceed maxPortfolioExposurePct"));
   if(In.maxConsecutiveLosses < 0 || In.maxConsecutiveLosses > 50)
      return(Fail(err, "maxConsecutiveLosses must be in [0,50]"));
   if(In.minRR < 0.5 || In.minRR > 20.0)
      return(Fail(err, "minRR must be in [0.5,20]"));
   if(In.breakEvenAtR < 0.0 || In.breakEvenAtR > 10.0)
      return(Fail(err, "breakEvenAtR must be in [0,10] (0 disables)"));

   //--- strategy
   if(In.minScore < 0.0 || In.minScore > QME_SCORE_MAX)
      return(Fail(err, "minScore must be in [0,100]"));
   if(In.minConfluence < 0.0 || In.minConfluence > 1.0)
      return(Fail(err, "minConfluence must be in [0,1]"));
   if(In.maxSignalsPerDay < 1)
      return(Fail(err, "maxSignalsPerDay must be >= 1"));
   if(In.signalExpiryMinutes < QmeTimeframeMinutes(In.tfEntry))
      return(Fail(err, "signalExpiryMinutes must be >= entry timeframe length"));
   if(In.cooldownSecPerSymbol < 0)
      return(Fail(err, "cooldownSecPerSymbol must be >= 0"));

   //--- runtime
   if(In.scanIntervalMs < 250 || In.scanIntervalMs > 3600000)
      return(Fail(err, "scanIntervalMs must be in [250,3600000]"));
   if(In.barsContext < QME_MIN_BARS_REQUIRED)
      return(Fail(err, "barsContext must be >= QME_MIN_BARS_REQUIRED"));
   if(In.barsContext > 100000)
      return(Fail(err, "barsContext is unreasonably large"));
   if(In.dashboardRefreshSec < 1 || In.dashboardRefreshSec > 60)
      return(Fail(err, "dashboardRefreshSec must be in [1,60]"));
   if(In.maxRetries < 0 || In.maxRetries > 5)
      return(Fail(err, "maxRetries must be in [0,5]"));
   if(In.deviationPoints < 0 || In.deviationPoints > 1000)
      return(Fail(err, "deviationPoints must be in [0,1000]"));
   if(In.maxSpreadAtrRatio < 0.0 || In.maxSpreadAtrRatio > 5.0)
      return(Fail(err, "maxSpreadAtrRatio must be in [0,5]"));

   //--- timeframe ordering: context >= bias >= structure >= setup >= entry
   const int mCtx = QmeTimeframeMinutes(In.tfContext);
   const int mBia = QmeTimeframeMinutes(In.tfBias);
   const int mStr = QmeTimeframeMinutes(In.tfStructure);
   const int mSet = QmeTimeframeMinutes(In.tfSetup);
   const int mEnt = QmeTimeframeMinutes(In.tfEntry);
   if(mCtx < mBia || mBia < mStr || mStr < mSet || mSet < mEnt)
      return(Fail(err, "timeframes must be non-increasing: Context >= Bias >= Structure >= Setup >= Entry"));
   if(In.tfEntry > PERIOD_M5)
      return(Fail(err, "tfEntry must be M5 or faster for entry confirmation"));

   //--- REAL trading: login must be pinned, otherwise real can never be armed
   if(In.enableRealTrading && In.expectedRealAccountLogin <= 0)
      return(Fail(err, "enableRealTrading requires expectedRealAccountLogin > 0"));
   if(In.realTradingArmed && !In.enableRealTrading)
      return(Fail(err, "realTradingArmed set while enableRealTrading is false (ambiguous intent)"));
   if(In.enableDemoTrading && In.analysisOnly)
     {
      //--- not fatal: analysisOnly always wins, but say it clearly
     }

   //--- blackout windows
   if(!ParseBlackouts(err))
      return(false);

   if(In.barsContext < 10 * QmeTimeframeMinutes(In.tfEntry))
     {
      //--- not fatal, but structure detection needs history
     }

   initialized = true;
   return(true);
  }

//------------------------------------------------------------------//
bool CConfig::ParseBlackouts(string &err)
  {
   m_blackoutCount = 0;
   m_blackoutsParsed = true;
   if(StringLen(In.newsBlackoutWindows) == 0)
      return(true);

   string parts[];
   const int n = QmeSplitList(In.newsBlackoutWindows, parts, QME_MAX_SYMBOLS);
   for(int i = 0; i < n; i++)
     {
      //--- expected "HH:MM-HH:MM"
      const int dash = StringFind(parts[i], "-");
      if(dash <= 0)
         return(Fail(err, "newsBlackoutWindows entry is not HH:MM-HH:MM: " + parts[i]));
      const string a = StringSubstr(parts[i], 0, dash);
      const string b = StringSubstr(parts[i], dash + 1);
      const int cA = StringFind(a, ":");
      const int cB = StringFind(b, ":");
      if(cA <= 0 || cB <= 0)
         return(Fail(err, "newsBlackoutWindows entry has no ':' separator: " + parts[i]));
      const int h1 = (int)StringToInteger(StringSubstr(a, 0, cA));
      const int m1 = (int)StringToInteger(StringSubstr(a, cA + 1));
      const int h2 = (int)StringToInteger(StringSubstr(b, 0, cB));
      const int m2 = (int)StringToInteger(StringSubstr(b, cB + 1));
      if(h1 < 0 || h1 > 23 || h2 < 0 || h2 > 23 || m1 < 0 || m1 > 59 || m2 < 0 || m2 > 59)
         return(Fail(err, "newsBlackoutWindows entry out of range: " + parts[i]));
      m_blackoutStart[m_blackoutCount] = h1 * 60 + m1;
      m_blackoutEnd[m_blackoutCount]   = h2 * 60 + m2;
      m_blackoutCount++;
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CConfig::InBlackoutWindow(const datetime gmtTime) const
  {
   if(!In.newsFilterEnabled || !m_blackoutsParsed || m_blackoutCount <= 0)
      return(false);
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   const int nowMin = dt.hour * 60 + dt.min;
   for(int i = 0; i < m_blackoutCount; i++)
     {
      const int s = m_blackoutStart[i];
      const int e = m_blackoutEnd[i];
      if(s <= e)
        {
         if(nowMin >= s && nowMin <= e) return(true);
        }
      else // window crosses midnight
        {
         if(nowMin >= s || nowMin <= e) return(true);
        }
     }
   return(false);
  }

//------------------------------------------------------------------//
int CConfig::Symbols(string &out[])
  {
   return(QmeSplitList(In.symbolList, out, QME_MAX_SYMBOLS));
  }

//------------------------------------------------------------------//
bool CConfig::IsPipelineTimeframe(const ENUM_TIMEFRAMES tf)
  {
   if(tf == In.tfContext)   return(true);
   if(tf == In.tfBias)      return(true);
   if(tf == In.tfStructure) return(true);
   if(tf == In.tfSetup)     return(true);
   if(tf == In.tfEntry)     return(true);
   return(false);
  }

//------------------------------------------------------------------//
int CConfig::PipelineTimeframes(ENUM_TIMEFRAMES &out[])
  {
   ArrayResize(out, 0);
   const ENUM_TIMEFRAMES all[5] = {In.tfContext, In.tfBias, In.tfStructure, In.tfSetup, In.tfEntry};
   //--- keep the configured order (highest first) but drop duplicates
   for(int i = 0; i < 5; i++)
     {
      bool dup = false;
      for(int j = 0; j < ArraySize(out); j++)
         if(out[j] == all[i]) { dup = true; break; }
      if(!dup)
        {
         const int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k] = all[i];
        }
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
bool CConfig::SessionAllowed(const ENUM_QME_SESSION s) const
  {
   if(!In.sessionFilterEnabled) return(true);
   switch(s)
     {
      case QME_SESSION_ASIA:    return(In.allowSessionAsia);
      case QME_SESSION_LONDON:  return(In.allowSessionLondon);
      case QME_SESSION_NEWYORK: return(In.allowSessionNewYork);
      case QME_SESSION_OVERLAP: return(In.allowSessionOverlap);
      case QME_SESSION_OFFHOURS:return(false);
      case QME_SESSION_UNKNOWN: return(false);
     }
   return(false);
  }

//--- the single configuration instance used by all modules
CConfig *g_cfg = NULL;

#endif // __QME_CORE_CONFIG_MQH__
//+------------------------------------------------------------------+
