//+------------------------------------------------------------------+
//|                                           Zones/ZoneIdentity      |
//|  Deterministic zone identity.                                       |
//|                                                                   |
//|  A zone id must be STABLE for the same market fact across restarts   |
//|  (so persisted state can be reconciled) and DIFFERENT for distinct   |
//|  facts. It is built from symbol, timeframe, side, source and the      |
//|  price bucket, never from a random number or an array index.         |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONEIDENTITY_MQH__
#define __QME_ZONES_ZONEIDENTITY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

class CZoneIdentity
  {
public:
   //--- price bucketed to a fraction of the zone height (avoids float noise)
   static long       Bucket(const double price, const double point, const int bucketPoints);
   static string     Key(const string symbol, const ENUM_TIMEFRAMES tf,
                         const ENUM_QME_SIDE side, const ENUM_QME_ZONE_SOURCE src,
                         const double lower, const double upper, const double point);
   static ulong      Make(const string symbol, const ENUM_TIMEFRAMES tf,
                          const ENUM_QME_SIDE side, const ENUM_QME_ZONE_SOURCE src,
                          const double lower, const double upper, const double point);
  };

//------------------------------------------------------------------//
long CZoneIdentity::Bucket(const double price, const double point, const int bucketPoints)
  {
   if(point <= 0.0) return((long)MathRound(price * 100000.0));
   const double bucketPrice = MathMax(point * (double)MathMax(bucketPoints, 1), QME_PRICE_EPS);
   return((long)MathRound(price / bucketPrice));
  }

//------------------------------------------------------------------//
string CZoneIdentity::Key(const string symbol, const ENUM_TIMEFRAMES tf,
                          const ENUM_QME_SIDE side, const ENUM_QME_ZONE_SOURCE src,
                          const double lower, const double upper, const double point)
  {
   const long lo = Bucket(lower, point, 5);
   const long hi = Bucket(upper, point, 5);
   return(symbol + ":" + QmeTimeframeName(tf) + ":" + IntegerToString((int)side) + ":" +
          IntegerToString((int)src) + ":" + IntegerToString(lo) + ":" + IntegerToString(hi));
  }

//------------------------------------------------------------------//
ulong CZoneIdentity::Make(const string symbol, const ENUM_TIMEFRAMES tf,
                          const ENUM_QME_SIDE side, const ENUM_QME_ZONE_SOURCE src,
                          const double lower, const double upper, const double point)
  {
   ulong h = QmeHashString(Key(symbol, tf, side, src, lower, upper, point));
   //--- never return 0: 0 means "no zone" throughout the engine
   if(h == 0) h = 1;
   return(h);
  }

#endif // __QME_ZONES_ZONEIDENTITY_MQH__
//+------------------------------------------------------------------+
