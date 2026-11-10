//+------------------------------------------------------------------+
//|                                     Analysis/Market/SessionEngine |
//|  Classifies the current trading session from GMT and answers whether |
//|  the configured policy allows trading in it.                        |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_SESSION_ENGINE_MQH__
#define __QME_ANALYSIS_SESSION_ENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Config.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/MarketClock.mqh"

struct SSessionResult
  {
   ENUM_QME_SESSION  session;
   bool              tradingAllowed;   // per configuration
   bool              weekend;
   int               gmtHour;
   datetime          gmtTime;
   bool              valid;
  };

void QmeSessionReset(SSessionResult &s)
  {
   s.session = QME_SESSION_UNKNOWN;
   s.tradingAllowed = false;
   s.weekend = false;
   s.gmtHour = 0;
   s.gmtTime = 0;
   s.valid = false;
  }

class CSessionEngine
  {
public:
   static SSessionResult Evaluate(CMarketClock &clock, CConfig &cfg);
  };

//------------------------------------------------------------------//
SSessionResult CSessionEngine::Evaluate(CMarketClock &clock, CConfig &cfg)
  {
   SSessionResult r;
   r.session = QME_SESSION_UNKNOWN;
   r.tradingAllowed = false;
   r.weekend = false;
   r.gmtHour = 0;
   r.gmtTime = clock.GmtTime();
   r.valid = false;

   if(r.gmtTime <= 0)
      return(r);

   MqlDateTime dt;
   TimeToStruct(r.gmtTime, dt);
   r.gmtHour = dt.hour;
   r.weekend = CMarketClock::IsWeekend(r.gmtTime);
   r.session = CMarketClock::SessionOf(r.gmtTime);
   r.tradingAllowed = (!r.weekend) && cfg.SessionAllowed(r.session);
   r.valid = true;
   return(r);
  }

#endif // __QME_ANALYSIS_SESSION_ENGINE_MQH__
//+------------------------------------------------------------------+
