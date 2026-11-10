//+------------------------------------------------------------------+
//|                                            Zones/ZoneRanking      |
//|  Ranked, explainable zone score in [0,1]:                          |
//|    0.35 * strength  + 0.25 * confidence                            |
//|  + 0.20 * freshness + 0.20 * proximity                            |
//|  Freshness decays linearly over the zone lifetime; proximity is       |
//|  1 - distance/ATR capped at `maxDistAtr`.                            |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONERANKING_MQH__
#define __QME_ZONES_ZONERANKING_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "ZoneValidator.mqh"

class CZoneRanking
  {
public:
   static double     Score(const STradingZone &z, const double price, const double atr,
                           const datetime now, const double maxDistAtr = 3.0);
   static double     Freshness(const STradingZone &z, const datetime now);
   //--- descending insertion sort of a struct array (MQL5 ArraySort only
   //--- sorts numeric arrays, so ordering is explicit here)
   static void       SortByScore(STradingZone &zones[], const int count,
                                 const double price, const double atr, const datetime now);
  };

//------------------------------------------------------------------//
double CZoneRanking::Freshness(const STradingZone &z, const datetime now)
  {
   if(z.created <= 0) return(0.5);
   if(z.expires <= z.created) return(0.5);
   const double total = (double)(z.expires - z.created);
   const double used = (double)(now - z.created);
   if(used <= 0.0) return(1.0);
   return(QmeClamp(1.0 - used / total, 0.0, 1.0));
  }

//------------------------------------------------------------------//
double CZoneRanking::Score(const STradingZone &z, const double price, const double atr,
                           const datetime now, const double maxDistAtr)
  {
   if(z.state == QME_ZSTAT_INVALIDATED || z.state == QME_ZSTAT_EXPIRED) return(0.0);

   const double dist = CZoneValidator::DistanceAtr(z, price, atr);
   double proximity = 0.0;
   if(maxDistAtr > 0.0 && dist < DBL_MAX)
      proximity = QmeClamp(1.0 - dist / maxDistAtr, 0.0, 1.0);

   const double s = 0.35 * QmeClamp(z.strength, 0.0, 1.0) +
                    0.25 * QmeClamp(z.confidence, 0.0, 1.0) +
                    0.20 * Freshness(z, now) +
                    0.20 * proximity;
   return(QmeClamp(s, 0.0, 1.0));
  }

//------------------------------------------------------------------//
void CZoneRanking::SortByScore(STradingZone &zones[], const int count,
                               const double price, const double atr, const datetime now)
  {
   if(count <= 1) return;
   double scores[];
   ArrayResize(scores, count);
   for(int i = 0; i < count; i++)
      scores[i] = Score(zones[i], price, atr, now);

   //--- selection sort, descending (counts are small: <= board capacity)
   for(int i = 0; i < count - 1; i++)
     {
      int best = i;
      for(int j = i + 1; j < count; j++)
         if(scores[j] > scores[best]) best = j;
      if(best == i) continue;
      const double ts = scores[i]; scores[i] = scores[best]; scores[best] = ts;
      const STradingZone tz = zones[i]; zones[i] = zones[best]; zones[best] = tz;
     }
  }

#endif // __QME_ZONES_ZONERANKING_MQH__
//+------------------------------------------------------------------+
