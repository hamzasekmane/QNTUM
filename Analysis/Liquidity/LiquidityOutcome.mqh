//+------------------------------------------------------------------+
//| Analysis/Liquidity/LiquidityOutcome                               |
//| Distinguishes a rejection sweep from accepted breakout using only  |
//| completed-bar observations supplied in chronological order.       |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_LIQUIDITYOUTCOME_MQH__
#define __QME_ANALYSIS_LIQUIDITYOUTCOME_MQH__

#include "../../Core/Enums.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "LiquiditySweep.mqh"

#define QME_LIQUIDITY_WAIT       0
#define QME_LIQUIDITY_SWEEP      1
#define QME_LIQUIDITY_BREAKOUT   2

struct SLiquidityBar
  {
   double high;
   double low;
   double close;
  };

struct SLiquidityOutcome
  {
   int classification;       // WAIT / SWEEP / BREAKOUT
   int sweepBar;             // index in caller's oldest-to-newest array
   double wickExtreme;
   string reason;
  };

class CLiquidityOutcome
  {
public:
   // A sweep requires a penetration and close back through the level.
   // It is CONFIRMED only when a later completed bar closes through the
   // caller-provided opposite structure level (the CHoCH/MSS proxy).
   // Breakout requires a close beyond the liquidity and holdBars later
   // completed closes that remain beyond it. Otherwise return WAIT.
   static SLiquidityOutcome Classify(const SLiquidityBar &bars[], const int count,
                                     const double level, const ENUM_QME_SIDE levelSide,
                                     const double oppositeStructure, const int holdBars,
                                     const double tolerance);
   static SLiquidityOutcome ConfirmSweep(CBarSeries &series, const SSweepResult &sweep,
                                         const double oppositeStructure,
                                         const int maxConfirmBars, const double tolerance);
  };

SLiquidityOutcome CLiquidityOutcome::Classify(const SLiquidityBar &bars[], const int count,
                                               const double level, const ENUM_QME_SIDE levelSide,
                                               const double oppositeStructure, const int holdBars,
                                               const double tolerance)
  {
   SLiquidityOutcome r;
   r.classification = QME_LIQUIDITY_WAIT;
   r.sweepBar = -1;
   r.wickExtreme = 0.0;
   r.reason = "insufficient or invalid closed-bar evidence";
   if(count < 2 || level <= 0.0 || tolerance < 0.0 || holdBars < 1 ||
      (levelSide != QME_SIDE_BUY && levelSide != QME_SIDE_SELL)) return(r);

   // Walk newest to oldest; the most recent relevant level interaction wins.
   for(int i = count - 1; i >= 0; i--)
     {
      const bool sweep = (levelSide == QME_SIDE_BUY) ?
                         (bars[i].high > level + tolerance && bars[i].close < level) :
                         (bars[i].low < level - tolerance && bars[i].close > level);
      const bool outside = (levelSide == QME_SIDE_BUY) ?
                           (bars[i].close > level + tolerance) :
                           (bars[i].close < level - tolerance);
      if(sweep)
        {
         r.sweepBar = i;
         r.wickExtreme = (levelSide == QME_SIDE_BUY) ? bars[i].high : bars[i].low;
         const int newer = count - 1 - i;
         if(newer < 1 || oppositeStructure <= 0.0)
           { r.reason = "rejection close seen; waiting for later CHoCH"; return(r); }
         const bool choch = (levelSide == QME_SIDE_BUY) ?
                            (bars[count-1].close < oppositeStructure) :
                            (bars[count-1].close > oppositeStructure);
         if(choch)
           { r.classification = QME_LIQUIDITY_SWEEP; r.reason = "rejection and subsequent opposite-structure close"; }
         else r.reason = "rejection seen; CHoCH not confirmed";
         return(r);
        }
      if(outside)
        {
         const int newer = count - 1 - i;
         if(newer < holdBars)
           { r.reason = "close beyond liquidity; waiting for hold confirmation"; return(r); }
         bool held = true;
         for(int j = i; j < count; j++)
           {
            if(levelSide == QME_SIDE_BUY && bars[j].close <= level + tolerance) held = false;
            if(levelSide == QME_SIDE_SELL && bars[j].close >= level - tolerance) held = false;
           }
         if(held)
           { r.classification = QME_LIQUIDITY_BREAKOUT; r.reason = "breakout accepted by consecutive closes"; }
         else r.reason = "close outside did not hold; waiting for a fresh event";
         return(r);
        }
     }
   r.reason = "no confirmed interaction with liquidity";
   return(r);
  }

SLiquidityOutcome CLiquidityOutcome::ConfirmSweep(CBarSeries &series, const SSweepResult &sweep,
                                                    const double oppositeStructure,
                                                    const int maxConfirmBars, const double tolerance)
  {
   SLiquidityBar bars[];
   SLiquidityOutcome empty;
   empty.classification=QME_LIQUIDITY_WAIT; empty.sweepBar=-1;
   empty.wickExtreme=0.0; empty.reason="sweep absent, stale, or invalid";
   if(!series.IsValid() || !sweep.valid || sweep.barIndex < 1 ||
      maxConfirmBars < 1 || sweep.barIndex > maxConfirmBars ||
      sweep.level <= 0.0 || sweep.levelSide == QME_SIDE_NONE) return(empty);
   const int n=sweep.barIndex+1;
   ArrayResize(bars,n);
   for(int k=0; k<n; k++)
     {
      const int shift=sweep.barIndex-k;
      bars[k].high=series.High(shift);
      bars[k].low=series.Low(shift);
      bars[k].close=series.Close(shift);
     }
   return(Classify(bars,n,sweep.level,sweep.levelSide,oppositeStructure,1,tolerance));
  }

#endif
