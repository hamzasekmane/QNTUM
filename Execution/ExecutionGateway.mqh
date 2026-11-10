//+------------------------------------------------------------------+
//|                                       Execution/ExecutionGateway  |
//|  The single authorized path from an intent to the broker.            |
//|                                                                   |
//|  Pipeline:                                                        |
//|   idempotency -> final authorization -> request build -> validate     |
//|   -> OrderCheck -> send (retry policy) -> reconcile -> journal         |
//|  If any step fails the intent is recorded as failed and nothing is     |
//|  left in an unknown state without reconciliation.                    |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_GATEWAY_MQH__
#define __QME_EXECUTION_GATEWAY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountContext.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Account/TradingPermissions.mqh"
#include "../Account/BrokerCapabilities.mqh"
#include "IdempotencyGuard.mqh"
#include "TradeRequestBuilder.mqh"
#include "ExecutionValidator.mqh"
#include "OrderManager.mqh"
#include "PositionReconciler.mqh"
#include "ExecutionMonitor.mqh"
#include "TradeJournal.mqh"
#include "RetryPolicy.mqh"

class CExecutionGateway
  {
private:
   CAccountContext   *m_account;
   CIdempotencyGuard  m_idem;
   CExecutionMonitor  m_monitor;
   CTradeJournal      m_journal;
   bool               m_ready;
   ENUM_QME_REJECT    m_lastReject;
   string             m_lastRejectNote;

   bool              ReconcileAfterAmbiguous(const STradePlan &plan, SExecutionResult &res);

public:
                     CExecutionGateway(void);
   bool              Init(CAccountContext *account, const CConfig &cfg, string &err);
   void              Shutdown(void);

   bool              Execute(const STradePlan &plan, const SSymbolSpec &spec,
                             const CConfig &cfg, SExecutionResult &res);

   CIdempotencyGuard* Idempotency(void) { return(&m_idem); }
   CExecutionMonitor* Monitor(void) { return(&m_monitor); }
   CTradeJournal     *Journal(void) { return(&m_journal); }
   bool              Ready(void) { return(m_ready); }
   ENUM_QME_REJECT   LastReject(void) { return(m_lastReject); }
   string            LastRejectNote(void) { return(m_lastRejectNote); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CExecutionGateway::CExecutionGateway(void)
  {
   m_account = NULL;
   m_ready = false;
   m_lastReject = QME_REJ_NONE;
   m_lastRejectNote = "";
  }

//------------------------------------------------------------------//
bool CExecutionGateway::Init(CAccountContext *account, const CConfig &cfg, string &err)
  {
   err = "";
   m_account = account;
   m_idem.Reset();
   m_monitor.Reset();

   if(!m_journal.Init(cfg.In.tradeJournalEnabled, account != NULL ? account.Login() : 0, err))
     {
      m_ready = false;
      return(false);
     }
   m_ready = true;
   QmeLogMsg(QME_LOG_INFO, "Gateway", "execution gateway ready (journal " +
             (cfg.In.tradeJournalEnabled ? "on" : "off") + ")");
   return(true);
  }

//------------------------------------------------------------------//
void CExecutionGateway::Shutdown(void)
  {
   m_journal.Shutdown();
   m_ready = false;
   QmeLogMsg(QME_LOG_INFO, "Gateway", "execution gateway stopped; " + m_monitor.Describe());
  }

//------------------------------------------------------------------//
bool CExecutionGateway::ReconcileAfterAmbiguous(const STradePlan &plan, SExecutionResult &res)
  {
   ulong tk = 0;
   double vol = 0.0, open = 0.0, sl = 0.0, tp = 0.0;
   if(CPositionReconciler::FindPosition(plan.symbol, plan.magic, tk, vol, open, sl, tp))
     {
      res.positionTicket = tk;
      res.filledVolume = vol;
      res.filledPrice = open;
      res.confirmed = true;
      res.state = QME_EXEC_RECONCILED;
      res.comment = "reconciled: position " + IntegerToString((long)tk) + " exists";
      m_journal.RecordEvent("RECONCILED", plan.symbol, res.comment);
      QmeLogMsg(QME_LOG_WARN, "Gateway", plan.symbol + " " + res.comment);
      return(true);
     }

   res.confirmed = false;
   res.state = QME_EXEC_UNKNOWN_STATE;
   res.comment = "ambiguous broker answer and no position found: state unknown";
   m_journal.RecordEvent("UNKNOWN", plan.symbol, res.comment);
   QmeLogMsg(QME_LOG_ERROR, "Gateway", plan.symbol + " " + res.comment);
   return(false);
  }

//------------------------------------------------------------------//
bool CExecutionGateway::Execute(const STradePlan &plan, const SSymbolSpec &spec,
                                const CConfig &cfg, SExecutionResult &res)
  {
   QmeExecClear(res);
   m_lastReject = QME_REJ_NONE;
   m_lastRejectNote = "";

   if(!m_ready || m_account == NULL)
     {
      res.state = QME_EXEC_FAILED;
      res.reject = QME_REJ_INTERNAL;
      m_lastReject = res.reject;
      m_lastRejectNote = "gateway not initialised";
      res.comment = m_lastRejectNote;
      return(false);
     }

   //--- 1. idempotency: has this intent already been consumed?
   string why = "";
   if(!m_idem.CanExecute(plan.fingerprint, why))
     {
      res.state = QME_EXEC_FAILED;
      res.reject = QME_REJ_DUPLICATE_SIGNAL;
      m_lastReject = res.reject;
      m_lastRejectNote = why;
      res.comment = why;
      m_monitor.OnLocalReject(plan.symbol, why);
      return(false);
     }

   //--- 2. final authorization (independent from the strategy's decision)
   const SAccountContext acc = m_account.Snapshot();
   ENUM_QME_REJECT authReject = QME_REJ_NONE;
   string authNote = "";
   if(!CTradingPermissions::Authorize(cfg.In, acc, spec, plan.side, authReject, authNote))
     {
      res.state = QME_EXEC_FAILED;
      res.reject = authReject;
      m_lastReject = authReject;
      m_lastRejectNote = authNote;
      res.comment = authNote;
      m_monitor.OnLocalReject(plan.symbol, authNote);
      QmeLogMsg(QME_LOG_WARN, "Gateway", plan.symbol + " not authorized: " + authNote);
      return(false);
     }

   //--- 3. request
   MqlTradeRequest req;
   string buildWhy = "";
   const int filling = CBrokerCapabilities::ChooseFilling(spec,
                             (plan.side == QME_SIDE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!CTradeRequestBuilder::Build(req, plan, spec, filling,
                                   cfg.In.deviationPoints, QME_ORDER_COMMENT, buildWhy))
     {
      res.state = QME_EXEC_FAILED;
      res.reject = QME_REJ_INTERNAL;
      m_lastReject = res.reject;
      m_lastRejectNote = buildWhy;
      res.comment = buildWhy;
      res.requestBuilt = false;
      m_monitor.OnLocalReject(plan.symbol, buildWhy);
      return(false);
     }
   res.requestBuilt = true;
   res.requestedVolume = plan.volume;
   res.requestedPrice = req.price;
   m_monitor.OnRequestBuilt(plan.symbol);

   //--- 4. validation (local + server-side OrderCheck, no order sent)
   const SRequestValidation v = CExecutionValidator::Full(req, plan, spec, cfg);
   res.orderCheckRetcode = v.retcode;
   if(!v.ok)
     {
      res.state = QME_EXEC_FAILED;
      res.reject = v.reason;
      m_lastReject = v.reason;
      m_lastRejectNote = v.comment;
      res.comment = v.comment;
      m_monitor.OnLocalReject(plan.symbol, v.comment);
      m_journal.RecordIntent(plan, "VALIDATION_FAILED", v.comment);
      QmeLogMsg(QME_LOG_WARN, "Gateway", plan.symbol + " validation failed: " + v.comment);
      return(false);
     }

   //--- 5. claim the intent, then send
   if(!m_idem.Begin(plan.fingerprint, TimeCurrent()))
     {
      res.state = QME_EXEC_FAILED;
      res.reject = QME_REJ_DUPLICATE_SIGNAL;
      m_lastReject = res.reject;
      m_lastRejectNote = "could not claim the intent";
      res.comment = m_lastRejectNote;
      return(false);
     }

   m_journal.RecordIntent(plan, "SEND", "volume=" + DoubleToString(plan.volume, 2));
   const ulong t0 = GetMicrosecondCount();
   const bool ok = COrderManager::Send(req, cfg, res);
   const double latency = (double)(GetMicrosecondCount() - t0) / 1000.0;
   m_monitor.OnSent(plan.symbol, latency);

   //--- 6. ambiguous outcome: reconcile before anything else
   if(!ok && res.state == QME_EXEC_UNKNOWN_STATE)
     {
      const bool found = ReconcileAfterAmbiguous(plan, res);
      m_idem.Complete(plan.fingerprint, found, TimeCurrent());
      m_monitor.OnResult(res, latency);
      m_journal.RecordResult(plan, res);
      m_lastReject = QME_REJ_EXECUTION_FAILED;
      m_lastRejectNote = res.comment;
      return(found);
     }

   m_idem.Complete(plan.fingerprint, ok, TimeCurrent());
   m_monitor.OnResult(res, latency);
   m_journal.RecordResult(plan, res);

   if(!ok)
     {
      m_lastReject = (res.reject != QME_REJ_NONE) ? res.reject : QME_REJ_BROKER_REJECTED;
      m_lastRejectNote = res.comment;
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
string CExecutionGateway::Describe(void)
  {
   return(m_monitor.Describe() + " idemInFlight=" +
          IntegerToString(m_idem.InFlightCount()) +
          (m_lastReject != QME_REJ_NONE ?
           " lastReject=" + QmeRejectName(m_lastReject) + " (" + m_lastRejectNote + ")" : ""));
  }

#endif // __QME_EXECUTION_GATEWAY_MQH__
//+------------------------------------------------------------------+
