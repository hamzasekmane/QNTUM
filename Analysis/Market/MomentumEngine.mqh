//+------------------------------------------------------------------+
//|                                    Analysis/Market/MomentumEngine |
//|  Momentum = mean of (RSI deviation) and (ATR-normalised EMA         |
//|  distance), in [-1,+1].                                             |
//|                                                                   |
//|  Explicit formula:                                                 |
//|    rsiPart  = (rsi - 50) / 50                 -> [-1,+1]            |
//|    distPart = clamp((close-emaFast)/atr, -1, 1)                    |
//|    momentum = 0.6*rsiPart + 0.4*distPart                            |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_MOMENTUM_ENGINE_MQH__
#define __QME_ANALYSIS_MOMENTUM_ENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/TimeframeContext.mqh"

struct SMomentumResult
  {
   double            value;        // [-1,+1]
   double            rsi;
   double            emaDistance;  // (close-emaFast)/atr
   ENUM_QME_SIDE     direction;    // BUY when value > +0.15, SELL when < -0.15
   bool              overbought;   // rsi >= 70
   bool              oversold;     // rsi <= 30
   bool              valid;
  };

class CMomentumEngine
  {
public:
   static SMomentumResult Evaluate(CTimeframeContext &ctx);
  };

//------------------------------------------------------------------//
SMomentumResult CMomentumEngine::Evaluate(CTimeframeContext &ctx)
  {
   SMomentumResult r;
   r.value = 0.0;
   r.rsi = 0.0;
   r.emaDistance = 0.0;
   r.direction = QME_SIDE_NONE;
   r.overbought = false;
   r.oversold = false;
   r.valid = false;

   if(!ctx.IndicatorReady()) return(r);

   r.rsi = ctx.Rsi();
   const double close = ctx.Close(0);
   const double atr = MathMax(ctx.Atr(), QME_EPSILON);
   const double emaFast = ctx.EmaFast();
   if(r.rsi <= 0.0 || close <= 0.0 || emaFast <= 0.0) return(r);

   const double rsiPart = QmeClamp((r.rsi - 50.0) / 50.0, -1.0, 1.0);
   r.emaDistance = QmeClamp((close - emaFast) / atr, -2.0, 2.0);
   const double distPart = QmeClamp(r.emaDistance, -1.0, 1.0);

   r.value = QmeClamp(0.6 * rsiPart + 0.4 * distPart, -1.0, 1.0);
   r.overbought = (r.rsi >= 70.0);
   r.oversold = (r.rsi <= 30.0);

   if(r.value > 0.15)      r.direction = QME_SIDE_BUY;
   else if(r.value < -0.15) r.direction = QME_SIDE_SELL;
   else                     r.direction = QME_SIDE_NONE;

   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_MOMENTUM_ENGINE_MQH__
//+------------------------------------------------------------------+
