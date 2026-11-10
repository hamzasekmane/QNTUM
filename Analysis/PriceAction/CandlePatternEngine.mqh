//+------------------------------------------------------------------+
//|                         Analysis/PriceAction/CandlePatternEngine  |
//|  Explicit, testable candle pattern rules.                           |
//|                                                                   |
//|  ENGULFING  (bull): bar closes above the previous bar's open, its    |
//|              body engulfs the previous body, previous bar bearish.    |
//|  PIN BAR    : wick >= 2x body AND wick >= 60% of range, close in the  |
//|              opposite third of the range.                            |
//|  INSIDE BAR : high <= prev high and low >= prev low.                 |
//|  OUTSIDE BAR: high > prev high and low < prev low.                   |
//|  STRONG      : body >= 70% of range and displacement.                |
//|  REJECTION   : close in the outer 25% of the range with a long wick   |
//|                pointing the other way.                              |
//|  DOJI        : body <= 10% of range.                                |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_CANDLEPATTERN_MQH__
#define __QME_ANALYSIS_CANDLEPATTERN_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "CandleEngine.mqh"

struct SPatternResult
  {
   ENUM_QME_CANDLE_PATTERN pattern;
   ENUM_QME_SIDE     bias;        // implied direction of the pattern
   double            quality;     // 0..1
   bool              valid;
  };

class CCandlePatternEngine
  {
public:
   static SPatternResult Detect(CBarSeries &series, const int shift,
                                const double displacementMult = 1.5);
  private:
   static SPatternResult Engulfing(const SCandle &c, const SCandle &prev);
   static SPatternResult PinBar(const SCandle &c, const SCandleFacts &f);
   static SPatternResult Shape(const SCandle &c, const SCandle &prev, const SCandleFacts &f);
  };

//------------------------------------------------------------------//
SPatternResult CCandlePatternEngine::Engulfing(const SCandle &c, const SCandle &prev)
  {
   SPatternResult r;
   r.pattern = QME_CANDLE_NONE;
   r.bias = QME_SIDE_NONE;
   r.quality = 0.0;
   r.valid = false;

   const double body = QmeCandleBody(c);
   const double prevBody = QmeCandleBody(prev);
   if(body <= QME_EPSILON || prevBody <= QME_EPSILON) return(r);

   //--- bullish engulfing
   if(QmeCandleIsBear(prev) && QmeCandleIsBull(c) &&
      c.close > prev.open && c.open < prev.close && body > prevBody)
     {
      r.pattern = QME_CANDLE_BULL_ENGULF;
      r.bias = QME_SIDE_BUY;
      r.quality = QmeClamp(body / (prevBody + QME_EPSILON) - 1.0, 0.0, 1.0) * 0.5 + 0.5;
      r.valid = true;
      return(r);
     }
   //--- bearish engulfing
   if(QmeCandleIsBull(prev) && QmeCandleIsBear(c) &&
      c.close < prev.open && c.open > prev.close && body > prevBody)
     {
      r.pattern = QME_CANDLE_BEAR_ENGULF;
      r.bias = QME_SIDE_SELL;
      r.quality = QmeClamp(body / (prevBody + QME_EPSILON) - 1.0, 0.0, 1.0) * 0.5 + 0.5;
      r.valid = true;
      return(r);
     }
   return(r);
  }

//------------------------------------------------------------------//
SPatternResult CCandlePatternEngine::PinBar(const SCandle &c, const SCandleFacts &f)
  {
   SPatternResult r;
   r.pattern = QME_CANDLE_NONE;
   r.bias = QME_SIDE_NONE;
   r.quality = 0.0;
   r.valid = false;

   const double body = QmeCandleBody(c);
   const double range = QmeCandleRange(c);
   if(range <= QME_EPSILON) return(r);

   //--- bullish pin: long lower wick, close in the upper third
   if(f.lowerWickRatio >= 0.60 && f.closePos >= 0.66 &&
      (body <= QME_EPSILON || QmeCandleLowerWick(c) >= 2.0 * body))
     {
      r.pattern = QME_CANDLE_BULL_PIN;
      r.bias = QME_SIDE_BUY;
      r.quality = QmeClamp(f.lowerWickRatio, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   //--- bearish pin: long upper wick, close in the lower third
   if(f.upperWickRatio >= 0.60 && f.closePos <= 0.34 &&
      (body <= QME_EPSILON || QmeCandleUpperWick(c) >= 2.0 * body))
     {
      r.pattern = QME_CANDLE_BEAR_PIN;
      r.bias = QME_SIDE_SELL;
      r.quality = QmeClamp(f.upperWickRatio, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   return(r);
  }

//------------------------------------------------------------------//
SPatternResult CCandlePatternEngine::Shape(const SCandle &c, const SCandle &prev, const SCandleFacts &f)
  {
   SPatternResult r;
   r.pattern = QME_CANDLE_NONE;
   r.bias = QME_SIDE_NONE;
   r.quality = 0.0;
   r.valid = false;

   if(c.high > prev.high && c.low < prev.low)
     {
      r.pattern = QME_CANDLE_OUTSIDE_BAR;
      r.bias = QmeCandleIsBull(c) ? QME_SIDE_BUY : QME_SIDE_SELL;
      r.quality = QmeClamp(f.bodyRatio, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   if(c.high <= prev.high && c.low >= prev.low)
     {
      r.pattern = QME_CANDLE_INSIDE_BAR;
      r.bias = QME_SIDE_NONE;
      r.quality = 0.4;
      r.valid = true;
      return(r);
     }
   if(f.bodyRatio <= 0.10)
     {
      r.pattern = QME_CANDLE_DOJI;
      r.bias = QME_SIDE_NONE;
      r.quality = 0.3;
      r.valid = true;
      return(r);
     }
   if(f.displacement && f.bodyRatio >= 0.70)
     {
      if(QmeCandleIsBull(c))
        {
         r.pattern = QME_CANDLE_STRONG_BULL;
         r.bias = QME_SIDE_BUY;
        }
      else
        {
         r.pattern = QME_CANDLE_STRONG_BEAR;
         r.bias = QME_SIDE_SELL;
        }
      r.quality = QmeClamp(f.bodyRatio, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   //--- rejection: close in the outer quarter with a long opposite wick
   if(f.closePos >= 0.75 && f.lowerWickRatio >= 0.35)
     {
      r.pattern = QME_CANDLE_REJECTION_BULL;
      r.bias = QME_SIDE_BUY;
      r.quality = QmeClamp(f.lowerWickRatio + 0.3, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   if(f.closePos <= 0.25 && f.upperWickRatio >= 0.35)
     {
      r.pattern = QME_CANDLE_REJECTION_BEAR;
      r.bias = QME_SIDE_SELL;
      r.quality = QmeClamp(f.upperWickRatio + 0.3, 0.0, 1.0);
      r.valid = true;
      return(r);
     }
   return(r);
  }

//------------------------------------------------------------------//
SPatternResult CCandlePatternEngine::Detect(CBarSeries &series, const int shift,
                                            const double displacementMult)
  {
   SPatternResult none;
   none.pattern = QME_CANDLE_NONE;
   none.bias = QME_SIDE_NONE;
   none.quality = 0.0;
   none.valid = false;

   SCandle c, prev;
   if(!series.Get(shift, c) || !series.Get(shift + 1, prev)) return(none);

   SCandleFacts facts;
   if(!CCandleEngine::Evaluate(series, shift, facts, displacementMult)) return(none);

   //--- precedence: engulfing > pin > shape
   SPatternResult r = Engulfing(c, prev);
   if(r.valid) return(r);
   r = PinBar(c, facts);
   if(r.valid) return(r);
   return(Shape(c, prev, facts));
  }

#endif // __QME_ANALYSIS_CANDLEPATTERNMQH__
//+------------------------------------------------------------------+
