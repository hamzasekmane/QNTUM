//+------------------------------------------------------------------+
//|                                 Analysis/Liquidity/LiquidityMap   |
//|  Builds the liquidity map for one symbol/timeframe.                 |
//|                                                                   |
//|  OBSERVED vs INFERRED is explicit:                                  |
//|   observed = measured from bars (swing extremes, session high/low,   |
//|              previous day/week high/low, equal-high clusters)        |
//|   inferred = derived from price structure/psychology (round numbers) |
//|  Inferred levels get a lower strength and are flagged, so scoring     |
//|  can treat them differently.                                        |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_LIQUIDITYMAP_MQH__
#define __QME_ANALYSIS_LIQUIDITYMAP_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"
#include "PdhPdlEngine.mqh"
#include "EqualHighLow.mqh"
#include "SessionLiquidity.mqh"

class CLiquidityMapBuilder
  {
private:
   static bool       Add(SLiquidityMap &map, const double price, const ENUM_QME_SIDE side,
                         const bool observed, const double strength, const int touches,
                         const datetime birth, const ENUM_QME_ZONE_SOURCE source);
   static void       AddRoundNumbers(SLiquidityMap &map, const string symbol,
                                     const double referencePrice,
                                     const double rangeLow, const double rangeHigh,
                                     const double point);

public:
   static bool       Build(CBarSeries &series, const SStructureState &state,
                           const SPdhPdl &pdp, const SSessionLevels &session,
                           const double atr, const double price,
                           SLiquidityMap &out);

   //--- nearest level of a given side relative to a price
   static bool       NearestAbove(const SLiquidityMap &map, const double price,
                                  SLiquidityLevel &out);
   static bool       NearestBelow(const SLiquidityMap &map, const double price,
                                  SLiquidityLevel &out);
  };

//------------------------------------------------------------------//
bool CLiquidityMapBuilder::Add(SLiquidityMap &map, const double price, const ENUM_QME_SIDE side,
                               const bool observed, const double strength, const int touches,
                               const datetime birth, const ENUM_QME_ZONE_SOURCE source)
  {
   if(price <= 0.0 || side == QME_SIDE_NONE) return(false);
   if(map.count >= QME_MAX_LIQUIDITY_LEVELS) return(false);

   //--- merge with an existing level at (almost) the same price and side
   for(int i = 0; i < map.count; i++)
     {
      if(map.levels[i].side != side) continue;
      const double tol = MathMax(map.equalHighTolerance, QME_PRICE_EPS);
      if(MathAbs(map.levels[i].price - price) <= tol)
        {
         //--- corroboration increases strength but never beyond 1
         map.levels[i].strength = QmeClamp(map.levels[i].strength + 0.25 * strength, 0.0, 1.0);
         map.levels[i].touches += touches;
         map.levels[i].observed = map.levels[i].observed || observed;
         if(birth > map.levels[i].birthTime) map.levels[i].birthTime = birth;
         return(true);
        }
     }
   map.levels[map.count].price = price;
   map.levels[map.count].side = side;
   map.levels[map.count].observed = observed;
   map.levels[map.count].strength = QmeClamp(strength, 0.0, 1.0);
   map.levels[map.count].touches = touches;
   map.levels[map.count].birthTime = birth;
   map.levels[map.count].source = source;
   map.count++;
   return(true);
  }

//------------------------------------------------------------------//
void CLiquidityMapBuilder::AddRoundNumbers(SLiquidityMap &map, const string symbol,
                                           const double referencePrice,
                                           const double rangeLow, const double rangeHigh,
                                           const double point)
  {
   if(point <= 0.0 || rangeHigh <= rangeLow) return;
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   //--- step: 100 pips on 4/5-digit quotes, 1.00 on 2-digit quotes (metals,
   //--- indices), otherwise 1000 points
   double step = 100.0 * point;
   if(digits <= 2) step = 1.0;
   if(digits == 3) step = 10.0 * point;
   if(step <= 0.0) return;

   const double first = MathCeil(rangeLow / step) * step;
   for(double p = first; p <= rangeHigh && map.count < QME_MAX_LIQUIDITY_LEVELS; p += step)
     {
      //--- a round number above the current price is buy-side resting liquidity,
      //--- below it is sell-side. These are INFERRED, not observed.
      const ENUM_QME_SIDE side = (p > referencePrice) ? QME_SIDE_BUY : QME_SIDE_SELL;
      Add(map, p, side, false /*inferred*/, 0.20, 1, 0, QME_ZONE_SRC_LIQUIDITY);
     }
  }

//------------------------------------------------------------------//
bool CLiquidityMapBuilder::Build(CBarSeries &series, const SStructureState &state,
                                 const SPdhPdl &pdp, const SSessionLevels &session,
                                 const double atr, const double price,
                                 SLiquidityMap &out)
  {
   QmeLiquidityReset(out);
   if(!series.IsValid()) return(false);

   out.equalHighTolerance = MathMax(atr * 0.10, QME_PRICE_EPS);
   out.rangeHigh = series.Highest(0, 50);
   out.rangeLow  = series.Lowest(0, 50);
   out.pdh = pdp.pdh; out.pdl = pdp.pdl;
   out.pwh = pdp.pwh; out.pwl = pdp.pwl;
   out.sessionHigh = session.high;
   out.sessionLow = session.low;

   //--- confirmed swing extremes are observed liquidity
   if(state.valid)
     {
      for(int i = 0; i < state.swingCount; i++)
        {
         const SStructurePoint p = state.swings[i];
         const ENUM_QME_SIDE side = p.isHigh ? QME_SIDE_BUY : QME_SIDE_SELL;
         Add(out, p.price, side, true, 0.30 + 0.30 * p.strength, 1, p.time,
             QME_ZONE_SRC_LIQUIDITY);
        }

      //--- equal highs/lows: strongest resting pools
      SEqualCluster clusters[];
      const int n = CEqualHighLow::Detect(state.swings, state.swingCount, atr, 0.10,
                                          SymbolInfoDouble(series.Symbol(), SYMBOL_POINT),
                                          16, clusters);
      for(int i = 0; i < n; i++)
        {
         const ENUM_QME_SIDE side = clusters[i].isHigh ? QME_SIDE_BUY : QME_SIDE_SELL;
         const double strength = QmeClamp(0.40 + 0.15 * clusters[i].touches, 0.0, 1.0);
         Add(out, clusters[i].price, side, true, strength, clusters[i].touches,
             clusters[i].newest, QME_ZONE_SRC_LIQUIDITY);
        }
     }

   //--- previous day / week extremes (observed, high importance)
   if(pdp.dayValid)
     {
      Add(out, pdp.pdh, QME_SIDE_BUY, true, 0.70, 1, pdp.dayBarTime, QME_ZONE_SRC_PDH_PDL);
      Add(out, pdp.pdl, QME_SIDE_SELL, true, 0.70, 1, pdp.dayBarTime, QME_ZONE_SRC_PDH_PDL);
     }
   if(pdp.weekValid)
     {
      Add(out, pdp.pwh, QME_SIDE_BUY, true, 0.80, 1, pdp.weekBarTime, QME_ZONE_SRC_PDH_PDL);
      Add(out, pdp.pwl, QME_SIDE_SELL, true, 0.80, 1, pdp.weekBarTime, QME_ZONE_SRC_PDH_PDL);
     }

   //--- session highs/lows (observed)
   if(session.valid)
     {
      Add(out, session.high, QME_SIDE_BUY, true, 0.45, 1, session.sessionStart,
          QME_ZONE_SRC_SESSION_RANGE);
      Add(out, session.low, QME_SIDE_SELL, true, 0.45, 1, session.sessionStart,
          QME_ZONE_SRC_SESSION_RANGE);
     }

   //--- inferred psychological levels
   AddRoundNumbers(out, series.Symbol(), price, out.rangeLow, out.rangeHigh,
                   SymbolInfoDouble(series.Symbol(), SYMBOL_POINT));

   out.valid = (out.count > 0);
   return(out.valid);
  }

//------------------------------------------------------------------//
bool CLiquidityMapBuilder::NearestAbove(const SLiquidityMap &map, const double price,
                                        SLiquidityLevel &out)
  {
   bool found = false;
   double best = DBL_MAX;
   for(int i = 0; i < map.count; i++)
     {
      if(map.levels[i].price <= price + QME_PRICE_EPS) continue;
      if(map.levels[i].price < best)
        {
         best = map.levels[i].price;
         out = map.levels[i];
         found = true;
        }
     }
   return(found);
  }

//------------------------------------------------------------------//
bool CLiquidityMapBuilder::NearestBelow(const SLiquidityMap &map, const double price,
                                        SLiquidityLevel &out)
  {
   bool found = false;
   double best = -DBL_MAX;
   for(int i = 0; i < map.count; i++)
     {
      if(map.levels[i].price >= price - QME_PRICE_EPS) continue;
      if(map.levels[i].price > best)
        {
         best = map.levels[i].price;
         out = map.levels[i];
         found = true;
        }
     }
   return(found);
  }

#endif // __QME_ANALYSIS_LIQUIDITYMAP_MQH__
//+------------------------------------------------------------------+
