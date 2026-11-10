//+------------------------------------------------------------------+
//|                              Analysis/Liquidity/EqualHighLow      |
//|  Equal highs / equal lows = clusters of swings at (nearly) the same  |
//|  price. They are the strongest RESTING liquidity references.         |
//|                                                                   |
//|  DEFINITION:                                                      |
//|   two swing highs are "equal" when |h1-h2| <= tol, where            |
//|   tol = max(equalToleranceAtr * ATR, 2 * point).                    |
//|   A cluster of >= 2 equal highs is reported at the MEAN price with    |
//|   strength increasing with the number of touches.                    |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_EQUALHL_MQH__
#define __QME_ANALYSIS_EQUALHL_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

struct SEqualCluster
  {
   double            price;      // mean of the cluster
   bool              isHigh;     // true = equal highs (buy-side above)
   int               touches;
   datetime          newest;
   datetime          oldest;
   double            tolerance;
  };

class CEqualHighLow
  {
public:
   //--- find equal-high and equal-low clusters among confirmed swings
   static int        Detect(const SStructurePoint &swings[], const int count,
                            const double atr, const double toleranceAtr,
                            const double point, const int maxOut,
                            SEqualCluster &out[]);
  };

//------------------------------------------------------------------//
int CEqualHighLow::Detect(const SStructurePoint &swings[], const int count,
                          const double atr, const double toleranceAtr,
                          const double point, const int maxOut,
                          SEqualCluster &out[])
  {
   ArrayResize(out, 0);
   if(count < 2 || maxOut <= 0) return(0);

   double tol = atr * toleranceAtr;
   const double floorTol = 2.0 * ((point > 0.0) ? point : QME_PRICE_EPS);
   if(tol < floorTol) tol = floorTol;

   bool used[QME_MAX_SWINGS];
   for(int i = 0; i < QME_MAX_SWINGS; i++) used[i] = false;

   int found = 0;
   for(int i = 0; i < count && found < maxOut; i++)
     {
      if(used[i]) continue;
      const double p0 = swings[i].price;
      if(p0 <= 0.0) continue;

      double sum = p0;
      int touches = 1;
      datetime newest = swings[i].time;
      datetime oldest = swings[i].time;
      used[i] = true;

      for(int j = i + 1; j < count; j++)
        {
         if(used[j]) continue;
         if(swings[j].isHigh != swings[i].isHigh) continue;
         if(MathAbs(swings[j].price - p0) > tol) continue;
         used[j] = true;
         sum += swings[j].price;
         touches++;
         if(swings[j].time > newest) newest = swings[j].time;
         if(swings[j].time < oldest)  oldest = swings[j].time;
        }

      if(touches < 2) continue;   // a single swing is not a cluster

      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n].price = sum / touches;
      out[n].isHigh = swings[i].isHigh;
      out[n].touches = touches;
      out[n].newest = newest;
      out[n].oldest = oldest;
      out[n].tolerance = tol;
      found++;
     }
   return(found);
  }

#endif // __QME_ANALYSIS_EQUALHL_MQH__
//+------------------------------------------------------------------+
