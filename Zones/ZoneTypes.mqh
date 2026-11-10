//+------------------------------------------------------------------+
//|                                             Zones/ZoneTypes       |
//|  Zone-local definitions only.                                      |
//|                                                                   |
//|  The canonical zone RECORD (STradingZone) and the zone enumerations  |
//|  live in Core/Types.mqh and Core/Enums.mqh — there is deliberately    |
//|  ONE definition of a zone in this project. This file adds geometry,   |
//|  source priority and the lifecycle transition table.                 |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONETYPES_MQH__
#define __QME_ZONES_ZONETYPES_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

//--- used when deciding which source survives a merge
int QmeZoneSourcePriority(const ENUM_QME_ZONE_SOURCE s)
  {
   switch(s)
     {
      case QME_ZONE_SRC_ORDER_BLOCK:        return(90);
      case QME_ZONE_SRC_FVG:                return(80);
      case QME_ZONE_SRC_PDH_PDL:            return(75);
      case QME_ZONE_SRC_LIQUIDITY:          return(70);
      case QME_ZONE_SRC_VOLUME_PROFILE:     return(60);
      case QME_ZONE_SRC_SUPPORT_RESISTANCE: return(55);
      case QME_ZONE_SRC_SESSION_RANGE:      return(45);
      case QME_ZONE_SRC_PREMIUM_DISCOUNT:   return(40);
     }
   return(0);
  }

//--- default invalidation level: a stop-run distance beyond the zone
double QmeZoneDefaultInvalidation(const STradingZone &z, const double atr,
                                  const double bufferAtr = 0.35)
  {
   const double buffer = MathMax(atr * bufferAtr, QME_PRICE_EPS);
   const double lo = MathMin(z.upper, z.lower);
   const double hi = MathMax(z.upper, z.lower);
   if(z.side == QME_SIDE_BUY)  return(lo - buffer);   // demand dies below
   if(z.side == QME_SIDE_SELL) return(hi + buffer);   // supply dies above
   return(0.0);
  }

//--- normalise a zone so upper >= lower and the geometry is sane
bool QmeZoneNormalise(STradingZone &z)
  {
   if(z.upper < z.lower)
     {
      const double t = z.upper;
      z.upper = z.lower;
      z.lower = t;
     }
   if(z.upper <= 0.0 || z.lower <= 0.0) return(false);
   if(z.upper - z.lower < QME_PRICE_EPS) return(false);
   return(true);
  }

//--- lifecycle transition table (explicit, used by CZoneLifecycle)
bool QmeZoneTransitionAllowed(const ENUM_QME_ZONE_STATE from, const ENUM_QME_ZONE_STATE to)
  {
   if(from == QME_ZSTAT_INVALIDATED || from == QME_ZSTAT_EXPIRED) return(false); // terminal
   switch(from)
     {
      case QME_ZSTAT_FRESH:
         return(to == QME_ZSTAT_TESTED || to == QME_ZSTAT_MITIGATED ||
                to == QME_ZSTAT_INVALIDATED || to == QME_ZSTAT_EXPIRED);
      case QME_ZSTAT_TESTED:
         return(to == QME_ZSTAT_MITIGATED || to == QME_ZSTAT_TESTED ||
                to == QME_ZSTAT_INVALIDATED || to == QME_ZSTAT_EXPIRED);
      case QME_ZSTAT_MITIGATED:
         return(to == QME_ZSTAT_INVALIDATED || to == QME_ZSTAT_EXPIRED);
     }
   return(false);
  }

#endif // __QME_ZONES_ZONETYPES_MQH__
//+------------------------------------------------------------------+
