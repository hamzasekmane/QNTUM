//+------------------------------------------------------------------+
//|                                         Strategy/SignalTypes      |
//|  Signal construction, identity and validation helpers.              |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SIGNALTYPES_MQH__
#define __QME_STRATEGY_SIGNALTYPES_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Intelligence/ScoringEngine.mqh"
#include "MTF/EntryTypes.mqh"

class CSignalTypes
  {
public:
   static bool       IsTerminal(const ENUM_QME_SIGNAL_STATE s);
   static bool       IsLive(const ENUM_QME_SIGNAL_STATE s);
   static bool       IsPendingExecution(const ENUM_QME_SIGNAL_STATE s);

   //--- deterministic id: symbol/side/tf/zone/bar hashed, then made unique
   static ulong      MakeId(const string symbol, const ENUM_QME_SIDE side,
                            const ENUM_TIMEFRAMES tf, const ulong zoneId,
                            const datetime barTime, const long sequence);

   //--- validate the economic content of a signal before it can be approved
   static bool       Validate(STradingSignal &s, const double minRR,
                              ENUM_QME_REJECT &reason, string &why);

   static string     Describe(const STradingSignal &s);
  };

//------------------------------------------------------------------//
bool CSignalTypes::IsTerminal(const ENUM_QME_SIGNAL_STATE s)
  {
   return(s == QME_SIG_CLOSED || s == QME_SIG_REJECTED || s == QME_SIG_EXPIRED ||
          s == QME_SIG_INVALIDATED || s == QME_SIG_EXECUTION_FAILED ||
          s == QME_SIG_CANCELLED);
  }

bool CSignalTypes::IsLive(const ENUM_QME_SIGNAL_STATE s)
  {
   return(s == QME_SIG_DETECTED || s == QME_SIG_EVALUATING || s == QME_SIG_APPROVED ||
          s == QME_SIG_EXECUTION_PENDING || s == QME_SIG_EXECUTED || s == QME_SIG_MONITORING);
  }

bool CSignalTypes::IsPendingExecution(const ENUM_QME_SIGNAL_STATE s)
  {
   return(s == QME_SIG_APPROVED || s == QME_SIG_EXECUTION_PENDING);
  }

//------------------------------------------------------------------//
ulong CSignalTypes::MakeId(const string symbol, const ENUM_QME_SIDE side,
                           const ENUM_TIMEFRAMES tf, const ulong zoneId,
                           const datetime barTime, const long sequence)
  {
   const string key = symbol + "|" + QmeSideName(side) + "|" + QmeTimeframeName(tf) + "|" +
                      IntegerToString((long)zoneId) + "|" + IntegerToString((long)barTime) + "|" +
                      IntegerToString(sequence);
   ulong id = QmeHashString(key);
   if(id == 0) id = 1;
   return(id);
  }

//------------------------------------------------------------------//
bool CSignalTypes::Validate(STradingSignal &s, const double minRR,
                            ENUM_QME_REJECT &reason, string &why)
  {
   reason = QME_REJ_NONE;
   why = "";

   if(s.side == QME_SIDE_NONE) { reason = QME_REJ_INTERNAL; why = "no direction"; return(false); }
   if(StringLen(s.symbol) == 0) { reason = QME_REJ_INTERNAL; why = "no symbol"; return(false); }
   if(s.entry <= 0.0) { reason = QME_REJ_INTERNAL; why = "no entry price"; return(false); }

   if(!QmeStopIsValid(s.side, s.entry, s.stopLoss))
     {
      reason = QME_REJ_SL_INVALID;
      why = "protective stop missing or on the wrong side";
      return(false);
     }
   if(!QmeTargetIsValid(s.side, s.entry, s.takeProfit1))
     {
      reason = QME_REJ_TP_INVALID;
      why = "take profit missing or on the wrong side";
      return(false);
     }

   s.rr = QmeComputeRR(s.side, s.entry, s.stopLoss, s.takeProfit1);
   s.riskReward = s.rr;
   if(s.rr < minRR)
     {
      reason = QME_REJ_RR;
      why = "rr " + QmeFmt(s.rr, 2) + " < " + QmeFmt(minRR, 2);
      return(false);
     }
   if(s.expires > 0 && s.created > 0 && s.expires <= s.created)
     {
      reason = QME_REJ_EXPIRED;
      why = "expiry not after creation";
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
string CSignalTypes::Describe(const STradingSignal &s)
  {
   return("#" + IntegerToString((long)s.id) + " " + s.symbol + " " + QmeSideName(s.side) + " " +
          QmeTimeframeName(s.tf) + " " + QmeSignalStateName(s.state) +
          " entry=" + DoubleToString(s.entry, 5) +
          " sl=" + DoubleToString(s.stopLoss, 5) +
          " tp=" + DoubleToString(s.takeProfit1, 5) +
          " rr=" + QmeFmt(s.rr, 2) +
          " score=" + QmeFmt(s.score, 1) +
          (s.reject != QME_REJ_NONE ? " reject=" + QmeRejectName(s.reject) : ""));
  }

#endif // __QME_STRATEGY_SIGNALTYPES_MQH__
//+------------------------------------------------------------------+
