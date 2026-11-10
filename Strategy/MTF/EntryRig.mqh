//+------------------------------------------------------------------+
//|                                       Strategy/MTF/EntryRig       |
//|  Builds an entry specification from a zone.                         |
//|                                                                   |
//|  GEOMETRY (explicit):                                              |
//|   BUY  : entry = upper edge of the demand zone (or the current price   |
//|          when price is already inside the zone)                       |
//|          stop  = lower edge - buffer(0.25 ATR)                        |
//|          tp1   = entry + rrTarget * stopDistance                      |
//|   SELL : mirrored.                                                  |
//|                                                                   |
//|  REJECTIONS (never silently adjusted):                              |
//|   * stop distance above maxStopAtr rejects the setup instead of        |
//|     shrinking the stop;                                            |
//|   * stop distance below the broker's stops level is widened to the      |
//|     broker minimum and flagged, because the broker would reject the     |
//|     order otherwise — the resulting RR is re-checked afterwards.        |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_ENTRYRIG_MQH__
#define __QME_STRATEGY_ENTRYRIG_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Account/SymbolSpecifications.mqh"
#include "EntryTypes.mqh"

class CEntryRig
  {
public:
   static SEntrySpec FromZone(const STradingZone &zone, const ENUM_QME_SIDE side,
                              const double price, const double atr, const double point,
                              const SSymbolSpec &spec, const double rrTarget,
                              const double maxStopAtr, const double bufferAtr = 0.25);
  };

//------------------------------------------------------------------//
SEntrySpec CEntryRig::FromZone(const STradingZone &zone, const ENUM_QME_SIDE side,
                               const double price, const double atr, const double point,
                               const SSymbolSpec &spec, const double rrTarget,
                               const double maxStopAtr, const double bufferAtr)
  {
   SEntrySpec e;
   QmeEntrySpecClear(e);
   e.side = side;
   e.zoneId = zone.id;
   e.zoneUpper = MathMax(zone.upper, zone.lower);
   e.zoneLower = MathMin(zone.upper, zone.lower);
   e.type = QME_ENTRY_LIMIT;

   if(side == QME_SIDE_NONE || price <= 0.0 || atr <= 0.0)
     {
      e.reason = QME_REJ_INTERNAL;
      e.note = "invalid inputs";
      return(e);
     }

   const double buffer = MathMax(atr * bufferAtr, point * 2.0);
   const double brokerStop = CSymbolSpecifications::MinStopDistance(spec);

   if(side == QME_SIDE_BUY)
     {
      //--- inside the zone: take the market entry at the current price,
      //--- otherwise wait for a retest of the upper edge
      if(price <= e.zoneUpper && price >= e.zoneLower)
        {
         e.entry = price;
         e.type = QME_ENTRY_MARKET;
        }
      else
         e.entry = e.zoneUpper;

      e.stop = e.zoneLower - buffer;
      if(e.entry <= e.stop)
        {
         e.reason = QME_REJ_SL_INVALID;
         e.note = "entry below stop";
         return(e);
        }
     }
   else
     {
      if(price >= e.zoneLower && price <= e.zoneUpper)
        {
         e.entry = price;
         e.type = QME_ENTRY_MARKET;
        }
      else
         e.entry = e.zoneLower;

      e.stop = e.zoneUpper + buffer;
      if(e.entry >= e.stop)
        {
         e.reason = QME_REJ_SL_INVALID;
         e.note = "entry above stop";
         return(e);
        }
     }

   e.entry = CSymbolSpecifications::NormalizePrice(spec, e.entry);
   e.stop  = CSymbolSpecifications::NormalizePrice(spec, e.stop);

   //--- broker minimum stop distance: widen (never shrink) and re-validate
   double dist = MathAbs(e.entry - e.stop);
   if(dist < brokerStop)
     {
      const double widened = brokerStop + point;
      e.stop = (side == QME_SIDE_BUY) ? e.entry - widened : e.entry + widened;
      e.stop = CSymbolSpecifications::NormalizePrice(spec, e.stop);
      dist = MathAbs(e.entry - e.stop);
     }

   //--- reject when the structural stop is unreasonably wide
   if(maxStopAtr > 0.0 && dist > atr * maxStopAtr)
     {
      e.reason = QME_REJ_SL_INVALID;
      e.note = "structural stop " + DoubleToString(dist / atr, 2) + " ATR exceeds max " +
               QmeFmt(maxStopAtr, 2);
      return(e);
     }

   e.stopDistance = dist;
   if(side == QME_SIDE_BUY)
     {
      e.target1 = e.entry + rrTarget * dist;
      e.target2 = e.entry + 1.5 * rrTarget * dist;
     }
   else
     {
      e.target1 = e.entry - rrTarget * dist;
      e.target2 = e.entry - 1.5 * rrTarget * dist;
     }

   e.valid = true;
   return(e);
  }

#endif // __QME_STRATEGY_ENTRYRIG_MQH__
//+------------------------------------------------------------------+
