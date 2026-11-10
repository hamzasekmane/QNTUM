//+------------------------------------------------------------------+
//|                          Analysis/PriceAction/DisplacementEngine  |
//|  Displacement = an impulsive, one-sided move that leaves imbalance.  |
//|                                                                   |
//|  DEFINITION:                                                       |
//|   a closed bar is a displacement bar when                          |
//|     body >= mult * average body(20)   AND                           |
//|     body >= 0.55 * bar range          AND                           |
//|     body >= 0.5 * ATR                                              |
//|  The engine reports the most recent one and its direction.           |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_DISPLACEMENT_MQH__
#define __QME_ANALYSIS_DISPLACEMENT_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

struct SDisplacementResult
  {
   bool              found;
   ENUM_QME_SIDE     side;
   int               barIndex;
   datetime          time;
   double            body;
   double            bodyAtr;      // body / ATR
   double            score;        // 0..1
   bool              valid;
  };

void QmeDisplacementClear(SDisplacementResult &d)
  {
   d.found = false;
   d.side = QME_SIDE_NONE;
   d.barIndex = -1;
   d.time = 0;
   d.body = 0.0;
   d.bodyAtr = 0.0;
   d.score = 0.0;
   d.valid = false;
  }

class CDisplacementEngine
  {
public:
   static SDisplacementResult Latest(CBarSeries &series, const double atr,
                                     const double avgBody, const int scanBars,
                                     const double mult = 1.5);

   //--- generic test used by FVG / order-block detection
   static bool       IsDisplacementBar(CBarSeries &series, const int shift,
                                       const double atr, const double avgBody,
                                       const double mult, ENUM_QME_SIDE &side);
  };

//------------------------------------------------------------------//
bool CDisplacementEngine::IsDisplacementBar(CBarSeries &series, const int shift,
                                            const double atr, const double avgBody,
                                            const double mult, ENUM_QME_SIDE &side)
  {
   side = QME_SIDE_NONE;
   SCandle c;
   if(!series.Get(shift, c)) return(false);

   const double body = QmeCandleBody(c);
   const double range = QmeCandleRange(c);
   if(range <= QME_EPSILON || body <= QME_EPSILON) return(false);
   if(atr <= QME_EPSILON || avgBody <= QME_EPSILON) return(false);

   if(body < mult * avgBody) return(false);
   if(body < 0.55 * range) return(false);
   if(body < 0.5 * atr) return(false);

   side = QmeCandleIsBull(c) ? QME_SIDE_BUY : QME_SIDE_SELL;
   return(true);
  }

//------------------------------------------------------------------//
SDisplacementResult CDisplacementEngine::Latest(CBarSeries &series, const double atr,
                                                const double avgBody, const int scanBars,
                                                const double mult)
  {
   SDisplacementResult r;
   QmeDisplacementClear(r);
   if(!series.IsValid()) return(r);

   const int limit = MathMin(scanBars, series.Count() - 1);
   for(int i = 0; i < limit; i++)
     {
      ENUM_QME_SIDE side = QME_SIDE_NONE;
      if(!IsDisplacementBar(series, i, atr, avgBody, mult, side)) continue;

      SCandle c;
      if(!series.Get(i, c)) continue;

      r.found = true;
      r.side = side;
      r.barIndex = i;
      r.time = c.time;
      r.body = QmeCandleBody(c);
      r.bodyAtr = r.body / MathMax(atr, QME_EPSILON);
      r.score = QmeClamp((r.body / MathMax(avgBody, QME_EPSILON) - 1.0) / 2.0, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   return(r);
  }

#endif // __QME_ANALYSIS_DISPLACEMENT_MQH__
//+------------------------------------------------------------------+
