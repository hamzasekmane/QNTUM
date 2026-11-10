//+------------------------------------------------------------------+
//|                                       Analysis/Market/RegimeEngine |
//|  Market regime from the Kaufman efficiency ratio plus volatility.    |
//|                                                                   |
//|  efficiencyRatio = |close(0) - close(N-1)| / sum(|close(i)-close(i+1)|)|
//|    ~1.0 = perfectly directional, ~0.0 = pure noise                   |
//|                                                                   |
//|  Rules:                                                           |
//|   ER >= 0.45 and trend UP   -> TREND_UP                            |
//|   ER >= 0.45 and trend DOWN -> TREND_DOWN                          |
//|   ER <= 0.25                -> RANGE                               |
//|   ER in between: EXPANSION when vol high, CONTRACTION when vol low  |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_REGIME_ENGINE_MQH__
#define __QME_ANALYSIS_REGIME_ENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/TimeframeContext.mqh"
#include "TrendEngine.mqh"
#include "VolatilityEngine.mqh"

struct SRegimeResult
  {
   ENUM_QME_REGIME   regime;
   double            confidence;      // 0..1
   double            efficiencyRatio; // 0..1
   ENUM_QME_TREND    trend;
   ENUM_QME_VOLATILITY volatility;
   double            rangeCompression; // 0..1, 1 = tightest
   int               lookback;
   bool              valid;
  };

class CRegimeEngine
  {
public:
   static SRegimeResult Evaluate(CTimeframeContext &ctx, const STrendResult &trend,
                                 const SVolatilityResult &vol, const int lookback = 20);
  };

//------------------------------------------------------------------//
SRegimeResult CRegimeEngine::Evaluate(CTimeframeContext &ctx, const STrendResult &trend,
                                      const SVolatilityResult &vol, const int lookback)
  {
   SRegimeResult r;
   r.regime = QME_REGIME_UNKNOWN;
   r.confidence = 0.0;
   r.efficiencyRatio = 0.0;
   r.trend = trend.trend;
   r.volatility = vol.state;
   r.rangeCompression = 0.0;
   r.lookback = lookback;
   r.valid = false;

   CBarSeries *s = ctx.Series();
   if(s == NULL) return(r);
   if(s.Count() <= lookback + 1) return(r);
   if(!trend.valid || !vol.valid) return(r);

   //--- Kaufman efficiency ratio over the lookback window
   const double newest = s.Close(0);
   const double oldest = s.Close(lookback);
   if(newest <= 0.0 || oldest <= 0.0) return(r);

   double path = 0.0;
   for(int i = 0; i < lookback; i++)
      path += MathAbs(s.Close(i) - s.Close(i + 1));
   if(path <= QME_EPSILON) return(r);

   r.efficiencyRatio = QmeClamp(MathAbs(newest - oldest) / path, 0.0, 1.0);

   //--- range compression: current 20-bar range vs the 60-bar range
   const double range20 = s.Highest(0, 20) - s.Lowest(0, 20);
   const double range60 = s.Highest(0, 60) - s.Lowest(0, 60);
   if(range60 > QME_EPSILON)
      r.rangeCompression = QmeClamp(1.0 - (range20 / range60), 0.0, 1.0);

   if(r.efficiencyRatio >= 0.45 && trend.trend == QME_TREND_UP)
     {
      r.regime = QME_REGIME_TREND_UP;
      r.confidence = QmeClamp(0.4 + 0.6 * (r.efficiencyRatio - 0.45) / 0.55, 0.0, 1.0);
     }
   else if(r.efficiencyRatio >= 0.45 && trend.trend == QME_TREND_DOWN)
     {
      r.regime = QME_REGIME_TREND_DOWN;
      r.confidence = QmeClamp(0.4 + 0.6 * (r.efficiencyRatio - 0.45) / 0.55, 0.0, 1.0);
     }
   else if(r.efficiencyRatio <= 0.25)
     {
      r.regime = QME_REGIME_RANGE;
      r.confidence = QmeClamp(0.4 + 0.6 * (0.25 - r.efficiencyRatio) / 0.25, 0.0, 1.0);
     }
   else
     {
      //--- transitional: the volatility state decides
      if(vol.state == QME_VOL_HIGH || vol.state == QME_VOL_EXTREME)
        {
         r.regime = QME_REGIME_EXPANSION;
         r.confidence = 0.45;
        }
      else if(vol.state == QME_VOL_LOW)
        {
         r.regime = QME_REGIME_CONTRACTION;
         r.confidence = 0.45;
        }
      else
        {
         r.regime = QME_REGIME_RANGE;
         r.confidence = 0.30;   // weak classification, deliberately low
        }
     }

   //--- a strong efficiency ratio makes any classification more credible
   r.confidence = QmeClamp(r.confidence * (0.7 + 0.3 * r.efficiencyRatio), 0.0, 1.0);
   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_REGIME_ENGINE_MQH__
//+------------------------------------------------------------------+
