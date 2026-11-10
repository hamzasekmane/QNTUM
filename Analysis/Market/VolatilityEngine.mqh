//+------------------------------------------------------------------+
//|                                  Analysis/Market/VolatilityEngine |
//|  Volatility state from the instrument's own ATR history.            |
//|                                                                   |
//|  ATR ratio = ATR(current) / ATR(average of last 20). Thresholds come |
//|  from the asset-class tuning, never from hard-coded pip values.      |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_VOLATILITY_ENGINE_MQH__
#define __QME_ANALYSIS_VOLATILITY_ENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/TimeframeContext.mqh"
#include "../../Data/AssetClassTuning.mqh"

struct SVolatilityResult
  {
   ENUM_QME_VOLATILITY state;
   double            atr;         // price units
   double            atrAvg;
   double            atrRatio;    // atr / atrAvg
   double            atrPct;      // atr / close * 100
   double            percentile;  // 0..1 rough percentile of atrRatio
   bool              valid;
  };

class CVolatilityEngine
  {
public:
   static SVolatilityResult Evaluate(CTimeframeContext &ctx, const SAssetTuning &tuning);
  };

//------------------------------------------------------------------//
SVolatilityResult CVolatilityEngine::Evaluate(CTimeframeContext &ctx, const SAssetTuning &tuning)
  {
   SVolatilityResult r;
   r.state = QME_VOL_UNKNOWN;
   r.atr = 0.0;
   r.atrAvg = 0.0;
   r.atrRatio = 0.0;
   r.atrPct = 0.0;
   r.percentile = 0.5;
   r.valid = false;

   if(!ctx.IndicatorReady()) return(r);

   r.atr = ctx.Atr();
   r.atrAvg = ctx.AtrAvg();
   r.atrPct = ctx.AtrPct();
   if(r.atr <= 0.0 || !QmeIsFinite(r.atr)) return(r);

   r.atrRatio = (r.atrAvg > 0.0) ? r.atr / r.atrAvg : 1.0;

   //--- map the ratio onto a coarse percentile using the class thresholds
   if(r.atrRatio <= tuning.atrLowRatio)      r.percentile = 0.20;
   else if(r.atrRatio >= tuning.atrHighRatio) r.percentile = 0.85;
   else r.percentile = 0.50;

   if(r.atrRatio >= tuning.atrHighRatio * 1.5)  r.state = QME_VOL_EXTREME;
   else if(r.atrRatio >= tuning.atrHighRatio)   r.state = QME_VOL_HIGH;
   else if(r.atrRatio <= tuning.atrLowRatio)    r.state = QME_VOL_LOW;
   else                                         r.state = QME_VOL_NORMAL;

   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_VOLATILITY_ENGINE_MQH__
//+------------------------------------------------------------------+
