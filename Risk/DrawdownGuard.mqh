//+------------------------------------------------------------------+
//|                                          Risk/DrawdownGuard       |
//|  Blocks new trades when equity drawdown from the peak exceeds the      |
//|  configured limit.                                                    |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_DRAWDOWN_MQH__
#define __QME_RISK_DRAWDOWN_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Account/AccountState.mqh"

class CDrawdownGuard
  {
public:
   static bool       Check(const SAccountContext &acc, CAccountState &state,
                           const double maxDrawdownPct, double &currentPct, string &why);
  };

//------------------------------------------------------------------//
bool CDrawdownGuard::Check(const SAccountContext &acc, CAccountState &state,
                           const double maxDrawdownPct, double &currentPct, string &why)
  {
   why = "";
   currentPct = 0.0;
   if(maxDrawdownPct <= 0.0) return(true);

   currentPct = state.DrawdownPct(acc);
   if(currentPct >= maxDrawdownPct)
     {
      why = "drawdown " + QmeFmt(currentPct, 2) + "% reached the limit of " +
            QmeFmt(maxDrawdownPct, 2) + "%";
      return(false);
     }
   return(true);
  }

#endif // __QME_RISK_DRAWDOWN_MQH__
//+------------------------------------------------------------------+
