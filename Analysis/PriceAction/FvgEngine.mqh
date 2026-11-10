//+------------------------------------------------------------------+
//|                                     Analysis/PriceAction/FvgEngine|
//|  Fair Value Gap (3-bar imbalance) detection with fill tracking.      |
//|                                                                   |
//|  DEFINITION (shift indexing, 0 = newest closed bar):                 |
//|   bullish FVG at shifts (i+2, i+1, i):                              |
//|     low[i]  > high[i+2]     -> gap between high[i+2] and low[i]     |
//|   bearish FVG:                                                      |
//|     high[i] < low[i+2]      -> gap between high[i] and low[i+2]     |
//|  Minimum gap size is expressed in ATR units so it adapts per asset.  |
//|                                                                   |
//|  A gap is "filled" progressively: fillRatio is how much of the gap    |
//|  price has already traded back through, measured on closed bars.      |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_FVGENGINE_MQH__
#define __QME_ANALYSIS_FVGENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

class CFvgEngine
  {
public:
   //--- fills out[] newest-first; returns count
   static int        Detect(CBarSeries &series, const double atr, const double minSizeAtr,
                            const int scanBars, const int maxOut, SFvgRecord &out[]);

   //--- nearest unfilled gap in a direction relative to price
   static bool       NearestUnfilled(const SFvgRecord &gaps[], const int count,
                                     const double price, const bool above, SFvgRecord &out);
  };

//------------------------------------------------------------------//
int CFvgEngine::Detect(CBarSeries &series, const double atr, const double minSizeAtr,
                       const int scanBars, const int maxOut, SFvgRecord &out[])
  {
   ArrayResize(out, 0);
   if(!series.IsValid() || maxOut <= 0) return(0);

   const double minSize = MathMax(atr * minSizeAtr, QME_PRICE_EPS);
   const int limit = MathMin(scanBars, series.Count() - 3);
   int found = 0;

   for(int i = 0; i < limit && found < maxOut; i++)
     {
      const double hi_i = series.High(i);
      const double lo_i = series.Low(i);
      const double hi_2 = series.High(i + 2);
      const double lo_2 = series.Low(i + 2);
      if(hi_i <= 0.0 || lo_i <= 0.0 || hi_2 <= 0.0 || lo_2 <= 0.0) continue;

      double upper = 0.0, lower = 0.0;
      ENUM_QME_SIDE side = QME_SIDE_NONE;

      if(lo_i > hi_2 + minSize)
        {
         //--- bullish imbalance
         side = QME_SIDE_BUY;
         upper = lo_i;
         lower = hi_2;
        }
      else if(hi_i < lo_2 - minSize)
        {
         //--- bearish imbalance
         side = QME_SIDE_SELL;
         upper = lo_2;
         lower = hi_i;
        }
      else
         continue;

      const double size = upper - lower;
      if(size <= QME_EPSILON) continue;

      //--- fill tracking over the bars NEWER than the gap (shifts 0..i-1):
      //--- how far price has traded back into the imbalance, on closed bars.
      double minLowNewer = upper;
      double maxHighNewer = lower;
      for(int k = i - 1; k >= 0; k--)
        {
         const double h = series.High(k);
         const double l = series.Low(k);
         if(h <= 0.0 || l <= 0.0) continue;
         if(l < minLowNewer)  minLowNewer = l;
         if(h > maxHighNewer) maxHighNewer = h;
        }

      double fillRatio;
      if(side == QME_SIDE_BUY)
         fillRatio = QmeClamp((upper - minLowNewer) / size, 0.0, 1.0);
      else
         fillRatio = QmeClamp((maxHighNewer - lower) / size, 0.0, 1.0);

      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n].time = series.TimeAt(i + 1);
      out[n].side = side;
      out[n].upper = upper;
      out[n].lower = lower;
      out[n].fillRatio = fillRatio;
      out[n].filled = (fillRatio >= 0.95);
      found++;
     }
   return(found);
  }

//------------------------------------------------------------------//
bool CFvgEngine::NearestUnfilled(const SFvgRecord &gaps[], const int count,
                                 const double price, const bool above, SFvgRecord &out)
  {
   bool found = false;
   double best = 0.0;
   for(int i = 0; i < count; i++)
     {
      if(gaps[i].filled) continue;
      const double mid = 0.5 * (gaps[i].upper + gaps[i].lower);
      if(above)
        {
         if(mid <= price + QME_PRICE_EPS) continue;
         if(!found || mid < best) { best = mid; out = gaps[i]; found = true; }
        }
      else
        {
         if(mid >= price - QME_PRICE_EPS) continue;
         if(!found || mid > best) { best = mid; out = gaps[i]; found = true; }
        }
     }
   return(found);
  }

#endif // __QME_ANALYSIS_FVGENGINE_MQH__
//+------------------------------------------------------------------+
