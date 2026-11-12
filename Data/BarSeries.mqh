//+------------------------------------------------------------------+
//|                                                  Data/BarSeries   |
//|  QuantumMarketEngine — closed-bar series per symbol/timeframe.     |
//|                                                                   |
//|  LOOK-AHEAD PROTECTION:                                          |
//|   * CopyRates is always requested with start_pos = 1, so the bar    |
//|     currently being formed can never enter the series;             |
//|   * index 0 of the series is therefore the newest CLOSED bar;        |
//|   * a bar is additionally rejected unless its open time + period     |
//|     is <= server time.                                             |
//|                                                                   |
//|  OWNERSHIP: one CBarSeries per CTimeframeContext (composition).     |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_BARSERIES_MQH__
#define __QME_DATA_BARSERIES_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Core/HistoryGuard.mqh"
#include "../Core/Logger.mqh"
#include "../Core/Algorithms.mqh"

class CBarSeries
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   SCandle           m_bars[];
   int               m_count;
   int               m_requested;
   datetime          m_lastClosedBarTime;
   datetime          m_lastRefresh;
   bool              m_valid;
   bool              m_orderValid;
   int               m_gaps;
   int               m_worstGap;
   string            m_error;

   bool              Convert(const MqlRates &rates[], const int copied);

public:
   void              Reset(void);
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf, const int bars);
   bool              Refresh(void);

   string            Symbol(void) { return(m_symbol); }
   ENUM_TIMEFRAMES   Timeframe(void) { return(m_tf); }
   int               Count(void) { return(m_count); }
   bool              IsValid(void) { return(m_valid); }
   bool              OrderValid(void) { return(m_orderValid); }
   int               Gaps(void) { return(m_gaps); }
   int               WorstGap(void) { return(m_worstGap); }
   string            LastError(void) { return(m_error); }
   datetime          LastClosedBarTime(void) { return(m_lastClosedBarTime); }
   datetime          LastRefreshTime(void) { return(m_lastRefresh); }

   //--- shift 0 = newest closed bar
   bool              Get(const int shift, SCandle &out);
   //--- exact closed-bar time lookup using descending-order binary search
   bool              FindShiftByTime(const datetime time, int &shift);
   bool              AtTime(const datetime time, SCandle &out);
   double            Open(const int shift)  { SCandle c; return(Get(shift, c) ? c.open  : 0.0); }
   double            High(const int shift)  { SCandle c; return(Get(shift, c) ? c.high  : 0.0); }
   double            Low(const int shift)   { SCandle c; return(Get(shift, c) ? c.low   : 0.0); }
   double            Close(const int shift) { SCandle c; return(Get(shift, c) ? c.close : 0.0); }
   long              TickVolume(const int shift){ SCandle c; return(Get(shift, c) ? c.tickVolume : 0); }
   datetime          TimeAt(const int shift){ SCandle c; return(Get(shift, c) ? c.time : 0); }

   //--- extremes over [shift, shift+count)
   double            Highest(const int shift, const int count);
   double            Lowest(const int shift, const int count);
   double            AverageRange(const int count);
   double            AverageVolume(const int count);
   double            AverageSpread(const int count);
   //--- average absolute close-to-close move (displacement reference)
   double            AverageBody(const int count);
  };

//------------------------------------------------------------------//
void CBarSeries::Reset(void)
  {
   m_symbol = "";
   m_tf = PERIOD_CURRENT;
   m_count = 0;
   m_requested = 0;
   m_lastClosedBarTime = 0;
   m_lastRefresh = 0;
   m_valid = false;
   m_orderValid = false;
   m_gaps = 0;
   m_worstGap = 0;
   m_error = "";
   ArrayResize(m_bars, 0);
  }

//------------------------------------------------------------------//
bool CBarSeries::Init(const string symbol, const ENUM_TIMEFRAMES tf, const int bars)
  {
   Reset();
   m_symbol = symbol;
   m_tf = tf;
   m_requested = bars;
   if(bars < QME_MIN_BARS_REQUIRED)
     {
      m_error = "requested bars below QME_MIN_BARS_REQUIRED";
      return(false);
     }
   if(!SymbolSelect(symbol, true))
     {
      m_error = "SymbolSelect failed for " + symbol;
      QmeLogMsg(QME_LOG_ERROR, "BarSeries", m_error);
      return(false);
     }
   ArrayResize(m_bars, bars);
   return(Refresh());
  }

//------------------------------------------------------------------//
bool CBarSeries::Refresh(void)
  {
   m_valid = false;
   m_error = "";
   m_lastRefresh = TimeCurrent();

   if(StringLen(m_symbol) == 0 || m_requested <= 0)
     {
      m_error = "series not initialised";
      return(false);
     }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   //--- start from position 1: position 0 is the bar still being formed
   const int copied = CopyRates(m_symbol, m_tf, 1, m_requested, rates);
   if(copied <= 0)
     {
      m_error = "CopyRates returned " + IntegerToString(copied) + " (" + QmeLastErrorText() + ")";
      return(false);
     }
   if(copied < m_requested)
     {
      //--- not fatal, but the caller must know history is short
      if(copied < QME_MIN_BARS_REQUIRED)
        {
         m_error = "insufficient history: " + IntegerToString(copied) + " < " +
                   IntegerToString(QME_MIN_BARS_REQUIRED);
         return(false);
        }
     }
   return(Convert(rates, copied));
  }

//------------------------------------------------------------------//
bool CBarSeries::Convert(const MqlRates &rates[], const int copied)
  {
   if(copied <= 0) return(false);
   if(ArraySize(m_bars) < copied) ArrayResize(m_bars, copied);

   const datetime server = TimeTradeServer();
   m_count = 0;

   for(int i = 0; i < copied; i++)
     {
      SCandle c;
      QmeCandleClear(c);
      c.time = rates[i].time;
      c.open = rates[i].open;
      c.high = rates[i].high;
      c.low = rates[i].low;
      c.close = rates[i].close;
      c.tickVolume = rates[i].tick_volume;
      c.realVolume = rates[i].real_volume;
      c.spread = rates[i].spread;

      //--- reject impossible bars
      if(!QmeOhlcPlausible(c.open, c.high, c.low, c.close))
         continue;

      //--- reject the bar that is still forming (defence in depth: CopyRates
      //--- already started at position 1)
      if(!QmeBarIsClosed(c.time, m_tf, server))
         continue;

      c.valid = true;
      m_bars[m_count] = c;
      m_count++;
     }

   if(m_count < QME_MIN_BARS_REQUIRED)
     {
      m_valid = false;
      m_error = "usable closed bars after validation: " + IntegerToString(m_count);
      return(false);
     }

   //--- ordering / monotonicity
   datetime times[];
   ArrayResize(times, m_count);
   for(int i = 0; i < m_count; i++) times[i] = m_bars[i].time;
   m_orderValid = QmeSeriesOrderValid(times, m_count);
   m_gaps = QmeCountGaps(times, m_count, m_tf, m_worstGap);

   m_lastClosedBarTime = m_bars[0].time;
   m_valid = m_orderValid;
   if(!m_orderValid)
      m_error = "bar times are not strictly descending";
   return(m_valid);
  }

//------------------------------------------------------------------//
bool CBarSeries::Get(const int shift, SCandle &out)
  {
   QmeCandleClear(out);
   if(shift < 0 || shift >= m_count) return(false);
   out = m_bars[shift];
   return(out.valid);
  }

//------------------------------------------------------------------//
bool CBarSeries::FindShiftByTime(const datetime time, int &shift)
  {
   shift = -1;
   if(!m_valid || !m_orderValid) return(false);
   return(CQmeAlgorithms::FindBarTimeDescending(m_bars, m_count, time, shift));
  }

bool CBarSeries::AtTime(const datetime time, SCandle &out)
  {
   QmeCandleClear(out);
   int shift = -1;
   if(!FindShiftByTime(time, shift)) return(false);
   return(Get(shift, out));
  }

//------------------------------------------------------------------//
double CBarSeries::Highest(const int shift, const int count)
  {
   double h = -DBL_MAX;
   const int end = MathMin(m_count, shift + count);
   for(int i = shift; i < end; i++)
      if(m_bars[i].high > h) h = m_bars[i].high;
   return(h == -DBL_MAX ? 0.0 : h);
  }

//------------------------------------------------------------------//
double CBarSeries::Lowest(const int shift, const int count)
  {
   double l = DBL_MAX;
   const int end = MathMin(m_count, shift + count);
   for(int i = shift; i < end; i++)
      if(m_bars[i].low < l) l = m_bars[i].low;
   return(l == DBL_MAX ? 0.0 : l);
  }

//------------------------------------------------------------------//
double CBarSeries::AverageRange(const int count)
  {
   const int n = MathMin(m_count, count);
   if(n <= 0) return(0.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += QmeCandleRange(m_bars[i]);
   return(sum / n);
  }

//------------------------------------------------------------------//
double CBarSeries::AverageVolume(const int count)
  {
   const int n = MathMin(m_count, count);
   if(n <= 0) return(0.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += (double)m_bars[i].tickVolume;
   return(sum / n);
  }

//------------------------------------------------------------------//
double CBarSeries::AverageSpread(const int count)
  {
   const int n = MathMin(m_count, count);
   if(n <= 0) return(0.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += (double)m_bars[i].spread;
   return(sum / n);
  }

//------------------------------------------------------------------//
double CBarSeries::AverageBody(const int count)
  {
   const int n = MathMin(m_count, count);
   if(n <= 0) return(0.0);
   double sum = 0.0;
   for(int i = 0; i < n; i++) sum += QmeCandleBody(m_bars[i]);
   return(sum / n);
  }

#endif // __QME_DATA_BARSERIES_MQH__
//+------------------------------------------------------------------+
