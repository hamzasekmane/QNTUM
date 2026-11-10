//+------------------------------------------------------------------+
//|                          Analysis/PriceAction/OrderBlockEngine    |
//|  Order blocks: the last opposite candle before a displacement leg.    |
//|                                                                   |
//|  DEFINITION:                                                       |
//|   Search displacement bars (see CDisplacementEngine) scanning from    |
//|   newest. For a bullish displacement at shift i, walk back up to      |
//|   `lookback` bars and take the FIRST bearish candle found; its        |
//|   [low, high] is the bullish order block. Mirror for bearish.         |
//|                                                                   |
//|   A block is "mitigated" when a later closed bar trades back into it.  |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_ORDERBLOCK_MQH__
#define __QME_ANALYSIS_ORDERBLOCK_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "DisplacementEngine.mqh"

class COrderBlockEngine
  {
public:
   static int        Detect(CBarSeries &series, const double atr, const double avgBody,
                            const double displacementMult, const int scanBars,
                            const int lookback, const int maxOut,
                            SOrderBlockRecord &out[]);

   //--- does this block still overlap a price (used for zone merging)?
   static bool       Contains(const SOrderBlockRecord &ob, const double price);
  };

//------------------------------------------------------------------//
int COrderBlockEngine::Detect(CBarSeries &series, const double atr, const double avgBody,
                              const double displacementMult, const int scanBars,
                              const int lookback, const int maxOut,
                              SOrderBlockRecord &out[])
  {
   ArrayResize(out, 0);
   if(!series.IsValid() || maxOut <= 0) return(0);

   const int limit = MathMin(scanBars, series.Count() - lookback - 1);
   int found = 0;

   for(int i = 0; i < limit && found < maxOut; i++)
     {
      ENUM_QME_SIDE side = QME_SIDE_NONE;
      if(!CDisplacementEngine::IsDisplacementBar(series, i, atr, avgBody,
                                                 displacementMult, side))
         continue;

      //--- walk back for the last opposite candle
      for(int k = 1; k <= lookback; k++)
        {
         SCandle c;
         if(!series.Get(i + k, c)) break;
         const bool opposite = (side == QME_SIDE_BUY) ? QmeCandleIsBear(c) : QmeCandleIsBull(c);
         if(!opposite) continue;

         const double upper = c.high;
         const double lower = c.low;
         if(upper <= lower) break;

         //--- mitigation: any newer closed bar traded back inside the block
         bool mitigated = false;
         for(int m = i - 1; m >= 0; m--)
           {
            const double h = series.High(m);
            const double l = series.Low(m);
            if(l <= upper && h >= lower)
              {
               mitigated = true;
               break;
              }
           }

         const int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n].time = c.time;
         out[n].side = side;
         out[n].upper = upper;
         out[n].lower = lower;
         out[n].mitigated = mitigated;
         //--- strength: displacement size relative to average body
         SCandle disp;
         double dispBody = 0.0;
         if(series.Get(i, disp)) dispBody = QmeCandleBody(disp);
         out[n].displacement = QmeClamp(dispBody / MathMax(avgBody, QME_EPSILON) / 3.0, 0.0, 1.0);
         found++;
         break;
        }
     }
   return(found);
  }

//------------------------------------------------------------------//
bool COrderBlockEngine::Contains(const SOrderBlockRecord &ob, const double price)
  {
   if(ob.upper <= ob.lower) return(false);
   return(price >= ob.lower - QME_PRICE_EPS && price <= ob.upper + QME_PRICE_EPS);
  }

#endif // __QME_ANALYSIS_ORDERBLOCK_MQH__
//+------------------------------------------------------------------+
