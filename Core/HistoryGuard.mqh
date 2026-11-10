//+------------------------------------------------------------------+
//|                                                 HistoryGuard.mqh |
//|  QuantumMarketEngine — historical data integrity.                 |
//|                                                                   |
//|  PURPOSE: guarantee that no decision uses a bar from the future,   |
//|  a bar that has not closed, a duplicated timestamp, or a series    |
//|  whose ordering is inconsistent with another timeframe.            |
//|  OWNERSHIP: stateless utility + small per-series state.            |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_HISTORYGUARD_MQH__
#define __QME_CORE_HISTORYGUARD_MQH__

#include "Constants.mqh"
#include "Types.mqh"
#include "Utils.mqh"

//--- a bar can only be consumed when it is strictly older than the last
//--- server time we have seen (i.e. it is closed).
bool QmeBarIsClosed(const datetime barTime, const ENUM_TIMEFRAMES tf, const datetime serverTime)
  {
   if(barTime <= 0) return(false);
   return(barTime + PeriodSeconds(tf) <= serverTime);
  }

//--- verify strict descending order (newest first) and no duplicated time
bool QmeSeriesOrderValid(const datetime &times[], const int count)
  {
   if(count <= 1) return(true);
   for(int i = 1; i < count; i++)
     {
      if(times[i] <= 0) return(false);
      if(times[i] >= times[i - 1]) return(false);   // must be strictly decreasing
     }
   return(true);
  }

//--- detect a suspicious gap inside the series (missing bars)
//--- returns the number of gaps found; fills worst gap in `worstGapBars`
int QmeCountGaps(const datetime &times[], const int count,
                 const ENUM_TIMEFRAMES tf, int &worstGapBars)
  {
   worstGapBars = 0;
   if(count <= 1) return(0);
   const int step = PeriodSeconds(tf);
   if(step <= 0) return(0);
   int gaps = 0;
   for(int i = 1; i < count; i++)
     {
      const long delta = (long)times[i - 1] - (long)times[i];
      //--- weekend / session breaks are expected: only count gaps that are a
      //--- multiple of the period AND larger than 3 periods, and treat them as
      //--- informational, never as a hard error.
      if(delta > (long)step * 3)
        {
         const int missing = (int)(delta / step) - 1;
         gaps++;
         if(missing > worstGapBars) worstGapBars = missing;
        }
     }
   return(gaps);
  }

//--- cross-timeframe monotonicity: the newest closed bar of a lower timeframe
//--- must not be older than the newest closed bar of a higher timeframe minus
//--- one period of the higher timeframe (otherwise the data is inconsistent).
bool QmeCrossTimeframeConsistent(const datetime lastLower, const ENUM_TIMEFRAMES lowerTf,
                                 const datetime lastHigher, const ENUM_TIMEFRAMES higherTf)
  {
   if(lastLower <= 0 || lastHigher <= 0) return(false);
   if(PeriodSeconds(lowerTf) > PeriodSeconds(higherTf)) return(true); // nothing to compare
   //--- the lower timeframe must reach at least the start of the last higher bar
   return(lastLower + PeriodSeconds(lowerTf) >= lastHigher);
  }

//--- reject prices that cannot come from a real bar
bool QmeOhlcPlausible(const double o, const double h, const double l, const double c)
  {
   if(!QmeIsFinite(o) || !QmeIsFinite(h) || !QmeIsFinite(l) || !QmeIsFinite(c)) return(false);
   if(o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0) return(false);
   if(h < l) return(false);
   if(h < o - QME_PRICE_EPS || h < c - QME_PRICE_EPS) return(false);
   if(l > o + QME_PRICE_EPS || l > c + QME_PRICE_EPS) return(false);
   return(true);
  }

#endif // __QME_CORE_HISTORYGUARD_MQH__
//+------------------------------------------------------------------+
