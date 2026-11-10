//+------------------------------------------------------------------+
//|                                Analysis/PriceAction/CandleEngine  |
//|  Normalises a closed candle into measurable facts.                  |
//|                                                                   |
//|  All ratios are relative to the candle's own range, and the          |
//|  displacement test is relative to the average body of the last 20     |
//|  bars, so the same code works on FX, metals and indices.             |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_CANDLEENGINE_MQH__
#define __QME_ANALYSIS_CANDLEENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

class CCandleEngine
  {
public:
   //--- shift 0 = newest closed bar
   static bool       Evaluate(CBarSeries &series, const int shift, SCandleFacts &out,
                              const double displacementMult = 1.5);
  };

//------------------------------------------------------------------//
bool CCandleEngine::Evaluate(CBarSeries &series, const int shift, SCandleFacts &out,
                             const double displacementMult)
  {
   QmeCandleFactsClear(out);
   SCandle c;
   if(!series.Get(shift, c)) return(false);

   const double range = QmeCandleRange(c);
   if(range <= QME_EPSILON) return(false);

   out.bodyRatio = QmeCandleBody(c) / range;
   out.upperWickRatio = QmeCandleUpperWick(c) / range;
   out.lowerWickRatio = QmeCandleLowerWick(c) / range;
   out.closePos = QmeCandleClosePos(c);

   //--- displacement: body significantly larger than the recent average body
   const double avgBody = series.AverageBody(20);
   if(avgBody > QME_EPSILON)
     {
      const double ratio = QmeCandleBody(c) / avgBody;
      out.displacement = (ratio >= displacementMult) && (out.bodyRatio >= 0.55);
      out.displacementScore = QmeClamp((ratio - 1.0) / 2.0, 0.0, 1.0);
     }
   out.valid = true;
   return(true);
  }

#endif // __QME_ANALYSIS_CANDLEENGINE_MQH__
//+------------------------------------------------------------------+
