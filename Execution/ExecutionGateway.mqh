//+------------------------------------------------------------------+
//|                                       Execution/ExecutionGateway  |
//|  The single authorized path from an intent to the broker.            |
//|                                                                   |
//|  Pipeline:                                                        |
//|   idempotency -> final authorization -> request build -> validate     |
//|   -> OrderCheck -> send (retry policy) -> reconcile -> journal         |
//|  Ambiguous outcomes remain blocked for operator reconciliation.       |
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
#include "../Persistence/CheckpointManager.mqh"
#include "../Persistence/StateRecovery.mqh"

class CExecutionGateway
  {
private:
   CAccountContext   *m_account;
   CIdempotencyGuard  m_idem;
   CExecutionMonitor  m_monitor;
   CTradeJournal      m_journal;
   bool               m_ready;
   CCheckpointManager *m_checkpoint;
   CPositionStateStore *m_positions;
   CSignalHistoryStore *m_history;
   CSignalDeduplicator *m_dedup;
   CRuntimeMemory     *m_memory;
   ENUM_QME_REJECT    m_lastReject;
   string             m_lastRejectNote;


public:
                     CExecutionGateway(void);
   bool              Init(CAccountContext *account, const CConfig &cfg, string &err);
   void              Shutdown(void);
   void              AttachPersistence(CCheckpointManager *checkpoint, CPositionStateStore *positions,
                                       CSignalHistoryStore *history, CSignalDeduplicator *dedup,
                                       CRuntimeMemory *memory);

   bool              Execute(const STradePlan &plan, const SSymbolSpec &spec,
                             const CConfig &cfg, SExecutionResult &res);

   static bool       SupportsEntryType(const ENUM_QME_ENTRY_TYPE type) { return(type == QME_ENTRY_MARKET); }
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
   m_checkpoint = NULL;
   m_positions = NULL;
   m_history = NULL;
   m_dedup = NULL;
   m_memory = NULL;
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
void CExecutionGateway::AttachPersistence(CCheckpointManager *checkpoint, CPositionStateStore *positions,
                                          CSignalHistoryStore *history, CSignalDeduplicator *dedup,
                                          CRuntimeMemory *memory)
  {
   m_checkpoint = checkpoint;
   m_positions = positions;
   m_history = history;
   m_dedup = dedup;
   m_memory = memory;
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

   // Pending-order lifecycle and risk reservation are not implemented yet.
   // Do not silently treat a pending order as a fill.
   if(!SupportsEntryType(plan.entryType))
     {
      res.state = QME_EXEC_FAILED;
      res.reject = QME_REJ_DISABLED_BY_CONFIG;
      res.comment = "pending entries disabled until lifecycle and risk reconciliation are implemented";
      m_lastReject = res.reject;
      m_lastRejectNote = res.comment;
      m_monitor.OnLocalReject(plan.symbol, res.comment);
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

   // The quote used by the builder may differ from the signal used for
   // sizing. Revalidate RR and broker-calculated loss on the request itself.
   const SRequestValidation risk = CExecutionValidator::RequestRisk(req, plan, acc.equity, cfg);
   if(!risk.ok)
     {
      res.state = QME_EXEC_FAILED;
      res.reject = risk.reason;
      res.comment = risk.comment;
      m_lastReject = res.reject;
      m_lastRejectNote = res.comment;
      m_monitor.OnLocalReject(plan.symbol, res.comment);
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

   // Write the in-flight claim BEFORE OrderSend. If the process crashes
   // after this point, recovery must not silently resend this intent.
   string persistErr = "";
   bool saved = false;
   if(m_checkpoint != NULL && m_positions != NULL && m_history != NULL &&
      m_dedup != NULL && m_memory != NULL && m_checkpoint.Enabled())
     {
      const string payload = CStateRecovery::Compose(*m_account.State(), *m_positions,
                                                     *m_history, *m_dedup, m_idem, *m_memory);
      saved = m_checkpoint.Save(payload, TimeCurrent(), persistErr);
     }
   else
      persistErr = "persistence unavailable";
   if(!saved)
     {
      m_idem.Abort(plan.fingerprint); // no order was sent
      res.state = QME_EXEC_FAILED;
      res.reject = QME_REJ_INTERNAL;
      res.comment = "pre-send checkpoint failed: " + persistErr;
      m_lastReject = res.reject;
      m_lastRejectNote = res.comment;
      m_monitor.OnLocalReject(plan.symbol, res.comment);
      return(false);
     }

   m_journal.RecordIntent(plan, "SEND", "volume=" + DoubleToString(plan.volume, 2));
   const ulong t0 = GetMicrosecondCount();
   const bool ok = COrderManager::Send(req, cfg, res);
   const double latency = (double)(GetMicrosecondCount() - t0) / 1000.0;
   m_monitor.OnSent(plan.symbol, latency);
   // Remember only confirmed or unresolved broker submissions. A local
   // validation rejection must remain retryable when market conditions change.
   if((ok || res.state == QME_EXEC_UNKNOWN_STATE) && m_dedup != NULL)
      m_dedup.Register(plan.fingerprint, plan.signalId, TimeCurrent());

   //--- 6. ambiguous outcome: reconcile before anything else
   if(!ok && res.state == QME_EXEC_UNKNOWN_STATE)
     {
      // Symbol + magic cannot identify this intent: a pre-existing position
      // or a delayed/pending order could be mistaken for a fill. Keep the
      // claim IN_FLIGHT until an operator reconciles it with broker records.
      res.reject = QME_REJ_EXECUTION_FAILED;
      res.comment = "ambiguous order outcome; intent remains blocked pending reconciliation";
      m_journal.RecordEvent("UNKNOWN", plan.symbol, res.comment);
      m_monitor.OnResult(res, latency);
      m_journal.RecordResult(plan, res);
      m_lastReject = res.reject;
      m_lastRejectNote = res.comment;
      return(false);
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
