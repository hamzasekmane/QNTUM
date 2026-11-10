//+------------------------------------------------------------------+
//|                                          Zones/ZoneValidator      |
//|  Structural validity + invalidation rules for zones.                |
//|                                                                   |
//|  A zone is only usable when it is geometrically sane, not expired,    |
//|  and price has not already violated its invalidation level.           |
//|  Invalidated zones are never deleted silently: the state is set and   |
//|  the board keeps them until retention removes them.                   |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONEVALIDATOR_MQH__
#define __QME_ZONES_ZONEVALIDATOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "ZoneTypes.mqh"

class CZoneValidator
  {
public:
   static bool       IsValid(const STradingZone &z, const double point, const datetime now,
                             string &why);
   static bool       IsPriceInvalidated(const STradingZone &z, const double close,
                                        const double atr);
   static bool       IsExpired(const STradingZone &z, const datetime now);
   static double     AgeHours(const STradingZone &z, const datetime now);
   static double     DistanceAtr(const STradingZone &z, const double price, const double atr);
  };

//------------------------------------------------------------------//
bool CZoneValidator::IsValid(const STradingZone &z, const double point, const datetime now,
                             string &why)
  {
   why = "";
   if(z.id == 0) { why = "missing identity"; return(false); }
   if(StringLen(z.symbol) == 0) { why = "missing symbol"; return(false); }
   if(z.side == QME_SIDE_NONE) { why = "missing side"; return(false); }
   if(z.upper <= 0.0 || z.lower <= 0.0) { why = "non-positive boundary"; return(false); }
   if(z.upper <= z.lower) { why = "upper <= lower"; return(false); }
   if(z.upper - z.lower < MathMax(point, QME_PRICE_EPS)) { why = "degenerate height"; return(false); }
   if(z.invalidateLevel <= 0.0) { why = "missing invalidation level"; return(false); }
   if(z.state == QME_ZSTAT_INVALIDATED) { why = "already invalidated"; return(false); }
   if(z.state == QME_ZSTAT_EXPIRED) { why = "already expired"; return(false); }
   if(z.expires > 0 && now > z.expires) { why = "expired by time"; return(false); }
   return(true);
  }

//------------------------------------------------------------------//
bool CZoneValidator::IsPriceInvalidated(const STradingZone &z, const double close,
                                        const double atr)
  {
   if(close <= 0.0) return(false);
   if(z.invalidateLevel <= 0.0) return(false);

   if(z.side == QME_SIDE_BUY)
      return(close < z.invalidateLevel - QME_PRICE_EPS);
   if(z.side == QME_SIDE_SELL)
      return(close > z.invalidateLevel + QME_PRICE_EPS);
   return(false);
  }

//------------------------------------------------------------------//
bool CZoneValidator::IsExpired(const STradingZone &z, const datetime now)
  {
   return(z.expires > 0 && now > z.expires);
  }

//------------------------------------------------------------------//
double CZoneValidator::AgeHours(const STradingZone &z, const datetime now)
  {
   if(z.created <= 0 || now <= z.created) return(0.0);
   return((double)(now - z.created) / 3600.0);
  }

//------------------------------------------------------------------//
double CZoneValidator::DistanceAtr(const STradingZone &z, const double price, const double atr)
  {
   if(atr <= QME_EPSILON || price <= 0.0) return(DBL_MAX);
   const double lo = MathMin(z.upper, z.lower);
   const double hi = MathMax(z.upper, z.lower);
   if(price >= lo && price <= hi) return(0.0);
   const double d = (price > hi) ? (price - hi) : (lo - price);
   return(d / atr);
  }

#endif // __QME_ZONES_ZONEVALIDATOR_MQH__
//+------------------------------------------------------------------+
