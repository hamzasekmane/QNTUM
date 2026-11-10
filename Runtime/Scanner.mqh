//+------------------------------------------------------------------+
//|                                              Runtime/Scanner      |
//|  The analysis factory: one SMarketAnalysis per symbol per timeframe. |
//|                                                                   |
//|  For every configured symbol the scanner holds the five timeframes    |
//|  of the pipeline (context, bias, structure, setup, entry), keeps      |
//|  their data fresh, and composes a complete SMarketAnalysis from the    |
//|  analysis engines. Nothing is cached across calls: if a timeframe is   |
//|  not ready the analysis is marked invalid instead of being reused.     |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_SCANNER_MQH__
#define __QME_RUNTIME_SCANNER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Data/MarketData.mqh"
#include "../Data/TimeframeContext.mqh"
#include "../Data/BarSeries.mqh"
#include "../Data/DataSynchronizer.mqh"
#include "../Data/DataQualityGuard.mqh"
#include "../Data/MarketClock.mqh"
#include "../Data/SymbolProfile.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "../Zones/ZoneEngine.mqh"

#define QME_TF_SLOTS 5

class CSymbolRuntime
  {
public:
   string            symbol;
   int               index;
   SSymbolSpec       spec;
   SAssetTuning      tuning;
   CTimeframeContext ctx[QME_TF_SLOTS];
   CBarSeries        series[QME_TF_SLOTS];
   SMarketAnalysis   analysis[QME_TF_SLOTS];
   bool              tfReady[QME_TF_SLOTS];
   CZoneEngine       zones;
   SMarketSnapshot   snapshot;
   SDataQuality      quality;
   datetime          lastBarTime;
   string            note;

                     CSymbolRuntime(void) { index = -1; lastBarTime = 0; note = ""; }
   bool              Init(const string sym, const int idx, const SInputs &in, const CConfig &cfg,
                          string &err);
   void              Shutdown(void);
   int               SlotOf(const ENUM_TIMEFRAMES tf);
  };

//------------------------------------------------------------------//
bool CSymbolRuntime::Init(const string sym, const int idx, const SInputs &in, const CConfig &cfg,
                          string &err)
  {
   err = "";
   symbol = sym;
   index = idx;
   lastBarTime = 0;
   note = "";

   if(!CSymbolSpecifications::EnsureSelected(symbol, err))
      return(false);
   if(!CSymbolSpecifications::Load(symbol, spec, err))
      return(false);
   const ENUM_QME_ASSET asset = CAssetClassTuning::Detect(spec.symbol, spec.path,
                                                          spec.description);
   CAssetClassTuning::Get(asset, tuning);

   const ENUM_TIMEFRAMES tfs[QME_TF_SLOTS];
   tfs[0] = in.tfContext;
   tfs[1] = in.tfBias;
   tfs[2] = in.tfStructure;
   tfs[3] = in.tfSetup;
   tfs[4] = in.tfEntry;

   const int bars = MathMax(in.barsContext, QME_MIN_BARS_REQUIRED);
   for(int i = 0; i < QME_TF_SLOTS; i++)
     {
      QmeAnalysisClear(analysis[i]);
      tfReady[i] = false;
      if(!ctx[i].Init(symbol, tfs[i], bars))
        {
         err = "cannot initialise context " + symbol + " " + QmeTfName(tfs[i]);
         return(false);
        }
      if(!series[i].Init(symbol, tfs[i], bars))
        {
         err = "cannot initialise series " + symbol + " " + QmeTfName(tfs[i]);
         return(false);
        }
     }

   if(!zones.Init(symbol, cfg.In.zoneMaxAgeHours, cfg.In.zoneMergeOverlapPct))
     {
      err = "cannot initialise zone engine for " + symbol;
      return(false);
     }

   QmeSnapshotClear(snapshot);
   snapshot.symbol = symbol;
   note = "ready";
   return(true);
  }

void CSymbolRuntime::Shutdown(void)
  {
   for(int i = 0; i < QME_TF_SLOTS; i++)
     {
      ctx[i].Shutdown();
      series[i].Reset();
     }
   zones.Shutdown();
  }

int CSymbolRuntime::SlotOf(const ENUM_TIMEFRAMES tf)
  {
   for(int i = 0; i < QME_TF_SLOTS; i++)
      if(ctx[i].Timeframe() == tf) return(i);
   return(-1);
  }

//+------------------------------------------------------------------+
class CScanner
  {
private:
   CMarketData      *m_data;
   CMarketClock      m_clock;
   CSymbolRuntime   *m_rt[QME_MAX_SYMBOLS];
   int               m_count;
   CConfig          *m_cfg;
   SSessionResult    m_session;
   long              m_scans;
   long              m_failures;

   bool              BuildAnalysis(CSymbolRuntime &rt, const int slot, const datetime gmtNow,
                                   const long gmtOffset, const double spreadPoints);
   bool              RefreshSymbol(CSymbolRuntime &rt, const datetime gmtNow, const long gmtOffset);

public:
                     CScanner(void);
                    ~CScanner(void) { Shutdown(); }
   bool              Init(CMarketData *data, CConfig *cfg, const SInputs &in, string &err);
   void              Shutdown(void);

   bool              Scan(const bool force, string &note);
   int               Count(void) { return(m_count); }
   CSymbolRuntime*   At(const int i);
   CSymbolRuntime*   Find(const string symbol);
   int               SymbolIndex(const string symbol);
   SSessionResult    Session(void) { return(m_session); }
   long              Scans(void) { return(m_scans); }
   long              Failures(void) { return(m_failures); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CScanner::CScanner(void)
  {
   m_data = NULL;
   m_count = 0;
   m_cfg = NULL;
   m_scans = 0;
   m_failures = 0;
   QmeSessionReset(m_session);
   for(int i = 0; i < QME_MAX_SYMBOLS; i++) m_rt[i] = NULL;
  }

//------------------------------------------------------------------//
bool CScanner::Init(CMarketData *data, CConfig *cfg, const SInputs &in, string &err)
  {
   err = "";
   if(data == NULL || cfg == NULL)
     {
      err = "scanner needs market data and configuration";
      return(false);
     }
   m_data = data;
   m_cfg = cfg;
   m_clock.Refresh();

   string syms[];
   const int n = QmeSplitList(in.symbolList, syms, QME_MAX_SYMBOLS);
   if(n <= 0)
     {
      err = "no symbols configured";
      return(false);
     }

   int created = 0;
   for(int i = 0; i < n; i++)
     {
      if(created >= QME_MAX_SYMBOLS) break;
      CSymbolRuntime *rt = new CSymbolRuntime();
      if(rt == NULL)
        {
         err = "out of memory creating symbol runtime";
         return(false);
        }
      string symErr = "";
      if(!rt.Init(syms[i], created, in, *cfg, symErr))
        {
         err = "symbol " + syms[i] + ": " + symErr;
         delete rt;
         return(false);
        }
      m_rt[created] = rt;
      created++;
     }
   m_count = created;
   QmeLogMsg(QME_LOG_INFO, "Scanner", IntegerToString(m_count) + " symbol(s) initialised");
   return(m_count > 0);
  }

//------------------------------------------------------------------//
void CScanner::Shutdown(void)
  {
   for(int i = 0; i < m_count; i++)
     {
      if(m_rt[i] == NULL) continue;
      m_rt[i].Shutdown();
      delete m_rt[i];
      m_rt[i] = NULL;
     }
   m_count = 0;
  }

//------------------------------------------------------------------//
CSymbolRuntime* CScanner::At(const int i)
  {
   if(i < 0 || i >= m_count) return(NULL);
   return(m_rt[i]);
  }

CSymbolRuntime* CScanner::Find(const string symbol)
  {
   for(int i = 0; i < m_count; i++)
      if(m_rt[i] != NULL && m_rt[i].symbol == symbol) return(m_rt[i]);
   return(NULL);
  }

int CScanner::SymbolIndex(const string symbol)
  {
   for(int i = 0; i < m_count; i++)
      if(m_rt[i] != NULL && m_rt[i].symbol == symbol) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CScanner::Scan(const bool force, string &note)
  {
   note = "";
   if(m_data == NULL || m_cfg == NULL)
     {
      note = "scanner not initialised";
      return(false);
     }

   m_clock.Refresh();
   m_session = CSessionEngine::Evaluate(m_clock, *m_cfg);
   if(!m_data.Refresh(force))
     {
      m_failures++;
      note = "market data refresh failed";
      return(false);
     }

   const datetime gmtNow = m_clock.GmtTime();
   const long offset = m_clock.ServerGmtOffset();
   int analysed = 0;
   for(int i = 0; i < m_count; i++)
     {
      if(m_rt[i] == NULL) continue;
      if(RefreshSymbol(*m_rt[i], gmtNow, offset)) analysed++;
     }

   m_scans++;
   if(analysed < m_count) m_failures++;
   note = IntegerToString(analysed) + "/" + IntegerToString(m_count) + " symbol(s) analysed";
   return(analysed > 0);
  }

//------------------------------------------------------------------//
bool CScanner::RefreshSymbol(CSymbolRuntime &rt, const datetime gmtNow, const long gmtOffset)
  {
   const double spreadPoints = (double)SymbolInfoInteger(rt.symbol, SYMBOL_SPREAD);

   bool anyReady = false;
   for(int i = 0; i < QME_TF_SLOTS; i++)
     {
      rt.tfReady[i] = false;
      if(!rt.ctx[i].Refresh()) continue;
      if(!rt.ctx[i].Ready()) continue;
      if(!rt.series[i].Refresh()) continue;

      if(!BuildAnalysis(rt, i, gmtNow, gmtOffset, spreadPoints)) continue;
      rt.tfReady[i] = anyReady = true;
     }

   if(!anyReady)
     {
      rt.note = "no timeframe ready";
      QmeLogMsg(QME_LOG_WARN, "Scanner", rt.symbol + ": " + rt.note);
      return(false);
     }

   //--- data quality on the entry timeframe (the one we trade from)
   SDataQuality q;
   if(rt.tfReady[4]) CDataQualityGuard::Evaluate(rt.ctx[4], spreadPoints, q);
   else CDataQualityGuard::Evaluate(rt.ctx[3], spreadPoints, q);
   rt.quality = q;
   rt.ctx[4].SetQuality(q);

   //--- zones are refreshed from the setup timeframe and the entry timeframe
   const datetime now = TimeCurrent();
   if(rt.tfReady[3]) rt.zones.Update(rt.analysis[3], rt.series[3], now, rt.spec.point);
   if(rt.tfReady[4]) rt.zones.Update(rt.analysis[4], rt.series[4], now, rt.spec.point);
   rt.zones.Board().Prune(now, m_cfg.In.zoneMaxAgeHours,
                          rt.analysis[4].price, rt.analysis[4].atr);

   //--- snapshot for the dashboard and the decision layer
   SMarketSnapshot s = rt.snapshot;
   const int entry = rt.tfReady[4] ? 4 : 3;
   s.symbol = rt.symbol;
   s.time = now;
   s.entryTf = rt.ctx[entry].Timeframe();
   s.bid = SymbolInfoDouble(rt.symbol, SYMBOL_BID);
   s.ask = SymbolInfoDouble(rt.symbol, SYMBOL_ASK);
   s.spreadPoints = spreadPoints;
   s.atr = rt.analysis[entry].atr;
   s.atrAvg = rt.ctx[entry].AtrAvg();
   s.rsi = rt.ctx[entry].Rsi();
   s.emaFast = rt.ctx[entry].EmaFast();
   s.emaSlow = rt.ctx[entry].EmaSlow();
   s.emaTrend = rt.ctx[entry].EmaTrend();
   s.regime = rt.analysis[entry].regime.regime;
   s.trend = rt.analysis[entry].trend.trend;
   s.volatility = rt.analysis[entry].volatility.state;
   s.session = m_session.session;
   s.bias = rt.analysis[1].bias.side;
   s.biasScore = rt.analysis[1].bias.score;
   s.momentum = rt.analysis[entry].momentum.value;
   s.structureValid = rt.analysis[entry].structureValid;
   s.liquidityValid = rt.analysis[entry].liquidityValid;
   s.dataValid = rt.analysis[entry].valid && q.ok;
   s.quality = q;
   s.zoneCount = rt.zones.ActiveCount(now);
   rt.snapshot = s;
   rt.lastBarTime = rt.series[entry].LastClosedBarTime();
   rt.note = "ok";
   return(true);
  }

//------------------------------------------------------------------//
bool CScanner::BuildAnalysis(CSymbolRuntime &rt, const int slot, const datetime gmtNow,
                             const long gmtOffset, const double spreadPoints)
  {
   SMarketAnalysis a;
   QmeAnalysisClear(a);

   CTimeframeContext *ctx = GetPointer(rt.ctx[slot]);
   CBarSeries *sr = GetPointer(rt.series[slot]);

   a.symbol = rt.symbol;
   a.tf = ctx.Timeframe();
   a.barTime = sr.LastClosedBarTime();
   a.price = sr.Close(0);
   a.atr = ctx.Atr();
   a.avgBody = ctx.AvgBody();
   a.avgRange = ctx.AvgRange(20);
   a.spreadPoints = spreadPoints;

   if(a.price <= 0.0 || a.atr <= 0.0 || a.barTime == 0)
     {
      rt.note = "incomplete data on " + QmeTfName(a.tf);
      return(false);
     }

   //--- market context
   a.trend = CTrendEngine::Evaluate(*ctx);
   a.momentum = CMomentumEngine::Evaluate(*ctx);
   a.volatility = CVolatilityEngine::Evaluate(*ctx, rt.tuning);
   a.regime = CRegimeEngine::Evaluate(*ctx, a.trend, a.volatility, 20);
   a.bias = CBiasEngine::Evaluate(a.trend, a.momentum, a.regime);
   a.session = m_session;

   //--- structure
   const int scanBars = QME_SCAN_BARS;
   a.structureValid = CStructureEngine::Evaluate(*ctx, rt.tuning, scanBars, a.structure);
   if(a.structureValid)
     {
      a.bos = CBosEngine::Detect(*sr, a.structure, a.atr, scanBars);
      a.mss = CMssEngine::Detect(*sr, a.structure, a.atr, scanBars);
     }
   a.breakout = CBreakoutEngine::Detect(*sr, a.atr, 20, 2, 0.10);

   //--- liquidity
   a.liquidityValid = CLiquidityEngine::Evaluate(*ctx, a.structure, gmtNow, gmtOffset,
                                                 m_session.session, a.liquidity);
   if(a.liquidityValid)
     {
      a.sweep = CLiquiditySweep::Best(*sr, a.liquidity.map.levels, a.liquidity.map.count,
                                      a.atr, scanBars, 0.15);
     }
   CVolumeProfile::Build(*sr, (int)MathMin(sr.Count(), 200), 24, a.volumeProfile);

   //--- price action
   a.fvgCount = CFvgEngine::Detect(*sr, a.atr, 0.25, scanBars, QME_MAX_FVGS, a.fvgs);
   a.obCount = COrderBlockEngine::Detect(*sr, a.atr, a.avgBody, rt.tuning.displacementMult,
                                         scanBars, 60, QME_MAX_OBS, a.orderBlocks);
   CCandleEngine::Evaluate(*sr, 0, a.candle, rt.tuning.displacementMult);
   a.pattern = CCandlePatternEngine::Detect(*sr, 0, rt.tuning.displacementMult);
   a.displacement = CDisplacementEngine::Latest(*sr, a.atr, a.avgBody, scanBars,
                                                rt.tuning.displacementMult);
   a.location = CLocationEngine::Evaluate(a.price, a.atr, 0.5);
   a.range = CPremiumDiscountEngine::FromStructure(a.structure, a.price, 0.10);

   //--- reaction at the nearest liquidity level on either side
   SLiquidityLevel lvl;
   bool haveLevel = false;
   if(a.liquidityValid)
     {
      SLiquidityLevel above, below;
      const bool hA = CLiquidityMapBuilder::NearestAbove(a.liquidity.map, a.price, above);
      const bool hB = CLiquidityMapBuilder::NearestBelow(a.liquidity.map, a.price, below);
      if(hA && hB)
        {
         if(MathAbs(above.price - a.price) <= MathAbs(below.price - a.price))
           { lvl = above; haveLevel = true; }
         else
           { lvl = below; haveLevel = true; }
        }
      else if(hA) { lvl = above; haveLevel = true; }
      else if(hB) { lvl = below; haveLevel = true; }
     }
   if(haveLevel)
      a.reaction = CReactionEngine::AtLevel(*sr, lvl.price, a.atr, scanBars, 0.25, 0.30);

   a.valid = a.structureValid && a.liquidityValid && a.trend.valid && a.bias.valid;
   rt.analysis[slot] = a;
   return(a.valid || a.structureValid);
  }

//------------------------------------------------------------------//
string CScanner::Describe(void)
  {
   int ready = 0;
   for(int i = 0; i < m_count; i++)
      if(m_rt[i] != NULL && m_rt[i].snapshot.dataValid) ready++;
   return("scanner symbols=" + IntegerToString(m_count) +
          " valid=" + IntegerToString(ready) +
          " scans=" + IntegerToString((int)m_scans) +
          " failures=" + IntegerToString((int)m_failures) +
          " session=" + QmeSessionName(m_session.session));
  }

#endif // __QME_RUNTIME_SCANNER_MQH__
//+------------------------------------------------------------------+
