//+------------------------------------------------------------------+
//|                                               Data/MarketData     |
//|  QuantumMarketEngine — the market data orchestrator.                 |
//|                                                                   |
//|  Owns (by pointer, released in Shutdown):                          |
//|    CSymbolProfile    one per symbol                                |
//|    CTimeframeContext one per symbol x pipeline timeframe            |
//|    CTickProcessor    one per symbol                                |
//|    CDataSynchronizer + CMarketClock + CDataQualityGuard (static)    |
//|                                                                   |
//|  PUBLIC CONTRACT                                                  |
//|    bool Init(const SInputs&, string &err)                          |
//|    bool Refresh(const bool force = false)                          |
//|    CTimeframeContext* Context(symbol, tf)   (NULL when unavailable) |
//|    CSymbolProfile*    Profile(symbol)                              |
//|    int  SymbolCount() / TimeframeCount()                           |
//|                                                                   |
//|  A symbol whose history is unavailable is NOT dropped: it is        |
//|  reported as not ready so the scanner can log QME_REJ_NO_DATA.       |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_MARKETDATA_MQH__
#define __QME_DATA_MARKETDATA_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Core/Profiler.mqh"
#include "SymbolProfile.mqh"
#include "TimeframeContext.mqh"
#include "TickProcessor.mqh"
#include "MarketClock.mqh"
#include "DataSynchronizer.mqh"
#include "DataQualityGuard.mqh"
#include "HistoryValidator.mqh"

class CMarketData
  {
private:
   string            m_symbols[QME_MAX_SYMBOLS];
   bool              m_symbolReady[QME_MAX_SYMBOLS];
   CSymbolProfile   *m_profiles[QME_MAX_SYMBOLS];
   CTickProcessor   *m_ticks[QME_MAX_SYMBOLS];
   CTimeframeContext *m_ctx[QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES];
   datetime          m_seriesMark[QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES];

   ENUM_TIMEFRAMES   m_tfs[QME_MAX_TIMEFRAMES];
   int               m_tfCount;
   int               m_symbolCount;
   int               m_bars;
   bool              m_ready;

   CMarketClock      m_clock;
   CDataSynchronizer m_sync;
   SMarketSnapshot   m_snap[QME_MAX_SYMBOLS];   // last computed snapshot per symbol

   int               TfIndex(const ENUM_TIMEFRAMES tf);
   int               Slot(const int symIdx, const int tfIdx) { return(symIdx * QME_MAX_TIMEFRAMES + tfIdx); }

public:
                     CMarketData(void);
   bool              Init(const SInputs &in, string &err);
   void              Shutdown(void);
   bool              Refresh(const bool force = false);

   bool              Ready(void) { return(m_ready); }
   int               SymbolCount(void) { return(m_symbolCount); }
   int               TimeframeCount(void) { return(m_tfCount); }
   string            SymbolAt(const int i);
   ENUM_TIMEFRAMES   TimeframeAt(const int i);
   int               SymbolIndex(const string symbol);

   CSymbolProfile*   Profile(const int i);
   CSymbolProfile*   Profile(const string symbol);
   CTickProcessor*   Ticks(const int i);
   CTickProcessor*   Ticks(const string symbol);
   CTimeframeContext* Context(const int i, const ENUM_TIMEFRAMES tf);
   CTimeframeContext* Context(const string symbol, const ENUM_TIMEFRAMES tf);
   CTimeframeContext* ContextByTfIndex(const int i, const int tfIndex);

   bool              SymbolReady(const int i, string &note);
   CMarketClock*     Clock(void) { return(&m_clock); }
   CDataSynchronizer* Sync(void) { return(&m_sync); }
   SMarketSnapshot   Snapshot(const int i) { return(m_snap[i]); }
   void              SetSnapshot(const int i, const SMarketSnapshot &s) { m_snap[i] = s; }

   string            Describe(void);
  };

//------------------------------------------------------------------//
CMarketData::CMarketData(void)
  {
   m_tfCount = 0;
   m_symbolCount = 0;
   m_bars = QME_DEFAULT_BARS_CONTEXT;
   m_ready = false;
   for(int i = 0; i < QME_MAX_SYMBOLS; i++)
     {
      m_symbols[i] = "";
      m_symbolReady[i] = false;
      m_profiles[i] = NULL;
      m_ticks[i] = NULL;
      QmeSnapshotClear(m_snap[i]);
     }
   for(int i = 0; i < QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES; i++)
     {
      m_ctx[i] = NULL;
      m_seriesMark[i] = 0;
     }
   for(int i = 0; i < QME_MAX_TIMEFRAMES; i++)
      m_tfs[i] = PERIOD_CURRENT;
  }

//------------------------------------------------------------------//
int CMarketData::TfIndex(const ENUM_TIMEFRAMES tf)
  {
   for(int i = 0; i < m_tfCount; i++)
      if(m_tfs[i] == tf) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CMarketData::Init(const SInputs &in, string &err)
  {
   err = "";
   m_ready = false;
   m_bars = in.barsContext;
   m_clock.Refresh();
   m_sync.Reset();

   //--- symbols
   string syms[];
   m_symbolCount = QmeSplitList(in.symbolList, syms, QME_MAX_SYMBOLS);
   if(m_symbolCount <= 0)
     {
      err = "no symbols configured";
      return(false);
     }

   //--- timeframes actually used by the pipeline (deduplicated, highest first)
   SInputs tmp = in;
   CConfig cfgTmp;
   string cfgErr;
   if(!cfgTmp.Init(tmp, cfgErr))
     {
      err = "config rejected while resolving timeframes: " + cfgErr;
      return(false);
     }
   ENUM_TIMEFRAMES tfList[];
   m_tfCount = cfgTmp.PipelineTimeframes(tfList);
   if(m_tfCount <= 0 || m_tfCount > QME_MAX_TIMEFRAMES)
     {
      err = "invalid pipeline timeframe count";
      return(false);
     }
   for(int i = 0; i < m_tfCount; i++)
      m_tfs[i] = tfList[i];

   int usable = 0;
   for(int s = 0; s < m_symbolCount; s++)
     {
      const string sym = QmeUpper(syms[s]);
      m_symbols[s] = sym;
      m_symbolReady[s] = false;

      CSymbolProfile *profile = new CSymbolProfile();
      if(profile == NULL)
        {
         err = "out of memory allocating symbol profile";
         return(false);
        }
      string perr = "";
      if(!profile.Init(sym, perr))
        {
         QmeLogMsg(QME_LOG_ERROR, "MarketData", "symbol " + sym + " unusable: " + perr);
         m_profiles[s] = profile;   // keep it so the dashboard can report the reason
         continue;
        }
      m_profiles[s] = profile;
      QmeLogMsg(QME_LOG_INFO, "MarketData", profile.Describe());

      CTickProcessor *ticks = new CTickProcessor();
      if(ticks == NULL)
        {
         err = "out of memory allocating tick processor";
         return(false);
        }
      ticks.Init(sym);
      m_ticks[s] = ticks;

      //--- one context per pipeline timeframe
      bool allOk = true;
      for(int t = 0; t < m_tfCount; t++)
        {
         CTimeframeContext *ctx = new CTimeframeContext();
         if(ctx == NULL)
           {
            err = "out of memory allocating timeframe context";
            return(false);
           }
         const int slot = Slot(s, t);
         m_ctx[slot] = ctx;
         if(!ctx.Init(sym, m_tfs[t], m_bars))
           {
            QmeLogMsg(QME_LOG_WARN, "MarketData", sym + " " + QmeTimeframeName(m_tfs[t]) +
                      " data unavailable: " + ctx.LastError());
            allOk = false;
           }
         else
            m_seriesMark[slot] = (datetime)SeriesInfoInteger(sym, m_tfs[t], SERIES_LASTBAR_DATE);
        }

      m_symbolReady[s] = allOk;
      if(allOk) usable++;
      else
         QmeLogMsg(QME_LOG_WARN, "MarketData", sym + " will be skipped until its history is complete");
     }

   if(usable == 0)
     {
      err = "no symbol has usable market data";
      return(false);
     }

   m_ready = true;
   QmeLogMsg(QME_LOG_INFO, "MarketData", "initialised " + IntegerToString(usable) + "/" +
             IntegerToString(m_symbolCount) + " symbols across " +
             IntegerToString(m_tfCount) + " timeframes");
   return(true);
  }

//------------------------------------------------------------------//
void CMarketData::Shutdown(void)
  {
   for(int s = 0; s < QME_MAX_SYMBOLS; s++)
     {
      for(int t = 0; t < QME_MAX_TIMEFRAMES; t++)
        {
         const int slot = Slot(s, t);
         if(m_ctx[slot] != NULL)
           {
            m_ctx[slot].Shutdown();
            delete m_ctx[slot];
            m_ctx[slot] = NULL;
           }
        }
      if(m_ticks[s] != NULL)   { delete m_ticks[s];   m_ticks[s] = NULL; }
      if(m_profiles[s] != NULL){ delete m_profiles[s]; m_profiles[s] = NULL; }
     }
   m_ready = false;
   m_symbolCount = 0;
   m_tfCount = 0;
   QmeLogMsg(QME_LOG_INFO, "MarketData", "released all series and indicator handles");
  }

//------------------------------------------------------------------//
//| Refresh strategy:                                                  |
//|  * ticks are updated every call (cheap);                            |
//|  * a timeframe context is only re-copied when SERIES_LASTBAR_DATE     |
//|    changed (i.e. a new bar started => the previous one closed) OR     |
//|    when force=true.                                                |
//+------------------------------------------------------------------//
bool CMarketData::Refresh(const bool force)
  {
   if(!m_ready) return(false);
   m_clock.Refresh();

   int refreshed = 0;
   for(int s = 0; s < m_symbolCount; s++)
     {
      if(m_profiles[s] == NULL) continue;
      m_profiles[s].Reload();

      double spreadPoints = 0.0;
      if(m_ticks[s] != NULL)
        {
         m_ticks[s].Update();
         spreadPoints = m_ticks[s].SpreadPoints();
        }

      for(int t = 0; t < m_tfCount; t++)
        {
         const int slot = Slot(s, t);
         if(m_ctx[slot] == NULL) continue;

         const datetime mark = (datetime)SeriesInfoInteger(m_symbols[s], m_tfs[t], SERIES_LASTBAR_DATE);
         const bool changed = force || (mark != m_seriesMark[slot]) || (m_seriesMark[slot] == 0);

         if(changed)
           {
            m_ctx[slot].Refresh();
            m_seriesMark[slot] = mark;
            refreshed++;
           }

         //--- quality is evaluated every cycle: it depends on spread, not bars
         SDataQuality q;
         CDataQualityGuard::Evaluate(m_ctx[slot], spreadPoints, q);
         m_ctx[slot].SetQuality(q);
        }

      //--- a symbol becomes ready once every context has valid data
      bool allOk = true;
      for(int t = 0; t < m_tfCount; t++)
        {
         CTimeframeContext *c = m_ctx[Slot(s, t)];
         if(c == NULL || !c.DataValid() || !c.IndicatorReady())
           {
            allOk = false;
            break;
           }
        }
      m_symbolReady[s] = allOk;
     }
   return(refreshed >= 0);
  }

//------------------------------------------------------------------//
string CMarketData::SymbolAt(const int i)
  {
   if(i < 0 || i >= m_symbolCount) return("");
   return(m_symbols[i]);
  }

ENUM_TIMEFRAMES CMarketData::TimeframeAt(const int i)
  {
   if(i < 0 || i >= m_tfCount) return(PERIOD_CURRENT);
   return(m_tfs[i]);
  }

int CMarketData::SymbolIndex(const string symbol)
  {
   for(int i = 0; i < m_symbolCount; i++)
      if(m_symbols[i] == symbol) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
CSymbolProfile* CMarketData::Profile(const int i)
  {
   if(i < 0 || i >= m_symbolCount) return(NULL);
   return(m_profiles[i]);
  }

CSymbolProfile* CMarketData::Profile(const string symbol)
  {
   return(Profile(SymbolIndex(symbol)));
  }

CTickProcessor* CMarketData::Ticks(const int i)
  {
   if(i < 0 || i >= m_symbolCount) return(NULL);
   return(m_ticks[i]);
  }

CTickProcessor* CMarketData::Ticks(const string symbol)
  {
   return(Ticks(SymbolIndex(symbol)));
  }

//------------------------------------------------------------------//
CTimeframeContext* CMarketData::Context(const int i, const ENUM_TIMEFRAMES tf)
  {
   if(i < 0 || i >= m_symbolCount) return(NULL);
   const int t = TfIndex(tf);
   if(t < 0) return(NULL);
   return(m_ctx[Slot(i, t)]);
  }

CTimeframeContext* CMarketData::Context(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   return(Context(SymbolIndex(symbol), tf));
  }

CTimeframeContext* CMarketData::ContextByTfIndex(const int i, const int tfIndex)
  {
   if(i < 0 || i >= m_symbolCount || tfIndex < 0 || tfIndex >= m_tfCount) return(NULL);
   return(m_ctx[Slot(i, tfIndex)]);
  }

//------------------------------------------------------------------//
bool CMarketData::SymbolReady(const int i, string &note)
  {
   note = "";
   if(i < 0 || i >= m_symbolCount)
     {
      note = "symbol index out of range";
      return(false);
     }
   if(m_profiles[i] == NULL || !m_profiles[i].Ready())
     {
      note = "symbol specification unavailable";
      return(false);
     }
   if(!m_symbolReady[i])
     {
      note = "market data not ready (history or indicators incomplete)";
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
string CMarketData::Describe(void)
  {
   string s = "symbols=" + IntegerToString(m_symbolCount) +
              " timeframes=" + IntegerToString(m_tfCount) + " [";
   for(int t = 0; t < m_tfCount; t++)
      s += QmeTimeframeName(m_tfs[t]) + (t + 1 < m_tfCount ? "," : "");
   s += "] serverOffset=" + IntegerToString((long)m_clock.ServerGmtOffset()) + "s";
   return(s);
  }

#endif // __QME_DATA_MARKETDATA_MQH__
//+------------------------------------------------------------------+
