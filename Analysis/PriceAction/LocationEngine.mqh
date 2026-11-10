//+------------------------------------------------------------------+
//|                                Analysis/PriceAction/LocationEngine|
//|  "Where is price right now?" — the locational context that decides    |
//|  whether a setup is worth taking.                                   |
//|                                                                   |
//|  Evaluates: position inside the dealing range (premium/discount),   |
//|  distance to the nearest liquidity pool on each side, and distance   |
//|  to the structural extremes. All distances are in ATR units so they  |
//|  are comparable across instruments.                                 |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_LOCATIONENGINE_MQH__
#define __QME_ANALYSIS_LOCATIONENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "PremiumDiscountEngine.mqh"
#include "../Liquidity/LiquidityMap.mqh"

struct SLocationResult
  {
   double            price;
   double            rangePosition;      // 0 = range low, 1 = range high
   bool              premium;
   bool              discount;
   double            distToBuySideAtr;    // nearest pool above
   double            distToSellSideAtr;  // nearest pool below
   bool              hasBuySide;
   bool              hasSellSide;
   double            distToRangeHighAtr;
   double            distToRangeLowAtr;
   bool              nearLiquidity;      // either side within nearAtr
   bool              atExtreme;          // within nearAtr of a range extreme
   bool              valid;
  };

class CLocationEngine
  {
public:
   static SLocationResult Evaluate(const double price, const double atr,
                                   const SRangeContext &range,
                                   const SLiquidityMap &liquidity,
                                   const double nearAtr = 0.5);
  };

//------------------------------------------------------------------//
SLocationResult CLocationEngine::Evaluate(const double price, const double atr,
                                          const SRangeContext &range,
                                          const SLiquidityMap &liquidity,
                                          const double nearAtr)
  {
   SLocationResult r;
   r.price = price;
   r.rangePosition = range.valid ? range.position : 0.5;
   r.premium = range.valid ? range.premium : false;
   r.discount = range.valid ? range.discount : false;
   r.distToBuySideAtr = 0.0;
   r.distToSellSideAtr = 0.0;
   r.hasBuySide = false;
   r.hasSellSide = false;
   r.distToRangeHighAtr = 0.0;
   r.distToRangeLowAtr = 0.0;
   r.nearLiquidity = false;
   r.atExtreme = false;
   r.valid = false;

   if(price <= 0.0 || atr <= QME_EPSILON) return(r);

   SLiquidityLevel lv;
   if(CLiquidityMapBuilder::NearestAbove(liquidity, price, lv))
     {
      r.hasBuySide = true;
      r.distToBuySideAtr = (lv.price - price) / atr;
     }
   if(CLiquidityMapBuilder::NearestBelow(liquidity, price, lv))
     {
      r.hasSellSide = true;
      r.distToSellSideAtr = (price - lv.price) / atr;
     }

   if(range.valid)
     {
      r.distToRangeHighAtr = (range.rangeHigh - price) / atr;
      r.distToRangeLowAtr = (price - range.rangeLow) / atr;
      r.atExtreme = (r.distToRangeHighAtr <= nearAtr) || (r.distToRangeLowAtr <= nearAtr);
     }

   r.nearLiquidity = (r.hasBuySide && r.distToBuySideAtr <= nearAtr) ||
                     (r.hasSellSide && r.distToSellSideAtr <= nearAtr);
   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_LOCATIONENGINE_MQH__
//+------------------------------------------------------------------+
