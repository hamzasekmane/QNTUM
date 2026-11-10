//+------------------------------------------------------------------+
//|                                          Strategy/SignalExpiry    |
//|  Expiration and invalidation of live signals.                        |
//|                                                                   |
//|  A signal expires when:                                            |
//|   * its configured expiry time has passed OR                        |
//|   * the entry timeframe moved `maxBars` closed bars past creation OR   |
//|   * price already violated the stop before execution OR               |
//|   * the zone it was based on became invalid.                          |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SIGNALEXPIRY_MQH__
#define __QME_STRATEGY_SIGNALEXPIRY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Zones/ZoneEngine.mqh"
#include "SignalRegistry.mqh"
#include "SignalLifecycle.mqh"

class CSignalExpiry
  {
public:
   //--- reason a signal should no longer be executable (NONE = still valid)
   static ENUM_QME_REJECT Check(const STradingSignal &s, const datetime now,
                                const double price, const bool zoneActive);

   //--- expire everything that is no longer executable
   static int        Process(CSignalRegistry &registry, CSignalLifecycle &lifecycle,
                            CZoneEngine &zones, const datetime now, const double price);
  };

//------------------------------------------------------------------//
ENUM_QME_REJECT CSignalExpiry::Check(const STradingSignal &s, const datetime now,
                                     const double price, const bool zoneActive)
  {
   if(CSignalTypes::IsTerminal(s.state)) return(QME_REJ_NONE);

   if(s.expires > 0 && now >= s.expires)
      return(QME_REJ_EXPIRED);

   if(!zoneActive)
      return(QME_REJ_INVALIDATED);

   //--- price already beyond the stop: the idea is dead before entry
   if(price > 0.0)
     {
      if(s.side == QME_SIDE_BUY && price <= s.stopLoss + QME_PRICE_EPS)
         return(QME_REJ_INVALIDATED);
      if(s.side == QME_SIDE_SELL && price >= s.stopLoss - QME_PRICE_EPS)
         return(QME_REJ_INVALIDATED);
     }
   return(QME_REJ_NONE);
  }

//------------------------------------------------------------------//
int CSignalExpiry::Process(CSignalRegistry &registry, CSignalLifecycle &lifecycle,
                           CZoneEngine &zones, const datetime now, const double price)
  {
   int expired = 0;
   for(int i = 0; i < registry.Count(); i++)
     {
      STradingSignal s;
      if(!registry.At(i, s)) continue;
      //--- only pre-execution states can expire
      if(!(s.state == QME_SIG_DETECTED || s.state == QME_SIG_EVALUATING ||
           s.state == QME_SIG_APPROVED || s.state == QME_SIG_EXECUTION_PENDING))
         continue;

      STradingZone zone;
      const bool zoneActive = zones.Board().ById(s.zoneId, zone) ? QmeZoneIsActive(zone, now)
                                                                 : false;
      const double px = (price > 0.0) ? price : 0.0;
      const ENUM_QME_REJECT reason = Check(s, now, px, zoneActive);
      if(reason == QME_REJ_NONE) continue;

      const ENUM_QME_SIGNAL_STATE to = (reason == QME_REJ_EXPIRED) ? QME_SIG_EXPIRED
                                                                   : QME_SIG_INVALIDATED;
      if(lifecycle.Transition(s, to, reason,
                              (reason == QME_REJ_EXPIRED) ? "expiry time reached"
                                                          : "zone no longer valid", now))
        {
         registry.Update(s);
         expired++;
        }
     }
   return(expired);
  }

#endif // __QME_STRATEGY_SIGNALEXPIRY_MQH__
//+------------------------------------------------------------------+
