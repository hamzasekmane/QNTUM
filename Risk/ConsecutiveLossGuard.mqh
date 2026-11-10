//+------------------------------------------------------------------+
//|                                  Risk/ConsecutiveLossGuard        |
//|  Stops trading after N consecutive losing trades (anti-revenge).     |
//|  The streak is re-derived from broker history, so it survives a       |
//|  restart. A profit resets it; break-even trades do not.               |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_CONSECLOSS_MQH__
#define __QME_RISK_CONSECLOSS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Account/AccountState.mqh"

class CConsecutiveLossGuard
  {
public:
   static bool       Check(CAccountState &state, const int maxLosses,
                           int &current, string &why);
  };

//------------------------------------------------------------------//
bool CConsecutiveLossGuard::Check(CAccountState &state, const int maxLosses,
                                  int &current, string &why)
  {
   why = "";
   current = state.ConsecutiveLosses();
   if(maxLosses <= 0) return(true);
   if(current >= maxLosses)
     {
      why = IntegerToString(current) + " consecutive losses reached the limit of " +
            IntegerToString(maxLosses);
      return(false);
     }
   return(true);
  }

#endif // __QME_RISK_CONSECLOSS_MQH__
//+------------------------------------------------------------------+
