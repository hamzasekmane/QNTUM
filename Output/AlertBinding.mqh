//+------------------------------------------------------------------+
//|                                        Output/AlertBinding        |
//|  Translates engine facts into alert text.                            |
//|                                                                   |
//|  Kept separate from CAlertEngine so the wording can change without     |
//|  touching delivery, and so the text is testable.                     |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_ALERTBINDING_MQH__
#define __QME_OUT_ALERTBINDING_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Risk/RiskEngine.mqh"
#include "../Persistence/StateRecovery.mqh"
#include "../Monitoring/HealthMonitor.mqh"
#include "AlertEngine.mqh"

class CAlertBinding
  {
public:
   static void       TradeOpened(const STradePlan &plan, const SExecutionResult &res,
                                 string &key, string &title, string &text);
   static void       TradeFailed(const string symbol, const ENUM_QME_REJECT reason,
                                 const string note, string &key, string &title, string &text);
   static void       RiskBlocked(const string symbol, const SRiskAssessment &risk,
                                 string &key, string &title, string &text);
   static void       HealthChanged(const SHealthReport &h, string &key,
                                   string &title, string &text);
   static void       Recovered(const SRecoveryReport &r, string &key,
                               string &title, string &text);
   static void       ShutdownEvent(const string summary, string &key,
                                   string &title, string &text);
  };

//------------------------------------------------------------------//
void CAlertBinding::TradeOpened(const STradePlan &plan, const SExecutionResult &res,
                                string &key, string &title, string &text)
  {
   key = "trade:" + plan.symbol;
   title = "Trade opened " + plan.symbol;
   text = QmeSideName(plan.side) + " " + DoubleToString(res.filledVolume > 0.0 ?
                                                        res.filledVolume : plan.volume, 2) +
          " @ " + DoubleToString(res.filledPrice > 0.0 ? res.filledPrice : plan.entry, 5) +
          " SL " + DoubleToString(plan.stopLoss, 5) +
          " TP " + DoubleToString(plan.takeProfit, 5) +
          " risk " + QmeFmtMoney(plan.riskMoney) +
          " rr " + QmeFmt(plan.rr, 2) +
          " ticket " + IntegerToString((long)res.positionTicket);
  }

//------------------------------------------------------------------//
void CAlertBinding::TradeFailed(const string symbol, const ENUM_QME_REJECT reason,
                                const string note, string &key, string &title, string &text)
  {
   key = "fail:" + symbol;
   title = "Execution failed " + symbol;
   text = QmeRejectName(reason) + ": " + note;
  }

//------------------------------------------------------------------//
void CAlertBinding::RiskBlocked(const string symbol, const SRiskAssessment &risk,
                                string &key, string &title, string &text)
  {
   key = "risk:" + symbol;
   title = "Trade blocked " + symbol;
   text = QmeRejectName(risk.reason) + ": " + risk.note +
          " (checks " + IntegerToString(risk.checksRun) + ")";
  }

//------------------------------------------------------------------//
void CAlertBinding::HealthChanged(const SHealthReport &h, string &key,
                                  string &title, string &text)
  {
   key = "health";
   title = "Health " + CHealthMonitor::StatusName(h.status);
   text = h.issues;
  }

//------------------------------------------------------------------//
void CAlertBinding::Recovered(const SRecoveryReport &r, string &key,
                              string &title, string &text)
  {
   key = "recovery";
   title = "State recovered";
   text = r.note;
  }

//------------------------------------------------------------------//
void CAlertBinding::ShutdownEvent(const string summary, string &key,
                                  string &title, string &text)
  {
   key = "shutdown";
   title = "Engine shutdown";
   text = summary;
  }

#endif // __QME_OUT_ALERTBINDING_MQH__
//+------------------------------------------------------------------+
