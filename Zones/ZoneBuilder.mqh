//+------------------------------------------------------------------+
//|                                            Zones/ZoneBuilder      |
//|  Converts analytical evidence into STradingZone records.            |
//|                                                                   |
//|  Every builder sets: identity, symbol, timeframe, side, boundaries,  |
//|  creation time, source, strength, confidence, invalidation level     |
//|  and expiration. A zone with no invalidation level is never emitted. |
//+------------------------------------------------------------------+
#ifndef __QME_ZONE_BUILDER_MQH__
#define __QME_ZONE_BUILDER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "ZoneIdentity.mqh"
#include "ZoneTypes.mqh"

class CZoneBuilder
  {
private:
   static bool       Finalize(STradingZone &z, const string symbol, const ENUM_TIMEFRAMES tf,
                              const double point, const double atr, const datetime now,
                              const int maxAgeHours);

public:
   static int        FromOrderBlocks(const string symbol, const ENUM_TIMEFRAMES tf,
                                     const SOrderBlockRecord &obs[], const int count,
                                     const double point, const double atr, const datetime now,
                                     const int maxAgeHours, const int maxOut,
                                     STradingZone &out[]);

   static int        FromFvgs(const string symbol, const ENUM_TIMEFRAMES tf,
                              const SFvgRecord &gaps[], const int count,
                              const double point, const double atr, const datetime now,
                              const int maxAgeHours, const int maxOut,
                              STradingZone &out[]);

   static int        FromLiquidity(const string symbol, const ENUM_TIMEFRAMES tf,
                                   const SLiquidityMap &map, const double point,
                                   const double atr, const datetime now,
                                   const int maxAgeHours, const int maxOut,
                                   STradingZone &out[]);

   static int        FromSwingRange(const string symbol, const ENUM_TIMEFRAMES tf,
                                    const SStructureState &state, const double point,
                                    const double atr, const datetime now,
                                    const int maxAgeHours, STradingZone &out[]);

   static int        FromVolumeProfile(const string symbol, const ENUM_TIMEFRAMES tf,
                                       const SVolumeProfile &profile, const double point,
                                       const double atr, const datetime now,
                                       const int maxAgeHours, const int maxOut,
                                       STradingZone &out[]);
  };

//------------------------------------------------------------------//
bool CZoneBuilder::Finalize(STradingZone &z, const string symbol, const ENUM_TIMEFRAMES tf,
                            const double point, const double atr, const datetime now,
                            const int maxAgeHours)
  {
   z.symbol = symbol;
   z.tf = tf;
   if(!QmeZoneNormalise(z)) return(false);

   //--- ignore zones thinner than a small fraction of ATR: pure noise
   const double minHeight = MathMax(atr * 0.05, point * 5.0);
   if(QmeZoneHeight(z) < minHeight) return(false);

   if(z.side == QME_SIDE_NONE) return(false);
   z.created = (z.created > 0) ? z.created : now;
   z.id = CZoneIdentity::Make(symbol, tf, z.side, z.source, z.lower, z.upper, point);
   if(z.id == 0) return(false);

   if(z.invalidateLevel <= 0.0)
      z.invalidateLevel = QmeZoneDefaultInvalidation(z, atr);
   if(z.expires <= 0 && maxAgeHours > 0)
      z.expires = z.created + (datetime)(maxAgeHours * 3600);

   z.state = QME_ZSTAT_FRESH;
   z.strength = QmeClamp(z.strength, 0.0, 1.0);
   z.confidence = QmeClamp(z.confidence, 0.0, 1.0);
   return(true);
  }

//------------------------------------------------------------------//
int CZoneBuilder::FromOrderBlocks(const string symbol, const ENUM_TIMEFRAMES tf,
                                  const SOrderBlockRecord &obs[], const int count,
                                  const double point, const double atr, const datetime now,
                                  const int maxAgeHours, const int maxOut,
                                  STradingZone &out[])
  {
   ArrayResize(out, 0);
   for(int i = 0; i < count && ArraySize(out) < maxOut; i++)
     {
      if(obs[i].mitigated) continue;   // a mitigated block is not fresh supply/demand
      STradingZone z;
      QmeZoneClear(z);
      z.side = obs[i].side;
      z.source = QME_ZONE_SRC_ORDER_BLOCK;
      z.lower = obs[i].lower;
      z.upper = obs[i].upper;
      z.created = obs[i].time;
      z.strength = QmeClamp(0.55 + 0.40 * obs[i].displacement, 0.0, 1.0);
      z.confidence = 0.60;
      z.factorMask = CFactorCatalog::Bit(QME_F_ORDER_BLOCK);
      if(!Finalize(z, symbol, tf, point, atr, now, maxAgeHours)) continue;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = z;
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
int CZoneBuilder::FromFvgs(const string symbol, const ENUM_TIMEFRAMES tf,
                           const SFvgRecord &gaps[], const int count,
                           const double point, const double atr, const datetime now,
                           const int maxAgeHours, const int maxOut,
                           STradingZone &out[])
  {
   ArrayResize(out, 0);
   for(int i = 0; i < count && ArraySize(out) < maxOut; i++)
     {
      if(gaps[i].filled) continue;
      //--- a gap more than 85% filled has effectively been rebalanced
      if(gaps[i].fillRatio >= 0.85) continue;

      STradingZone z;
      QmeZoneClear(z);
      z.side = gaps[i].side;
      z.source = QME_ZONE_SRC_FVG;
      z.lower = gaps[i].lower;
      z.upper = gaps[i].upper;
      z.created = gaps[i].time;
      z.strength = QmeClamp(0.80 - 0.5 * gaps[i].fillRatio, 0.0, 1.0);
      z.confidence = 0.55;
      z.factorMask = CFactorCatalog::Bit(QME_F_FVG);
      if(!Finalize(z, symbol, tf, point, atr, now, maxAgeHours)) continue;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = z;
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
int CZoneBuilder::FromLiquidity(const string symbol, const ENUM_TIMEFRAMES tf,
                                const SLiquidityMap &map, const double point,
                                const double atr, const datetime now,
                                const int maxAgeHours, const int maxOut,
                                STradingZone &out[])
  {
   ArrayResize(out, 0);
   const double halfHeight = MathMax(atr * 0.15, point * 5.0);

   for(int i = 0; i < map.count && ArraySize(out) < maxOut; i++)
     {
      //--- only observed pools with real strength become zones
      if(!map.levels[i].observed) continue;
      if(map.levels[i].strength < 0.45) continue;

      STradingZone z;
      QmeZoneClear(z);
      z.source = (map.levels[i].source == QME_ZONE_SRC_PDH_PDL) ?
                 QME_ZONE_SRC_PDH_PDL : QME_ZONE_SRC_LIQUIDITY;
      //--- a buy-side pool attracts price from below: it behaves as supply
      //--- resistance from above and as a target from below; the zone side is
      //--- set to the side the POOL defends.
      z.side = (map.levels[i].side == QME_SIDE_BUY) ? QME_SIDE_SELL : QME_SIDE_BUY;
      z.lower = map.levels[i].price - halfHeight;
      z.upper = map.levels[i].price + halfHeight;
      z.created = (map.levels[i].birthTime > 0) ? map.levels[i].birthTime : now;
      z.strength = QmeClamp(0.35 + 0.55 * map.levels[i].strength, 0.0, 1.0);
      z.confidence = 0.50;
      z.factorMask = CFactorCatalog::Bit(QME_F_LIQUIDITY);
      if(!Finalize(z, symbol, tf, point, atr, now, maxAgeHours)) continue;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = z;
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
int CZoneBuilder::FromSwingRange(const string symbol, const ENUM_TIMEFRAMES tf,
                                 const SStructureState &state, const double point,
                                 const double atr, const datetime now,
                                 const int maxAgeHours, STradingZone &out[])
  {
   ArrayResize(out, 0);
   if(!state.valid) return(0);
   const double halfHeight = MathMax(atr * 0.12, point * 4.0);

   if(state.lastSwingHigh > 0.0)
     {
      STradingZone z;
      QmeZoneClear(z);
      z.side = QME_SIDE_SELL;
      z.source = QME_ZONE_SRC_SUPPORT_RESISTANCE;
      z.lower = state.lastSwingHigh - halfHeight;
      z.upper = state.lastSwingHigh + halfHeight;
      z.created = state.lastSwingHighTime;
      z.strength = 0.55;
      z.confidence = 0.45;
      z.factorMask = CFactorCatalog::Bit(QME_F_STRUCTURE);
      if(Finalize(z, symbol, tf, point, atr, now, maxAgeHours))
        {
         const int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = z;
        }
     }
   if(state.lastSwingLow > 0.0)
     {
      STradingZone z;
      QmeZoneClear(z);
      z.side = QME_SIDE_BUY;
      z.source = QME_ZONE_SRC_SUPPORT_RESISTANCE;
      z.lower = state.lastSwingLow - halfHeight;
      z.upper = state.lastSwingLow + halfHeight;
      z.created = state.lastSwingLowTime;
      z.strength = 0.55;
      z.confidence = 0.45;
      z.factorMask = CFactorCatalog::Bit(QME_F_STRUCTURE);
      if(Finalize(z, symbol, tf, point, atr, now, maxAgeHours))
        {
         const int n = ArraySize(out);
         ArrayResize(out, n + 1);
         out[n] = z;
        }
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
int CZoneBuilder::FromVolumeProfile(const string symbol, const ENUM_TIMEFRAMES tf,
                                    const SVolumeProfile &profile, const double point,
                                    const double atr, const datetime now,
                                    const int maxAgeHours, const int maxOut,
                                    STradingZone &out[])
  {
   ArrayResize(out, 0);
   if(!profile.valid) return(0);

   for(int i = 0; i < profile.nodeCount && ArraySize(out) < maxOut; i++)
     {
      if(!profile.nodes[i].highNode) continue;
      STradingZone z;
      QmeZoneClear(z);
      //--- high-volume nodes are two-sided: use the current price side later.
      //--- By default, a node ABOVE the POC acts as supply, below as demand.
      z.side = (profile.nodes[i].mid > profile.poc) ? QME_SIDE_SELL : QME_SIDE_BUY;
      z.source = QME_ZONE_SRC_VOLUME_PROFILE;
      z.lower = profile.nodes[i].priceLow;
      z.upper = profile.nodes[i].priceHigh;
      z.created = now;
      z.strength = QmeClamp(0.30 + 0.50 * profile.nodes[i].share * (double)profile.nodeCount, 0.0, 1.0);
      z.confidence = 0.35;
      z.factorMask = CFactorCatalog::Bit(QME_F_PREMIUM_DISCOUNT);
      if(!Finalize(z, symbol, tf, point, atr, now, maxAgeHours)) continue;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = z;
     }
   return(ArraySize(out));
  }

#endif // __QME_ZONE_BUILDER_MQH__
//+------------------------------------------------------------------+
