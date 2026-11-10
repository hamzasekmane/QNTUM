//+------------------------------------------------------------------+
//|                                          Data/TimeframeContext    |
//|  QuantumMarketEngine — everything known about one symbol/timeframe.|
//|                                                                   |
//|  Composition: CBarSeries (closed bars) + CIndicatorCache           |
//|               + cached derived statistics + SDataQuality.           |
//|                                                                   |
//|  Refreshing a context is the ONLY way bars/indicator values change. |
//|  Analysis engines read the cached scalars, so a full scan never     |
//|  re-copies the same buffer twice.                                   |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_TIMEFRAMECONTEXT_MQH__
#define __QME_DATA_TIMEFRAMECONTEXT_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "BarSeries.mqh"
#include "IndicatorCache.mqh"

class CTimeframeContext
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   CBarSeries        m_series;
   CIndicatorCache   m_indicators;
   bool              m_ready;
   bool              m_dataValid;
   string            m_error;

   //--- cached derived values (recomputed on Refresh)
   double            m_atr;
   double            m_atrAvg;
   double            m_atrRatio;
   double            m_atrPct;
   double            m_rsi;
   double            m_emaFast;
   double            m_emaSlow;
   double            m_emaTrend;
   double            m_avgRange20;
   double            m_avgBody20;
   double            m_avgVolume20;
   double            m_avgSpread20;
   bool              m_indicatorReady;
   SDataQuality      m_quality;

public:
                     CTimeframeContext(void);
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf, const int bars);
   void              Shutdown(void);
   bool              Refresh(void);

   //--- identity / readiness
   string            Symbol(void) { return(m_symbol); }
   ENUM_TIMEFRAMES   Timeframe(void) { return(m_tf); }
   bool              Ready(void) { return(m_ready); }
   bool              DataValid(void) { return(m_dataValid); }
   bool              IndicatorReady(void) { return(m_indicatorReady); }
   void              SetQuality(const SDataQuality &q) { m_quality = q; }
   SDataQuality      Quality(void) { return(m_quality); }
   string            LastError(void) { return(m_error); }
   CBarSeries*       Series(void) { return(&m_series); }
   CIndicatorCache*  Indicators(void) { return(&m_indicators); }

   //--- cached statistics
   double            Atr(void) { return(m_atr); }
   double            AtrAvg(void) { return(m_atrAvg); }
   double            AtrRatio(void) { return(m_atrRatio); }
   double            AtrPct(void) { return(m_atrPct); }
   double            Rsi(void) { return(m_rsi); }
   double            EmaFast(void) { return(m_emaFast); }
   double            EmaSlow(void) { return(m_emaSlow); }
   double            EmaTrend(void) { return(m_emaTrend); }
   double            AvgRange(const int n) { return(m_avgRange20); }
   double            AvgBody(void) { return(m_avgBody20); }
   double            AvgVolume(void) { return(m_avgVolume20); }
   double            AvgSpread(void) { return(m_avgSpread20); }

   //--- convenience: EMA stack direction, 0 when not ready
   ENUM_QME_SIDE     EmaStackDirection(void);
   double            Close(const int shift) { return(m_series.Close(shift)); }
   datetime          LastBarTime(void) { return(m_series.LastClosedBarTime()); }
  };

//------------------------------------------------------------------//
CTimeframeContext::CTimeframeContext(void)
  {
   m_symbol = "";
   m_tf = PERIOD_CURRENT;
   m_ready = false;
   m_dataValid = false;
   m_error = "";
   m_atr = 0.0; m_atrAvg = 0.0; m_atrRatio = 0.0; m_atrPct = 0.0;
   m_rsi = 0.0; m_emaFast = 0.0; m_emaSlow = 0.0; m_emaTrend = 0.0;
   m_avgRange20 = 0.0; m_avgBody20 = 0.0; m_avgVolume20 = 0.0; m_avgSpread20 = 0.0;
   m_indicatorReady = false;
   QmeDataQualityClear(m_quality);
  }

//------------------------------------------------------------------//
bool CTimeframeContext::Init(const string symbol, const ENUM_TIMEFRAMES tf, const int bars)
  {
   m_symbol = symbol;
   m_tf = tf;
   m_ready = false;
   m_error = "";

   if(!m_series.Init(symbol, tf, bars))
     {
      m_error = "series: " + m_series.LastError();
      return(false);
     }
   if(!m_indicators.Init(symbol, tf, 14, 14, 20, 50, 200))
     {
      m_error = "indicators: " + m_indicators.LastError();
      return(false);
     }
   m_ready = true;
   return(Refresh());
  }

//------------------------------------------------------------------//
void CTimeframeContext::Shutdown(void)
  {
   m_indicators.Release();
   m_ready = false;
   m_dataValid = false;
  }

//------------------------------------------------------------------//
bool CTimeframeContext::Refresh(void)
  {
   m_dataValid = false;
   m_error = "";

   if(!m_series.Refresh())
     {
      m_error = "series refresh: " + m_series.LastError();
      return(false);
     }
   m_dataValid = m_series.IsValid();

   m_avgRange20  = m_series.AverageRange(20);
   m_avgBody20   = m_series.AverageBody(20);
   m_avgVolume20 = m_series.AverageVolume(20);
   m_avgSpread20 = m_series.AverageSpread(20);

   if(!m_indicators.Ready())
     {
      m_indicatorReady = false;
      //--- indicators may need a few seconds after the first request
      m_error = "indicators not ready";
      return(m_dataValid);
     }
   m_indicatorReady = true;

   double v = 0.0;
   if(!m_indicators.Atr(0, v)) { m_indicatorReady = false; m_error = "ATR unavailable"; return(m_dataValid); }
   m_atr = v;

   if(!m_indicators.Rsi(0, v)) { m_indicatorReady = false; m_error = "RSI unavailable"; return(m_dataValid); }
   m_rsi = v;

   if(!m_indicators.EmaFast(0, v)) { m_indicatorReady = false; m_error = "EMA fast unavailable"; return(m_dataValid); }
   m_emaFast = v;
   if(!m_indicators.EmaSlow(0, v)) { m_indicatorReady = false; m_error = "EMA slow unavailable"; return(m_dataValid); }
   m_emaSlow = v;
   if(!m_indicators.EmaTrend(0, v)) { m_indicatorReady = false; m_error = "EMA trend unavailable"; return(m_dataValid); }
   m_emaTrend = v;

   //--- average ATR of the last 20 closed bars (volatility baseline)
   double atrBuf[];
   if(m_indicators.AtrSeries(20, atrBuf))
     {
      double sum = 0.0;
      for(int i = 0; i < ArraySize(atrBuf); i++) sum += atrBuf[i];
      m_atrAvg = (ArraySize(atrBuf) > 0) ? sum / ArraySize(atrBuf) : 0.0;
     }
   else
      m_atrAvg = m_atr;

   m_atrRatio = QmeSafeDiv(m_atr, m_atrAvg, 1.0);
   const double close = m_series.Close(0);
   m_atrPct = (close > 0.0) ? 100.0 * m_atr / close : 0.0;

   return(m_dataValid && m_indicatorReady);
  }

//------------------------------------------------------------------//
ENUM_QME_SIDE CTimeframeContext::EmaStackDirection(void)
  {
   if(!m_indicatorReady) return(QME_SIDE_NONE);
   if(m_emaFast <= 0.0 || m_emaSlow <= 0.0 || m_emaTrend <= 0.0) return(QME_SIDE_NONE);
   if(m_emaFast > m_emaSlow && m_emaSlow > m_emaTrend) return(QME_SIDE_BUY);
   if(m_emaFast < m_emaSlow && m_emaSlow < m_emaTrend) return(QME_SIDE_SELL);
   return(QME_SIDE_NONE);
  }

#endif // __QME_DATA_TIMEFRAMECONTEXT_MQH__
//+------------------------------------------------------------------+
