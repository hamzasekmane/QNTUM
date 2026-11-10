//+------------------------------------------------------------------+
//|                                       Risk/DailyLossGuard         |
//|  Blocks new trades once the day's loss exceeds the configured cap.    |
//|  The daily baseline is re-derived from broker history on start, so a   |
//|  restart cannot reset the loss counter.                              |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_DAILYLOSS_MQH__
#define __QME_RISK_DAILYLOSS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Account/AccountState.mqh"

class CDailyLossGuard
  {
public:
   static bool       Check(const SAccountContext &acc, CAccountState &state,
                           const double maxDailyLossPct, double &currentPct, string &why);
  };

//------------------------------------------------------------------//
bool CDailyLossGuard::Check(const SAccountContext &acc, CAccountState &state,
                            const double maxDailyLossPct, double &currentPct, string &why)
  {
   why = "";
   currentPct = 0.0;
   if(maxDailyLossPct <= 0.0) return(true);   // guard disabled

   currentPct = state.DailyPlPct(acc);
   if(!QmeIsFinite(currentPct))
     {
      why = "daily P/L is not a finite number";
      return(false);
     }
   if(currentPct <= -maxDailyLossPct)
     {
      why = "daily loss " + QmeFmt(currentPct, 2) + "% reached the limit of " +
            QmeFmt(maxDailyLossPct, 2) + "%";
      return(false);
     }
   return(true);
  }

#endif // __QME_RISK_DAILYLOSS_MQH__
//+------------------------------------------------------------------+
