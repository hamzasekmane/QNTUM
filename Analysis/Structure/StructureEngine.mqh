//+------------------------------------------------------------------+
//|                                 Analysis/Structure/StructureEngine |
//|  Orchestrates swing detection + structure map for one context.      |
//|  Produces the SStructureState consumed by BOS/MSS/zones/scoring.    |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_STRUCTUREENGINE_MQH__
#define __QME_ANALYSIS_STRUCTUREENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Data/TimeframeContext.mqh"
#include "../../Data/AssetClassTuning.mqh"
#include "SwingDetector.mqh"
#include "StructureMap.mqh"

class CStructureEngine
  {
public:
   //--- build state from a context; returns false when structure is unusable
   static bool       Evaluate(CTimeframeContext &ctx, const SAssetTuning &tuning,
                              const int scanBars, SStructureState &state);
  };

//------------------------------------------------------------------//
bool CStructureEngine::Evaluate(CTimeframeContext &ctx, const SAssetTuning &tuning,
                                const int scanBars, SStructureState &state)
  {
   QmeStructureReset(state);
   CBarSeries *series = ctx.Series();
   if(series == NULL || !series.IsValid()) return(false);

   const int left = QME_SWING_LEFT_BARS;
   const int right = (tuning.swingRightBars > 0) ? tuning.swingRightBars : QME_SWING_RIGHT_BARS;

   SStructurePoint swings[];
   const int n = CSwingDetector::Detect(series, scanBars, left, right, swings);
   if(n < 2) return(false);

   if(!CStructureMap::Build(swings, n, state)) return(false);
   return(true);
  }

#endif // __QME_ANALYSIS_STRUCTUREENGINE_MQH__
//+------------------------------------------------------------------+
