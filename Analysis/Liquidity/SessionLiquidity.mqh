//+------------------------------------------------------------------+
//|                            Analysis/Liquidity/SessionLiquidity    |
//|  High/low of the CURRENT trading session, computed from server time  |
//|  converted to GMT.                                                 |
//|                                                                   |
//|  Note: the session start is derived arithmetically from the session  |
//|  definition in CMarketClock. If the broker has no bars inside the    |
//|  window (holiday), `valid` is false and the level is not used.       |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_SESSIONLIQUIDITY_MQH__
#define __QME_ANALYSIS_SESSIONLIQUIDITY_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "../../Data/MarketClock.mqh"

struct SSessionLevels
  {
   double            high;
   double            low;
   datetime          sessionStart;
   ENUM_QME_SESSION  session;
   int               barsUsed;
   bool              valid;
  };

class CSessionLiquidity
  {
public:
   static SSessionLevels Evaluate(CBarSeries &series, const ENUM_QME_SESSION session,
                                  const datetime gmtNow, const long serverGmtOffsetSec);
  private:
   static int        SessionStartGmtHour(const ENUM_QME_SESSION s);
  };

//------------------------------------------------------------------//
int CSessionLiquidity::SessionStartGmtHour(const ENUM_QME_SESSION s)
  {
   switch(s)
     {
      case QME_SESSION_ASIA:    return(0);
      case QME_SESSION_LONDON:  return(7);
      case QME_SESSION_OVERLAP: return(12);
      case QME_SESSION_NEWYORK: return(16);
      case QME_SESSION_OFFHOURS:return(21);
     }
   return(0);
  }

//------------------------------------------------------------------//
SSessionLevels CSessionLiquidity::Evaluate(CBarSeries &series, const ENUM_QME_SESSION session,
                                           const datetime gmtNow, const long serverGmtOffsetSec)
  {
   SSessionLevels r;
   r.high = 0.0;
   r.low = 0.0;
   r.sessionStart = 0;
   r.session = session;
   r.barsUsed = 0;
   r.valid = false;

   if(!series.IsValid() || gmtNow <= 0) return(r);

   //--- session start in GMT, then converted to server time
   MqlDateTime gmt;
   TimeToStruct(gmtNow, gmt);
   gmt.hour = SessionStartGmtHour(session);
   gmt.min = 0;
   gmt.sec = 0;
   const datetime sessionStartGmt = StructToTime(gmt);
   const datetime sessionStartServer = (datetime)((long)sessionStartGmt + serverGmtOffsetSec);
   r.sessionStart = sessionStartServer;

   double hi = -DBL_MAX;
   double lo = DBL_MAX;
   for(int i = 0; i < series.Count(); i++)
     {
      const datetime t = series.TimeAt(i);
      if(t < sessionStartServer) break;   // bars are newest-first
      const double h = series.High(i);
      const double l = series.Low(i);
      if(h <= 0.0 || l <= 0.0) continue;
      if(h > hi) hi = h;
      if(l < lo) lo = l;
      r.barsUsed++;
     }

   if(r.barsUsed < 1 || hi == -DBL_MAX || lo == DBL_MAX)
      return(r);

   r.high = hi;
   r.low = lo;
   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_SESSIONLIQUIDITY_MQH__
//+------------------------------------------------------------------+
