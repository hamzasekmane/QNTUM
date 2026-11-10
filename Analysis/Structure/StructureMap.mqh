//+------------------------------------------------------------------+
//|                                    Analysis/Structure/StructureMap |
//|  Turns the confirmed swing list into a structural state:            |
//|  last swing high/low, HH/HL/LH/LL and the structural trend.         |
//|                                                                   |
//|  Ownership: pure function over an SStructureState; no hidden state. |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_STRUCTUREMAP_MQH__
#define __QME_ANALYSIS_STRUCTUREMAP_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "SwingDetector.mqh"

class CStructureMap
  {
public:
   //--- fill `state` from confirmed swings (newest first)
   static bool       Build(const SStructurePoint &swings[], const int swingCount,
                           SStructureState &state);

   //--- index of the newest swing of the requested kind, -1 when absent
   static int        NewestIndex(const SStructurePoint &swings[], const int count, const bool isHigh);
   //--- the N-th newest swing high / low (0 = newest); false when missing
   static bool       NthSwing(const SStructurePoint &swings[], const int count,
                              const bool isHigh, const int nth, SStructurePoint &out);
  };

//------------------------------------------------------------------//
int CStructureMap::NewestIndex(const SStructurePoint &swings[], const int count, const bool isHigh)
  {
   for(int i = 0; i < count; i++)
      if(swings[i].isHigh == isHigh) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CStructureMap::NthSwing(const SStructurePoint &swings[], const int count,
                             const bool isHigh, const int nth, SStructurePoint &out)
  {
   int seen = 0;
   for(int i = 0; i < count; i++)
     {
      if(swings[i].isHigh != isHigh) continue;
      if(seen == nth)
        {
         out = swings[i];
         return(true);
        }
      seen++;
     }
   return(false);
  }

//------------------------------------------------------------------//
bool CStructureMap::Build(const SStructurePoint &swings[], const int swingCount,
                          SStructureState &state)
  {
   if(swingCount <= 0)
     {
      state.valid = false;
      return(false);
     }

   //--- copy swings into the fixed-capacity state
   state.swingCount = MathMin(swingCount, QME_MAX_SWINGS);
   for(int i = 0; i < state.swingCount; i++)
      state.swings[i] = swings[i];

   const int hiIdx = NewestIndex(swings, swingCount, true);
   const int loIdx = NewestIndex(swings, swingCount, false);

   if(hiIdx >= 0)
     {
      state.lastSwingHigh = swings[hiIdx].price;
      state.lastSwingHighTime = swings[hiIdx].time;
     }
   if(loIdx >= 0)
     {
      state.lastSwingLow = swings[loIdx].price;
      state.lastSwingLowTime = swings[loIdx].time;
     }

   //--- HH/HL/LH/LL from the two most recent swings of each kind
   SStructurePoint h1, h2, l1, l2;
   const bool hasH2 = NthSwing(swings, swingCount, true, 1, h2);
   const bool hasH1 = NthSwing(swings, swingCount, true, 0, h1);
   const bool hasL2 = NthSwing(swings, swingCount, false, 1, l2);
   const bool hasL1 = NthSwing(swings, swingCount, false, 0, l1);

   state.higherHigh = (hasH1 && hasH2 && h1.price > h2.price + QME_PRICE_EPS);
   state.lowerHigh  = (hasH1 && hasH2 && h1.price < h2.price - QME_PRICE_EPS);
   state.higherLow  = (hasL1 && hasL2 && l1.price > l2.price + QME_PRICE_EPS);
   state.lowerLow   = (hasL1 && hasL2 && l1.price < l2.price - QME_PRICE_EPS);

   //--- structural trend
   if(state.higherHigh && state.higherLow)
      state.trend = QME_TREND_UP;
   else if(state.lowerHigh && state.lowerLow)
      state.trend = QME_TREND_DOWN;
   else if(state.higherHigh || state.higherLow)
      state.trend = QME_TREND_UP;
   else if(state.lowerHigh || state.lowerLow)
      state.trend = QME_TREND_DOWN;
   else
      state.trend = QME_TREND_FLAT;

   state.valid = (hiIdx >= 0 && loIdx >= 0);
   return(state.valid);
  }

#endif // __QME_ANALYSIS_STRUCTUREMAP_MQH__
//+------------------------------------------------------------------+
