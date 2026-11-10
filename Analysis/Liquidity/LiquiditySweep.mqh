//+------------------------------------------------------------------+
//|                                 Analysis/Liquidity/LiquiditySweep |
//|  Liquidity sweep (stop raid) detection.                            |
//|                                                                   |
//|  DEFINITION:                                                      |
//|   Buy-side level (resting buy stops ABOVE price):                  |
//|     a closed bar trades at least `penetration` beyond the level      |
//|     (high > level + penetration) and CLOSES back below the level.     |
//|     => the pool was swept; the implied trade direction is SELL.      |
//|   Sell-side level (below price): mirror rule, implied direction BUY. |
//|                                                                   |
//|  Only CLOSED bars are examined, so a sweep cannot be claimed from a   |
//|  wick that is still forming.                                        |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_LIQUIDITYSWEEP_MQH__
#define __QME_ANALYSIS_LIQUIDITYSWEEP_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

struct SSweepResult
  {
   bool              valid;
   ENUM_QME_SIDE     levelSide;    // side of the liquidity that was taken
   ENUM_QME_SIDE     tradeSide;    // implied direction after the sweep
   double            level;
   double            extreme;      // wick extreme reached
   double            penetration;  // in ATR units
   datetime          time;
   int               barIndex;
  };

void QmeSweepClear(SSweepResult &s)
  {
   s.valid = false;
   s.levelSide = QME_SIDE_NONE;
   s.tradeSide = QME_SIDE_NONE;
   s.level = 0.0;
   s.extreme = 0.0;
   s.penetration = 0.0;
   s.time = 0;
   s.barIndex = -1;
  }

class CLiquiditySweep
  {
public:
   //--- levelSide: QME_SIDE_BUY for a pool above price, QME_SIDE_SELL below
   static SSweepResult Detect(CBarSeries &series, const double level,
                              const ENUM_QME_SIDE levelSide, const double atr,
                              const int scanBars, const double penetrationAtr);
   //--- best sweep over a set of levels (newest wins)
   static SSweepResult Best(CBarSeries &series, const SLiquidityLevel &levels[],
                            const int count, const double atr, const int scanBars,
                            const double penetrationAtr);
  };

//------------------------------------------------------------------//
SSweepResult CLiquiditySweep::Detect(CBarSeries &series, const double level,
                                     const ENUM_QME_SIDE levelSide, const double atr,
                                     const int scanBars, const double penetrationAtr)
  {
   SSweepResult r;
   QmeSweepClear(r);
   if(!series.IsValid() || level <= 0.0 || levelSide == QME_SIDE_NONE) return(r);

   const double pen = MathMax(atr * penetrationAtr, QME_PRICE_EPS);
   const int limit = MathMin(scanBars, series.Count());

   for(int i = 0; i < limit; i++)
     {
      if(levelSide == QME_SIDE_BUY)
        {
         const double h = series.High(i);
         const double c = series.Close(i);
         if(h > level + pen && c < level - QME_PRICE_EPS)
           {
            r.valid = true;
            r.levelSide = QME_SIDE_BUY;
            r.tradeSide = QME_SIDE_SELL;
            r.level = level;
            r.extreme = h;
            r.penetration = (h - level) / MathMax(atr, QME_EPSILON);
            r.time = series.TimeAt(i);
            r.barIndex = i;
            return(r);
           }
        }
      else
        {
         const double l = series.Low(i);
         const double c = series.Close(i);
         if(l < level - pen && c > level + QME_PRICE_EPS)
           {
            r.valid = true;
            r.levelSide = QME_SIDE_SELL;
            r.tradeSide = QME_SIDE_BUY;
            r.level = level;
            r.extreme = l;
            r.penetration = (level - l) / MathMax(atr, QME_EPSILON);
            r.time = series.TimeAt(i);
            r.barIndex = i;
            return(r);
           }
        }
     }
   return(r);
  }

//------------------------------------------------------------------//
SSweepResult CLiquiditySweep::Best(CBarSeries &series, const SLiquidityLevel &levels[],
                                   const int count, const double atr, const int scanBars,
                                   const double penetrationAtr)
  {
   SSweepResult best;
   QmeSweepClear(best);
   for(int i = 0; i < count; i++)
     {
      SSweepResult s = Detect(series, levels[i].price, levels[i].side, atr, scanBars, penetrationAtr);
      if(!s.valid) continue;
      //--- prefer the freshest sweep; tie-break on deeper penetration
      if(!best.valid ||
         s.barIndex < best.barIndex ||
         (s.barIndex == best.barIndex && s.penetration > best.penetration))
         best = s;
     }
   return(best);
  }

#endif // __QME_ANALYSIS_LIQUIDITYSWEEP_MQH__
//+------------------------------------------------------------------+
