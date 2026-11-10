//+------------------------------------------------------------------+
//|                                       Analysis/Structure/MssEngine |
//|  Market Structure Shift (MSS): a break of structure AGAINST the      |
//|  previous structural trend, i.e. a genuine reversal signal.          |
//|                                                                   |
//|  DEFINITION:                                                      |
//|   MSS_UP   : structural trend was DOWN and a closed bar closes above |
//|              the last swing high (the downtrend's structure fails).   |
//|   MSS_DOWN : structural trend was UP and a closed bar closes below    |
//|              the last swing low.                                     |
//|  MSS is only valid when the level broken is the last opposing swing   |
//|  and the break is confirmed by a closed bar. It cannot repaint.       |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_MSSENGINE_MQH__
#define __QME_ANALYSIS_MSSENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "BosEngine.mqh"

class CMssEngine
  {
public:
   static SStructureEvent Detect(CBarSeries &series, const SStructureState &state,
                                 const double atr, const int scanBars);

   //--- convenience: does the state carry a confirmed MSS?
   static bool       IsConfirmed(const SStructureState &state);
  };

//------------------------------------------------------------------//
SStructureEvent CMssEngine::Detect(CBarSeries &series, const SStructureState &state,
                                   const double atr, const int scanBars)
  {
   SStructureEvent r;
   QmeStructureEventClear(r);
   if(!state.valid || !series.IsValid()) return(r);

   const double ref = MathMax(atr, QME_EPSILON);
   const int limit = MathMin(scanBars, series.Count() - 1);

   //--- reversal up: structure was down, price closes above the last swing high
   if(state.trend == QME_TREND_DOWN && state.lastSwingHigh > 0.0)
     {
      for(int i = 0; i < limit; i++)
        {
         const double close = series.Close(i);
         if(close > state.lastSwingHigh + QME_PRICE_EPS)
           {
            r.event = QME_STRUCT_MSS_UP;
            r.level = state.lastSwingHigh;
            r.time = series.TimeAt(i);
            r.barIndex = i;
            r.strength = QmeClamp((close - state.lastSwingHigh) / ref, 0.0, 1.0);
            r.valid = true;
            return(r);
           }
        }
     }

   //--- reversal down: structure was up, price closes below the last swing low
   if(state.trend == QME_TREND_UP && state.lastSwingLow > 0.0)
     {
      for(int i = 0; i < limit; i++)
        {
         const double close = series.Close(i);
         if(close < state.lastSwingLow - QME_PRICE_EPS)
           {
            r.event = QME_STRUCT_MSS_DOWN;
            r.level = state.lastSwingLow;
            r.time = series.TimeAt(i);
            r.barIndex = i;
            r.strength = QmeClamp((state.lastSwingLow - close) / ref, 0.0, 1.0);
            r.valid = true;
            return(r);
           }
        }
     }
   return(r);
  }

//------------------------------------------------------------------//
bool CMssEngine::IsConfirmed(const SStructureState &state)
  {
   //--- the flag IS the confirmation record: it is set by the scanner from
   //--- the detected MSS event (with mssSide). It must not be gated on a
   //--- second, independently-maintained field (lastEvent), which left
   //--- this permanently false and the flag meaningless.
   return(state.mssConfirmed);
  }

#endif // __QME_ANALYSIS_MSSENGINE_MQH__
//+------------------------------------------------------------------+
