//+------------------------------------------------------------------+
//|                                  Analysis/PriceAction/ReactionEngine|
//|  Did price actually REACT at a level, or just pass through it?        |
//|                                                                   |
//|  DEFINITION:                                                       |
//|   a reaction exists when, inside `scanBars`, a closed bar             |
//|     - traded into the level zone (within tolerance), AND              |
//|     - closed away from it by at least `minBodyAtr * ATR`, AND         |
//|     - closed on the away side of the level.                          |
//|  The strongest (largest displacement) reaction is returned.          |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_REACTIONENGINE_MQH__
#define __QME_ANALYSIS_REACTIONENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

struct SReactionResult
  {
   bool              valid;
   ENUM_QME_SIDE     side;      // direction price moved away (BUY = bounced up)
   double            level;
   double            strength;  // 0..1
   datetime          time;
   int               barIndex;
  };

class CReactionEngine
  {
public:
   static SReactionResult AtLevel(CBarSeries &series, const double level,
                                  const double atr, const int scanBars,
                                  const double toleranceAtr = 0.25,
                                  const double minBodyAtr = 0.30);
  };

//------------------------------------------------------------------//
SReactionResult CReactionEngine::AtLevel(CBarSeries &series, const double level,
                                         const double atr, const int scanBars,
                                         const double toleranceAtr, const double minBodyAtr)
  {
   SReactionResult r;
   r.valid = false;
   r.side = QME_SIDE_NONE;
   r.level = level;
   r.strength = 0.0;
   r.time = 0;
   r.barIndex = -1;

   if(!series.IsValid() || level <= 0.0 || atr <= QME_EPSILON) return(r);

   const double tol = atr * toleranceAtr;
   const double minBody = atr * minBodyAtr;
   const int limit = MathMin(scanBars, series.Count());

   for(int i = 0; i < limit; i++)
     {
      SCandle c;
      if(!series.Get(i, c)) continue;

      //--- did this bar touch the level zone?
      const bool touched = (c.low <= level + tol) && (c.high >= level - tol);
      if(!touched) continue;

      const double body = QmeCandleBody(c);
      if(body < minBody) continue;

      //--- bounced up: closed above the level after trading below/at it
      if(c.close > level + tol && QmeCandleIsBull(c))
        {
         r.valid = true;
         r.side = QME_SIDE_BUY;
         r.strength = QmeClamp(body / MathMax(atr, QME_EPSILON), 0.0, 1.0);
         r.time = c.time;
         r.barIndex = i;
         return(r);
        }
      //--- rejected down
      if(c.close < level - tol && QmeCandleIsBear(c))
        {
         r.valid = true;
         r.side = QME_SIDE_SELL;
         r.strength = QmeClamp(body / MathMax(atr, QME_EPSILON), 0.0, 1.0);
         r.time = c.time;
         r.barIndex = i;
         return(r);
        }
     }
   return(r);
  }

#endif // __QME_ANALYSIS_REACTIONENGINE_MQH__
//+------------------------------------------------------------------+
