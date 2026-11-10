//+------------------------------------------------------------------+
//|                                             Data/IndicatorCache   |
//|  QuantumMarketEngine — indicator handles with strict readiness      |
//|  checks.                                                          |
//|                                                                   |
//|  RULES:                                                           |
//|   * handles are created once per symbol/timeframe and released in  |
//|     Release() (called from every Shutdown() chain);                 |
//|   * CopyBuffer is called with a 2-bar offset so that shift 0 in the |
//|     accessor always means "the newest CLOSED bar";                  |
//|   * BarsCalculated is checked before any value is consumed;         |
//|   * a failure returns false and never invents a value.              |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_INDICATORCACHE_MQH__
#define __QME_DATA_INDICATORCACHE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Core/Logger.mqh"

class CIndicatorCache
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_handleAtr;
   int               m_handleRsi;
   int               m_handleEmaFast;
   int               m_handleEmaSlow;
   int               m_handleEmaTrend;
   int               m_atrPeriod;
   int               m_rsiPeriod;
   int               m_emaFastPeriod;
   int               m_emaSlowPeriod;
   int               m_emaTrendPeriod;
   bool              m_ready;
   string            m_error;

   bool              Value(const int handle, const int shift, const int period,
                           const bool smoothed, double &out) const;
   int               WarmupBars(void) const;

public:
   void              Reset(void);
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int atrPeriod, const int rsiPeriod,
                          const int emaFast, const int emaSlow, const int emaTrend);
   void              Release(void);
   bool              Ready(void);

   bool              Atr(const int shift, double &v);
   bool              Rsi(const int shift, double &v);
   bool              EmaFast(const int shift, double &v);
   bool              EmaSlow(const int shift, double &v);
   bool              EmaTrend(const int shift, double &v);

   //--- N closed values of an indicator, oldest first (for averaging)
   bool              AtrSeries(const int count, double &out[]);
   bool              RsiSeries(const int count, double &out[]);

   string            LastError(void) { return(m_error); }
   int               Handles(void);
  };

//------------------------------------------------------------------//
void CIndicatorCache::Reset(void)
  {
   m_symbol = "";
   m_tf = PERIOD_CURRENT;
   m_handleAtr = INVALID_HANDLE;
   m_handleRsi = INVALID_HANDLE;
   m_handleEmaFast = INVALID_HANDLE;
   m_handleEmaSlow = INVALID_HANDLE;
   m_handleEmaTrend = INVALID_HANDLE;
   m_atrPeriod = 14;
   m_rsiPeriod = 14;
   m_emaFastPeriod = 20;
   m_emaSlowPeriod = 50;
   m_emaTrendPeriod = 200;
   m_ready = false;
   m_error = "";
  }

//------------------------------------------------------------------//
bool CIndicatorCache::Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int atrPeriod, const int rsiPeriod,
                           const int emaFast, const int emaSlow, const int emaTrend)
  {
   Release();
   m_symbol = symbol;
   m_tf = tf;
   m_atrPeriod = (atrPeriod < 2) ? 14 : atrPeriod;
   m_rsiPeriod = (rsiPeriod < 2) ? 14 : rsiPeriod;
   m_emaFastPeriod = (emaFast < 2) ? 20 : emaFast;
   m_emaSlowPeriod = (emaSlow < 2) ? 50 : emaSlow;
   m_emaTrendPeriod = (emaTrend < 2) ? 200 : emaTrend;

   m_handleAtr      = iATR(symbol, tf, m_atrPeriod);
   m_handleRsi      = iRSI(symbol, tf, m_rsiPeriod, PRICE_CLOSE);
   m_handleEmaFast  = iMA(symbol, tf, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_handleEmaSlow  = iMA(symbol, tf, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_handleEmaTrend = iMA(symbol, tf, m_emaTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(m_handleAtr == INVALID_HANDLE || m_handleRsi == INVALID_HANDLE ||
      m_handleEmaFast == INVALID_HANDLE || m_handleEmaSlow == INVALID_HANDLE ||
      m_handleEmaTrend == INVALID_HANDLE)
     {
      m_error = "indicator handle creation failed for " + symbol + " " + QmeTimeframeName(tf) +
                " (" + QmeLastErrorText() + ")";
      QmeLogMsg(QME_LOG_ERROR, "Indicators", m_error);
      Release();
      return(false);
     }
   m_ready = false;
   return(true);
  }

//------------------------------------------------------------------//
void CIndicatorCache::Release(void)
  {
   if(m_handleAtr != INVALID_HANDLE)      { IndicatorRelease(m_handleAtr);      m_handleAtr = INVALID_HANDLE; }
   if(m_handleRsi != INVALID_HANDLE)      { IndicatorRelease(m_handleRsi);      m_handleRsi = INVALID_HANDLE; }
   if(m_handleEmaFast != INVALID_HANDLE)  { IndicatorRelease(m_handleEmaFast);  m_handleEmaFast = INVALID_HANDLE; }
   if(m_handleEmaSlow != INVALID_HANDLE)  { IndicatorRelease(m_handleEmaSlow);  m_handleEmaSlow = INVALID_HANDLE; }
   if(m_handleEmaTrend != INVALID_HANDLE) { IndicatorRelease(m_handleEmaTrend); m_handleEmaTrend = INVALID_HANDLE; }
   m_ready = false;
  }

//------------------------------------------------------------------//
int CIndicatorCache::Handles(void)
  {
   int n = 0;
   if(m_handleAtr != INVALID_HANDLE) n++;
   if(m_handleRsi != INVALID_HANDLE) n++;
   if(m_handleEmaFast != INVALID_HANDLE) n++;
   if(m_handleEmaSlow != INVALID_HANDLE) n++;
   if(m_handleEmaTrend != INVALID_HANDLE) n++;
   return(n);
  }

//------------------------------------------------------------------//
int CIndicatorCache::WarmupBars(void) const
  {
   int w = m_atrPeriod;
   if(m_rsiPeriod > w) w = m_rsiPeriod;
   if(m_emaFastPeriod > w) w = m_emaFastPeriod;
   if(m_emaSlowPeriod > w) w = m_emaSlowPeriod;
   if(m_emaTrendPeriod > w) w = m_emaTrendPeriod;
   return(w + 2);
  }

//------------------------------------------------------------------//
bool CIndicatorCache::Ready(void)
  {
   if(m_handleAtr == INVALID_HANDLE) return(false);
   const int need = WarmupBars();
   const int calc = BarsCalculated(m_handleAtr);
   if(calc < need)
     {
      m_ready = false;
      return(false);
     }
   const int calcRsi = BarsCalculated(m_handleRsi);
   const int calcFast = BarsCalculated(m_handleEmaFast);
   const int calcSlow = BarsCalculated(m_handleEmaSlow);
   const int calcTrend = BarsCalculated(m_handleEmaTrend);
   m_ready = (calcRsi >= need && calcFast >= need && calcSlow >= need && calcTrend >= need);
   return(m_ready);
  }

//------------------------------------------------------------------//
//| Copy `count` values and return the one belonging to `shift` closed |
//| bars back. The buffer holds the forming bar at index 0, so closed   |
//| bar `shift` lives at index shift+1 (when AS_SERIES is true).        |
//+------------------------------------------------------------------//
bool CIndicatorCache::Value(const int handle, const int shift, const int period,
                            const bool smoothed, double &out) const
  {
   out = 0.0;
   if(handle == INVALID_HANDLE) return(false);
   if(shift < 0) return(false);
   if(BarsCalculated(handle) < shift + 2) return(false);

   double buf[];
   ArraySetAsSeries(buf, true);
   const int need = shift + 2;
   const int copied = CopyBuffer(handle, 0, 0, need, buf);
   if(copied < need)
      return(false);
   const double v = buf[shift + 1];
   if(!QmeIsFinite(v)) return(false);
   out = v;
   return(true);
  }

//------------------------------------------------------------------//
bool CIndicatorCache::Atr(const int shift, double &v)      { return(Value(m_handleAtr, shift, m_atrPeriod, false, v)); }
bool CIndicatorCache::Rsi(const int shift, double &v)      { return(Value(m_handleRsi, shift, m_rsiPeriod, false, v)); }
bool CIndicatorCache::EmaFast(const int shift, double &v)  { return(Value(m_handleEmaFast, shift, m_emaFastPeriod, true, v)); }
bool CIndicatorCache::EmaSlow(const int shift, double &v)  { return(Value(m_handleEmaSlow, shift, m_emaSlowPeriod, true, v)); }
bool CIndicatorCache::EmaTrend(const int shift, double &v) { return(Value(m_handleEmaTrend, shift, m_emaTrendPeriod, true, v)); }

//------------------------------------------------------------------//
//| `count` values ending at the newest closed bar, ordered oldest     |
//| first, so out[count-1] is the newest closed value.                  |
//+------------------------------------------------------------------//
bool CIndicatorCache::AtrSeries(const int count, double &out[])
  {
   ArrayResize(out, 0);
   if(m_handleAtr == INVALID_HANDLE || count <= 0) return(false);
   if(BarsCalculated(m_handleAtr) < count + 2) return(false);

   double buf[];
   ArraySetAsSeries(buf, true);
   const int copied = CopyBuffer(m_handleAtr, 0, 0, count + 2, buf);
   if(copied < count + 2) return(false);

   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      //--- out[0] = oldest of the requested window
      const int idx = count - i;   // skip the forming bar at index 0
      const double v = buf[idx];
      if(!QmeIsFinite(v)) { ArrayResize(out, 0); return(false); }
      out[i] = v;
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CIndicatorCache::RsiSeries(const int count, double &out[])
  {
   ArrayResize(out, 0);
   if(m_handleRsi == INVALID_HANDLE || count <= 0) return(false);
   if(BarsCalculated(m_handleRsi) < count + 2) return(false);

   double buf[];
   ArraySetAsSeries(buf, true);
   const int copied = CopyBuffer(m_handleRsi, 0, 0, count + 2, buf);
   if(copied < count + 2) return(false);

   ArrayResize(out, count);
   for(int i = 0; i < count; i++)
     {
      const int idx = count - i;
      const double v = buf[idx];
      if(!QmeIsFinite(v)) { ArrayResize(out, 0); return(false); }
      out[i] = v;
     }
   return(true);
  }

#endif // __QME_DATA_INDICATORCACHE_MQH__
//+------------------------------------------------------------------+
