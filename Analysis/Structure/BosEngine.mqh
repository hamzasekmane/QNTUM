//+------------------------------------------------------------------+
//|                                       Analysis/Structure/BosEngine |
//|  Break of Structure (BOS): price closes beyond a confirmed swing     |
//|  level in the direction of the prevailing structure.                 |
//|                                                                   |
//|  DEFINITION:                                                      |
//|   BOS_UP   : a CLOSED bar closes above state.lastSwingHigh while the |
//|              structural trend was already up (continuation).         |
//|   BOS_DOWN : a CLOSED bar closes below state.lastSwingLow while the   |
//|              structural trend was already down.                     |
//|  The break is only reported once, at the first closing bar beyond     |
//|  the level, using closed data only.                                  |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_BOSENGINE_MQH__
#define __QME_ANALYSIS_BOSENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

struct SStructureEvent
  {
   ENUM_QME_STRUCT_EVENT event;
   double            level;
   datetime          time;
   int               barIndex;    // 0 = newest closed bar
   double            strength;    // 0..1 = displacement beyond the level / ATR
   bool              valid;
  };

void QmeStructureEventClear(SStructureEvent &e)
  {
   e.event = QME_STRUCT_NONE;
   e.level = 0.0;
   e.time = 0;
   e.barIndex = -1;
   e.strength = 0.0;
   e.valid = false;
  }

class CBosEngine
  {
public:
   //--- look back `scanBars` closed bars for a fresh break
   static SStructureEvent Detect(CBarSeries &series, const SStructureState &state,
                                 const double atr, const int scanBars);
  };

//------------------------------------------------------------------//
SStructureEvent CBosEngine::Detect(CBarSeries &series, const SStructureState &state,
                                   const double atr, const int scanBars)
  {
   SStructureEvent r;
   QmeStructureEventClear(r);
   if(!state.valid) return(r);
   if(!series.IsValid()) return(r);

   const double ref = MathMax(atr, QME_EPSILON);
   const int limit = MathMin(scanBars, series.Count() - 1);

   for(int i = 0; i < limit; i++)
     {
      const double close = series.Close(i);
      if(close <= 0.0) continue;

      //--- upward break
      if(state.lastSwingHigh > 0.0 && close > state.lastSwingHigh + QME_PRICE_EPS &&
         state.trend == QME_TREND_UP)
        {
         r.event = QME_STRUCT_BOS_UP;
         r.level = state.lastSwingHigh;
         r.time = series.TimeAt(i);
         r.barIndex = i;
         r.strength = QmeClamp((close - state.lastSwingHigh) / ref, 0.0, 1.0);
         r.valid = true;
         return(r);
        }

      //--- downward break
      if(state.lastSwingLow > 0.0 && close < state.lastSwingLow - QME_PRICE_EPS &&
         state.trend == QME_TREND_DOWN)
        {
         r.event = QME_STRUCT_BOS_DOWN;
         r.level = state.lastSwingLow;
         r.time = series.TimeAt(i);
         r.barIndex = i;
         r.strength = QmeClamp((state.lastSwingLow - close) / ref, 0.0, 1.0);
         r.valid = true;
         return(r);
        }
     }
   return(r);
  }

#endif // __QME_ANALYSIS_BOSENGINE_MQH__
//+------------------------------------------------------------------+
