//+------------------------------------------------------------------+
//|                                    Strategy/MTF/PlanLifecycle     |
//|  A trade plan is the sized, authorizable intent derived from an      |
//|  approved signal. It is the only object the execution layer accepts.  |
//|                                                                   |
//|  A plan is INVALID unless it has a volume, a stop and a target.       |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_PLANLIFECYCLE_MQH__
#define __QME_STRATEGY_PLANLIFECYCLE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../SignalTypes.mqh"

class CPlanLifecycle
  {
public:
   static bool       Create(STradePlan &plan, const STradingSignal &s,
                            const double volume, const double riskMoney,
                            const ulong magic, const ENUM_QME_ACCOUNT_MODE mode);
   static bool       Validate(const STradePlan &p, const double minRR,
                              ENUM_QME_REJECT &reason, string &why);
   static string     Serialize(const STradePlan &p);
   static bool       Deserialize(const string line, STradePlan &p);
   static string     Describe(const STradePlan &p);
  };

//------------------------------------------------------------------//
bool CPlanLifecycle::Create(STradePlan &plan, const STradingSignal &s,
                            const double volume, const double riskMoney,
                            const ulong magic, const ENUM_QME_ACCOUNT_MODE mode)
  {
   QmePlanClear(plan);
   plan.signalId = s.id;
   plan.symbol = s.symbol;
   plan.side = s.side;
   plan.entryType = s.entryType;
   plan.entry = s.entry;
   plan.stopLoss = s.stopLoss;
   plan.takeProfit = s.takeProfit1;
   plan.volume = volume;
   plan.riskMoney = riskMoney;
   plan.rr = s.rr;
   plan.score = s.score;
   plan.magic = magic;
   plan.accountMode = mode;
   plan.fingerprint = s.fingerprint;
   plan.created = TimeCurrent();
   plan.authorized = false;
   plan.riskPassed = false;
   plan.reject = QME_REJ_NONE;
   return(plan.signalId != 0 && plan.volume > 0.0);
  }

//------------------------------------------------------------------//
bool CPlanLifecycle::Validate(const STradePlan &p, const double minRR,
                              ENUM_QME_REJECT &reason, string &why)
  {
   reason = QME_REJ_NONE;
   why = "";

   if(p.signalId == 0) { reason = QME_REJ_INTERNAL; why = "plan without signal id"; return(false); }
   if(StringLen(p.symbol) == 0) { reason = QME_REJ_INTERNAL; why = "plan without symbol"; return(false); }
   if(p.side == QME_SIDE_NONE) { reason = QME_REJ_INTERNAL; why = "plan without direction"; return(false); }
   if(p.volume <= 0.0) { reason = QME_REJ_VOLUME_INVALID; why = "volume is zero"; return(false); }
   if(!QmeStopIsValid(p.side, p.entry, p.stopLoss))
     { reason = QME_REJ_SL_INVALID; why = "stop invalid"; return(false); }
   if(!QmeTargetIsValid(p.side, p.entry, p.takeProfit))
     { reason = QME_REJ_TP_INVALID; why = "target invalid"; return(false); }

   const double rr = QmeComputeRR(p.side, p.entry, p.stopLoss, p.takeProfit);
   if(rr < minRR) { reason = QME_REJ_RR; why = "plan rr below minimum"; return(false); }
   return(true);
  }

//------------------------------------------------------------------//
string CPlanLifecycle::Serialize(const STradePlan &p)
  {
   return("plan;" + IntegerToString((long)p.signalId) + ";" + p.symbol + ";" +
          IntegerToString((int)p.side) + ";" + DoubleToString(p.entry, 8) + ";" +
          DoubleToString(p.stopLoss, 8) + ";" + DoubleToString(p.takeProfit, 8) + ";" +
          DoubleToString(p.volume, 4) + ";" + DoubleToString(p.riskMoney, 2) + ";" +
          IntegerToString((long)p.magic) + ";" + IntegerToString((int)p.accountMode) + ";" +
          p.fingerprint);
  }

//------------------------------------------------------------------//
bool CPlanLifecycle::Deserialize(const string line, STradePlan &p)
  {
   QmePlanClear(p);
   string f[];
   if(StringSplit(line, ';', f) < 12) return(false);
   if(f[0] != "plan") return(false);
   p.signalId = (ulong)StringToInteger(f[1]);
   p.symbol = f[2];
   p.side = (ENUM_QME_SIDE)StringToInteger(f[3]);
   p.entry = StringToDouble(f[4]);
   p.stopLoss = StringToDouble(f[5]);
   p.takeProfit = StringToDouble(f[6]);
   p.volume = StringToDouble(f[7]);
   p.riskMoney = StringToDouble(f[8]);
   p.magic = (ulong)StringToInteger(f[9]);
   p.accountMode = (ENUM_QME_ACCOUNT_MODE)StringToInteger(f[10]);
   p.fingerprint = f[11];
   p.rr = QmeComputeRR(p.side, p.entry, p.stopLoss, p.takeProfit);
   return(p.signalId != 0 && p.volume > 0.0);
  }

//------------------------------------------------------------------//
string CPlanLifecycle::Describe(const STradePlan &p)
  {
   return("#" + IntegerToString((long)p.signalId) + " " + p.symbol + " " +
          QmeSideName(p.side) + " vol=" + QmeFmt(p.volume, 2) +
          " entry=" + DoubleToString(p.entry, 5) +
          " sl=" + DoubleToString(p.stopLoss, 5) +
          " tp=" + DoubleToString(p.takeProfit, 5) +
          " rr=" + QmeFmt(p.rr, 2) + " risk=" + QmeFmtMoney(p.riskMoney) +
          " auth=" + QmeBoolStr(p.authorized));
  }

#endif // __QME_STRATEGY_PLANLIFECYCLE_MQH__
//+------------------------------------------------------------------+
