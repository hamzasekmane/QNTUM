//+------------------------------------------------------------------+
//|                                        Analysis/Market/BiasEngine |
//|  Higher-timeframe directional bias with an explicit, inspectable    |
//|  score. Bias is a HEURISTIC context score in [0,1] — it is not a     |
//|  probability and is never reported as one.                          |
//|                                                                   |
//|  Components (equal thirds, each 0..1):                              |
//|    trend strength (aligned EMA stack + ATR-normalised slope)        |
//|    momentum agreement (sign of momentum vs bias)                    |
//|    regime agreement (trend regime needed for a directional bias)    |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_BIAS_ENGINE_MQH__
#define __QME_ANALYSIS_BIAS_ENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "TrendEngine.mqh"
#include "MomentumEngine.mqh"
#include "RegimeEngine.mqh"

struct SBiasResult
  {
   ENUM_QME_SIDE     side;
   double            score;        // 0..1 heuristic strength
   ENUM_QME_TREND    trend;
   ENUM_QME_REGIME   regime;
   bool              aligned;      // all three components agree
   bool              valid;
  };

class CBiasEngine
  {
public:
   static SBiasResult Evaluate(const STrendResult &trend, const SMomentumResult &mom,
                               const SRegimeResult &regime);
  };

//------------------------------------------------------------------//
SBiasResult CBiasEngine::Evaluate(const STrendResult &trend, const SMomentumResult &mom,
                                  const SRegimeResult &regime)
  {
   SBiasResult r;
   r.side = QME_SIDE_NONE;
   r.score = 0.0;
   r.trend = trend.trend;
   r.regime = regime.regime;
   r.aligned = false;
   r.valid = false;

   if(!trend.valid || !mom.valid || !regime.valid) return(r);

   ENUM_QME_SIDE dir = QME_SIDE_NONE;
   if(trend.trend == QME_TREND_UP)   dir = QME_SIDE_BUY;
   if(trend.trend == QME_TREND_DOWN) dir = QME_SIDE_SELL;

   //--- component 1: trend strength, only when the stack is actually aligned
   const double cTrend = trend.stackAligned ? trend.strength : trend.strength * 0.4;

   //--- component 2: momentum must point the same way
   double cMom = 0.0;
   if(dir == QME_SIDE_BUY)       cMom = QmeClamp(mom.value, 0.0, 1.0);
   else if(dir == QME_SIDE_SELL) cMom = QmeClamp(-mom.value, 0.0, 1.0);

   //--- component 3: regime must be directional
   double cRegime = 0.0;
   if(dir == QME_SIDE_BUY && regime.regime == QME_REGIME_TREND_UP)
      cRegime = regime.confidence;
   else if(dir == QME_SIDE_SELL && regime.regime == QME_REGIME_TREND_DOWN)
      cRegime = regime.confidence;
   else if(regime.regime == QME_REGIME_RANGE)
      cRegime = 0.0;   // a range gives no directional bias

   r.score = QmeClamp((cTrend + cMom + cRegime) / 3.0, 0.0, 1.0);
   r.aligned = (cTrend > 0.4 && cMom > 0.2 && cRegime > 0.3);

   //--- a bias exists only when the trend is directional and the score is useful
   if(dir != QME_SIDE_NONE && r.score >= 0.30)
      r.side = dir;
   else
      r.side = QME_SIDE_NONE;

   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_BIAS_ENGINE_MQH__
//+------------------------------------------------------------------+
