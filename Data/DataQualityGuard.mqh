//+------------------------------------------------------------------+
//|                                          Data/DataQualityGuard    |
//|  QuantumMarketEngine — decides whether the current data is fit to   |
//|  base a decision on.                                               |
//|                                                                   |
//|  A failing quality check does NOT delete data; it marks the context  |
//|  unusable for this cycle and records the exact reason so the funnel  |
//|  can report it.                                                     |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_DATAQUALITY_MQH__
#define __QME_DATA_DATAQUALITY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "TimeframeContext.mqh"

//--- quality problem flags (stored in SDataQuality::flags)
enum ENUM_QME_DQ_FLAG
  {
   QME_DQ_FLAG_STALE        = 1,
   QME_DQ_FLAG_MISSING      = 2,
   QME_DQ_FLAG_INCONSISTENT = 4,
   QME_DQ_FLAG_SPREAD       = 8,
   QME_DQ_FLAG_SHORT        = 16,
   QME_DQ_FLAG_CLOSED       = 32
  };

class CDataQualityGuard
  {
public:
   //--- evaluate one context; returns out.ok
   static bool       Evaluate(CTimeframeContext &ctx, const double curSpreadPoints,
                              SDataQuality &out);
   static string     Describe(const SDataQuality &q);
  };

//------------------------------------------------------------------//
bool CDataQualityGuard::Evaluate(CTimeframeContext &ctx, const double curSpreadPoints,
                                 SDataQuality &out)
  {
   QmeDataQualityClear(out);
   out.curSpread = curSpreadPoints;

   CBarSeries *series = ctx.Series();
   if(series == NULL)
     {
      out.note = "no series";
      return(false);
     }

   out.closedBars = series.Count();
   out.avgSpread = (curSpreadPoints > 0.0 && ctx.AvgSpread() > 0.0) ?
                   series.AverageSpread(20) : 0.0;

   if(out.closedBars < QME_MIN_BARS_REQUIRED)
     {
      out.flags |= QME_DQ_FLAG_SHORT;
      out.note = "only " + IntegerToString(out.closedBars) + " closed bars";
     }

   if(!series.OrderValid())
     {
      out.inconsistentBars = true;
      out.flags |= QME_DQ_FLAG_INCONSISTENT;
      out.note = "bar order invalid";
     }

   //--- staleness: how old is the newest closed bar relative to the timeframe
   const datetime server = TimeTradeServer();
   const datetime lastBar = series.LastClosedBarTime();
   const int periodInt = PeriodSeconds(ctx.Timeframe());
   // CopyRates timestamps bars by OPEN time. Freshness must be measured from
   // the expected close boundary, not from that opening timestamp.
   const datetime closeBoundary = (lastBar > 0 && periodInt > 0 ? lastBar + periodInt : 0);
   out.barAgeSeconds = (closeBoundary > 0 && server > closeBoundary) ?
                       (double)(server - closeBoundary) : 0.0;
   const double periodSec = (double)periodInt;
   if(lastBar <= 0 || server <= 0 || lastBar > server || periodSec <= 0.0)
     {
      out.stale = true;
      out.flags |= QME_DQ_FLAG_CLOSED;
      out.note = "invalid server clock or closed bar time";
     }
   else if(periodSec > 0.0 && out.barAgeSeconds > periodSec * 3.0)
     {
      //--- 3 periods without a new closed bar: market closed or feed frozen
      out.stale = true;
      out.flags |= QME_DQ_FLAG_STALE;
      out.note = "newest bar is " + QmeFmt(out.barAgeSeconds / 60.0, 1) + " min old";
     }

   //--- gaps: informational until they dominate the window
   if(series.Gaps() > 0)
     {
      out.missingBars = (series.WorstGap() > out.closedBars / 4);
      if(out.missingBars)
        {
         out.flags |= QME_DQ_FLAG_MISSING;
         int worstAt = -1;
         long worstSeconds = 0;
         for(int gi=1; gi<series.Count(); gi++)
           {
            const long delta=(long)series.TimeAt(gi-1)-(long)series.TimeAt(gi);
            if(delta>worstSeconds) { worstSeconds=delta; worstAt=gi; }
           }
         const datetime newer=(worstAt>0 ? series.TimeAt(worstAt-1) : 0);
         const datetime older=(worstAt>0 ? series.TimeAt(worstAt) : 0);
         out.note = "missing-session-bars reason=unclassified symbol=" + series.Symbol() +
                    " tf=" + QmeTimeframeName(ctx.Timeframe()) +
                    " newer=" + TimeToString(newer,TIME_DATE|TIME_MINUTES) +
                    " older=" + TimeToString(older,TIME_DATE|TIME_MINUTES) +
                    " elapsedSec=" + IntegerToString(worstSeconds) +
                    " expectedSession=unknown (broker session schedule not evaluated)";
         QmeLogMsg(QME_LOG_WARN,"DataQuality",out.note);
        }
     }

   //--- spread sanity vs the series' own recent median-ish average
   if(out.avgSpread > 0.0 && curSpreadPoints > 0.0)
     {
      const double ratio = curSpreadPoints / out.avgSpread;
      out.spreadAbnormal = (ratio > 3.0);
      if(out.spreadAbnormal)
        {
         out.flags |= QME_DQ_FLAG_SPREAD;
         out.note = "spread " + QmeFmt(curSpreadPoints, 1) + " is " +
                    QmeFmt(ratio, 1) + "x average";
        }
     }

   out.ok = ((out.flags & (QME_DQ_FLAG_STALE | QME_DQ_FLAG_MISSING | QME_DQ_FLAG_INCONSISTENT | QME_DQ_FLAG_SHORT | QME_DQ_FLAG_CLOSED)) == 0);
   return(out.ok);
  }

//------------------------------------------------------------------//
string CDataQualityGuard::Describe(const SDataQuality &q)
  {
   return(string("ok=") + QmeBoolStr(q.ok) +
          " bars=" + IntegerToString(q.closedBars) +
          " age=" + QmeFmt(q.barAgeSeconds / 60.0, 1) + "m" +
          " spread=" + QmeFmt(q.curSpread, 1) + "/" + QmeFmt(q.avgSpread, 1) +
          " flags=" + IntegerToString(q.flags) +
          (StringLen(q.note) > 0 ? " (" + q.note + ")" : ""));
  }

#endif // __QME_DATA_DATAQUALITY_MQH__
//+------------------------------------------------------------------+
