//+------------------------------------------------------------------+
//|                                  Risk/SpreadSessionGuard          |
//|  Spread spikes and session restrictions.                             |
//|                                                                   |
//|  Two independent limits, both optional:                            |
//|   * absolute cap in points (InpMaxSpreadPoints, 0 = disabled);       |
//|   * relative cap: spread <= ratio * ATR (adapts to every instrument). |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_SPREADSESSION_MQH__
#define __QME_RISK_SPREADSESSION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"

class CSpreadSessionGuard
  {
public:
   static bool       CheckSpread(const double spreadPoints, const double atr,
                                 const double point, const double maxSpreadPoints,
                                 const double maxSpreadAtrRatio,
                                 ENUM_QME_REJECT &reason, string &why);

   static bool       CheckSession(const ENUM_QME_SESSION session, const bool sessionAllowed,
                                  const bool brokerSessionOpen, const CConfig &cfg,
                                  ENUM_QME_REJECT &reason, string &why);
  };

//------------------------------------------------------------------//
bool CSpreadSessionGuard::CheckSpread(const double spreadPoints, const double atr,
                                      const double point, const double maxSpreadPoints,
                                      const double maxSpreadAtrRatio,
                                      ENUM_QME_REJECT &reason, string &why)
  {
   reason = QME_REJ_NONE;
   why = "";

   if(spreadPoints <= 0.0)
     {
      reason = QME_REJ_STALE_DATA;
      why = "spread is zero or unavailable";
      return(false);
     }

   if(maxSpreadPoints > 0.0 && spreadPoints > maxSpreadPoints)
     {
      reason = QME_REJ_SPREAD;
      why = "spread " + QmeFmt(spreadPoints, 1) + " > cap " + QmeFmt(maxSpreadPoints, 1) + " points";
      return(false);
     }

   if(maxSpreadAtrRatio > 0.0 && atr > 0.0 && point > 0.0)
     {
      const double spreadPrice = spreadPoints * point;
      const double ratio = spreadPrice / atr;
      if(ratio > maxSpreadAtrRatio)
        {
         reason = QME_REJ_SPREAD;
         why = "spread is " + QmeFmt(ratio, 3) + " of ATR (max " +
               QmeFmt(maxSpreadAtrRatio, 3) + ")";
         return(false);
        }
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CSpreadSessionGuard::CheckSession(const ENUM_QME_SESSION session, const bool sessionAllowed,
                                       const bool brokerSessionOpen, const CConfig &cfg,
                                       ENUM_QME_REJECT &reason, string &why)
  {
   reason = QME_REJ_NONE;
   why = "";

   if(!brokerSessionOpen)
     {
      reason = QME_REJ_MARKET_CLOSED;
      why = "the broker reports the symbol as closed";
      return(false);
     }
   if(cfg.In.sessionFilterEnabled && !sessionAllowed)
     {
      reason = QME_REJ_SESSION;
      why = "session " + QmeSessionName(session) + " is not allowed by configuration";
      return(false);
     }
   return(true);
  }

#endif // __QME_RISK_SPREADSESSION_MQH__
//+------------------------------------------------------------------+
