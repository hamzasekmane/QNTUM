//+------------------------------------------------------------------+
//|                                Analysis/Structure/BreakoutEngine  |
//|  Range breakout detection with explicit confirmation and failure    |
//|  detection.                                                       |
//|                                                                   |
//|  DEFINITION:                                                      |
//|   box = highest high / lowest low of the `boxBars` bars BEFORE the   |
//|         most recent `confirmBars` bars.                            |
//|   confirmed breakout: a later closed bar closes outside the box by    |
//|         at least `bufferAtr * ATR`, after a bar that closed inside.   |
//|   failed breakout: a bar closed outside the box within the last        |
//|         `confirmBars` bars, but the newest closed bar is back inside. |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_BREAKOUTENGINE_MQH__
#define __QME_ANALYSIS_BREAKOUTENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "BosEngine.mqh"

class CBreakoutEngine
  {
public:
   static SStructureEvent Detect(CBarSeries &series, const double atr,
                                 const int boxBars, const int confirmBars,
                                 const double bufferAtr);
  };

//------------------------------------------------------------------//
SStructureEvent CBreakoutEngine::Detect(CBarSeries &series, const double atr,
                                        const int boxBars, const int confirmBars,
                                        const double bufferAtr)
  {
   SStructureEvent r;
   QmeStructureEventClear(r);
   if(!series.IsValid()) return(r);
   if(boxBars < 5 || confirmBars < 1) return(r);
   if(series.Count() < boxBars + confirmBars + 2) return(r);

   const double buffer = MathMax(atr, QME_EPSILON) * bufferAtr;

   //--- box from bars [confirmBars, confirmBars+boxBars)
   const double boxHigh = series.Highest(confirmBars, boxBars);
   const double boxLow  = series.Lowest(confirmBars, boxBars);
   if(boxHigh <= 0.0 || boxLow <= 0.0 || boxHigh <= boxLow) return(r);

   //--- scan the newest confirmBars closed bars for a confirmed break
   for(int i = 0; i < confirmBars; i++)
     {
      const double close = series.Close(i);
      if(close <= 0.0) continue;
      const double prevClose = series.Close(i + 1);

      if(close > boxHigh + buffer && prevClose <= boxHigh + QME_PRICE_EPS)
        {
         r.event = QME_STRUCT_BREAKOUT_CONFIRMED;
         r.level = boxHigh;
         r.time = series.TimeAt(i);
         r.barIndex = i;
         r.strength = QmeClamp((close - boxHigh) / MathMax(buffer, QME_EPSILON), 0.0, 1.0);
         r.valid = true;
         return(r);
        }
      if(close < boxLow - buffer && prevClose >= boxLow - QME_PRICE_EPS)
        {
         r.event = QME_STRUCT_BREAKOUT_CONFIRMED;
         r.level = boxLow;
         r.time = series.TimeAt(i);
         r.barIndex = i;
         r.strength = QmeClamp((boxLow - close) / MathMax(buffer, QME_EPSILON), 0.0, 1.0);
         r.valid = true;
         return(r);
        }
     }

   //--- failed breakout: closed outside earlier, now back inside
   const double newest = series.Close(0);
   for(int i = 1; i < confirmBars + 2 && i < series.Count(); i++)
     {
      const double c = series.Close(i);
      const bool wasAbove = (c > boxHigh + buffer);
      const bool wasBelow = (c < boxLow - buffer);
      if((wasAbove && newest < boxHigh) || (wasBelow && newest > boxLow))
        {
         r.event = QME_STRUCT_BREAKOUT_FAILED;
         r.level = wasAbove ? boxHigh : boxLow;
         r.time = series.TimeAt(i);
         r.barIndex = i;
         r.strength = 0.5;
         r.valid = true;
         return(r);
        }
     }
   return(r);
  }

#endif // __QME_ANALYSIS_BREAKOUTENGINE_MQH__
//+------------------------------------------------------------------+
