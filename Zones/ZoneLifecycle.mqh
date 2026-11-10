//+------------------------------------------------------------------+
//|                                          Zones/ZoneLifecycle      |
//|  Advances a zone through FRESH -> TESTED -> MITIGATED and terminal    |
//|  INVALIDATED / EXPIRED. Every transition is checked against the       |
//|  transition table, so a terminal state can never be revived.          |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONELIFECYCLE_MQH__
#define __QME_ZONES_ZONELIFECYCLE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Data/BarSeries.mqh"
#include "ZoneTypes.mqh"
#include "ZoneValidator.mqh"

class CZoneLifecycle
  {
private:
   static void       MoveTo(STradingZone &z, const ENUM_QME_ZONE_STATE to, const datetime now);

public:
   //--- update using the most recent closed bar only (no intrabar assumptions)
   static void       Update(STradingZone &z, CBarSeries &series, const datetime now,
                            const double atr, const double point);
  };

//------------------------------------------------------------------//
void CZoneLifecycle::MoveTo(STradingZone &z, const ENUM_QME_ZONE_STATE to, const datetime now)
  {
   if(z.state == to) return;
   if(!QmeZoneTransitionAllowed(z.state, to)) return;
   z.state = to;
   z.lastTouched = (now > 0) ? now : z.lastTouched;
  }

//------------------------------------------------------------------//
void CZoneLifecycle::Update(STradingZone &z, CBarSeries &series, const datetime now,
                            const double atr, const double point)
  {
   //--- terminal states never change
   if(z.state == QME_ZSTAT_INVALIDATED || z.state == QME_ZSTAT_EXPIRED) return;

   //--- time expiry first
   if(CZoneValidator::IsExpired(z, now))
     {
      MoveTo(z, QME_ZSTAT_EXPIRED, now);
      return;
     }

   SCandle newest;
   if(!series.Get(0, newest)) return;

   //--- price invalidation
   if(CZoneValidator::IsPriceInvalidated(z, newest.close, atr))
     {
      MoveTo(z, QME_ZSTAT_INVALIDATED, now);
      return;
     }

   const double lo = MathMin(z.upper, z.lower);
   const double hi = MathMax(z.upper, z.lower);

   //--- touched by the newest closed bar?
   if(newest.high >= lo - QME_PRICE_EPS && newest.low <= hi + QME_PRICE_EPS)
     {
      z.touches++;
      if(z.state == QME_ZSTAT_FRESH)
         MoveTo(z, QME_ZSTAT_TESTED, now);
     }

   //--- mitigated: price closed beyond the far edge of the zone
   //--- (demand consumed by trading below it, supply consumed above it)
   if(z.side == QME_SIDE_BUY && newest.close < lo - QME_PRICE_EPS)
      MoveTo(z, QME_ZSTAT_MITIGATED, now);
   else if(z.side == QME_SIDE_SELL && newest.close > hi + QME_PRICE_EPS)
      MoveTo(z, QME_ZSTAT_MITIGATED, now);

   //--- freshness decays touched zones slightly, but strength never grows
   if(z.state == QME_ZSTAT_TESTED && z.touches > 3)
      z.strength = QmeClamp(z.strength * 0.98, 0.0, 1.0);
  }

#endif // __QME_ZONES_ZONELIFECYCLE_MQH__
//+------------------------------------------------------------------+
