//+------------------------------------------------------------------+
//|                                       Analysis/Market/TrendEngine |
//|  EMA-stack trend classification with an ATR-normalised slope.       |
//|                                                                   |
//|  Explicit rules (testable):                                        |
//|   UP   : emaFast > emaSlow > emaTrend and slope > 0                 |
//|   DOWN : emaFast < emaSlow < emaTrend and slope < 0                 |
//|   FLAT : everything else                                            |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_TREND_ENGINE_MQH__
#define __QME_ANALYSIS_TREND_ENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/TimeframeContext.mqh"

struct STrendResult
  {
   ENUM_QME_TREND    trend;
   double            strength;    // 0..1
   double            emaFast;
   double            emaSlow;
   double            emaTrend;
   double            slope;       // (emaFast - emaFast[3]) / atr
   bool              stackAligned;
   bool              valid;
  };

class CTrendEngine
  {
public:
   static STrendResult Evaluate(CTimeframeContext &ctx);
  };

//------------------------------------------------------------------//
STrendResult CTrendEngine::Evaluate(CTimeframeContext &ctx)
  {
   STrendResult r;
   r.trend = QME_TREND_UNKNOWN;
   r.strength = 0.0;
   r.emaFast = 0.0;
   r.emaSlow = 0.0;
   r.emaTrend = 0.0;
   r.slope = 0.0;
   r.stackAligned = false;
   r.valid = false;

   if(!ctx.IndicatorReady()) return(r);

   r.emaFast = ctx.EmaFast();
   r.emaSlow = ctx.EmaSlow();
   r.emaTrend = ctx.EmaTrend();
   if(r.emaFast <= 0.0 || r.emaSlow <= 0.0 || r.emaTrend <= 0.0) return(r);

   //--- slope of the fast EMA over 3 closed bars, normalised by ATR
   double prev = 0.0;
   if(ctx.Indicators().EmaFast(3, prev) && ctx.Atr() > 0.0)
      r.slope = (r.emaFast - prev) / ctx.Atr();

   r.stackAligned = ((r.emaFast > r.emaSlow && r.emaSlow > r.emaTrend) ||
                     (r.emaFast < r.emaSlow && r.emaSlow < r.emaTrend));

   if(r.emaFast > r.emaSlow && r.emaSlow > r.emaTrend && r.slope > 0.0)
      r.trend = QME_TREND_UP;
   else if(r.emaFast < r.emaSlow && r.emaSlow < r.emaTrend && r.slope < 0.0)
      r.trend = QME_TREND_DOWN;
   else
      r.trend = QME_TREND_FLAT;

   //--- strength: separation of the stack plus slope magnitude, both in ATR
   const double atr = MathMax(ctx.Atr(), QME_EPSILON);
   const double sep = MathAbs(r.emaFast - r.emaTrend) / atr;
   double s = 0.5 * QmeClamp(sep / 2.0, 0.0, 1.0) +
              0.5 * QmeClamp(MathAbs(r.slope) / 1.0, 0.0, 1.0);
   if(r.trend == QME_TREND_FLAT) s *= 0.35;
   r.strength = QmeClamp(s, 0.0, 1.0);

   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_TREND_ENGINE_MQH__
//+------------------------------------------------------------------+
