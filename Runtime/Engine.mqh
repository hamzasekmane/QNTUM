//+------------------------------------------------------------------+
//|                                               Runtime/Engine      |
//|  The orchestrator. Owns every component and runs the cycle.           |
//|                                                                   |
//|  One cycle:                                                       |
//|    account refresh -> market scan -> signal generation ->             |
//|    decision (risk) -> execution -> book-keeping -> checkpoint          |
//|                                                                   |
//|  The engine never bypasses a layer: it cannot approve a trade, it      |
//|  can only ask the decision engine; it cannot send an order, it can     |
//|  only ask the gateway. Every refusal is kept and explained.            |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_ENGINE_MQH__
#define __QME_RUNTIME_ENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Core/EventLedger.mqh"
#include "../Core/Funnel.mqh"
#include "../Core/Profiler.mqh"
#include "../Account/AccountContext.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Data/MarketData.mqh"
#include "../Data/MarketClock.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "../Analysis/Market/SessionEngine.mqh"
#include "../Zones/ZoneEngine.mqh"
#include "../Intelligence/ScoringEngine.mqh"
#include "../Intelligence/AdaptiveWeights.mqh"
#include "../Strategy/SignalEngine.mqh"
#include "../Strategy/SignalRegistry.mqh"
#include "../Strategy/SignalLifecycle.mqh"
#include "../Strategy/SignalDeduplicator.mqh"
#include "../Strategy/SignalExpiry.mqh"
#include "../Strategy/StrategyRegistry.mqh"
#include "../Strategy/DecisionEngine.mqh"
#include "../Risk/RiskEngine.mqh"
#include "../Execution/ExecutionGateway.mqh"
#include "../Execution/TransactionHandler.mqh"
#include "../Execution/TradeManager.mqh"
#include "../Execution/PositionReconciler.mqh"
#include "../Persistence/PositionStateStore.mqh"
#include "../Persistence/SignalHistoryStore.mqh"
#include "../Persistence/RuntimeMemory.mqh"
#include "../Persistence/CheckpointManager.mqh"
#include "../Persistence/StateRecovery.mqh"
#include "AlgoContainers.mqh"
#include "Scanner.mqh"
#include "Scheduler.mqh"
#include "CanonicalSnapshot.mqh"
#include "ReplayEngine.mqh"
#include "RuntimeController.mqh"
#include "ShutdownManager.mqh"
#include "../Monitoring/ExecutionStatistics.mqh"

class CEngine
  {
private:
   SInputs            m_in;
   CConfig            m_cfg;
   bool               m_ready;
   bool               m_inCycle;
   string             m_error;

   CAccountContext    m_account;
   CMarketData        m_data;
   CScanner           m_scanner;
   CScheduler         m_scheduler;
   CEventLedger       m_ledger;
   CMarketClock       m_clock;

   CSignalLifecycle   m_lifecycle;
   CSignalRegistry    m_registry;
   CSignalDeduplicator m_dedup;
   CScoringEngine     m_scorer;
   CAdaptiveWeights   m_weights;
   CStrategyRegistry  m_strategies;
   CSignalEngine      m_signals;

   CRiskEngine        m_risk;
   CDecisionEngine    m_decisions;
   CExecutionGateway  m_gateway;
   CTransactionHandler m_transactions;

   CPositionStateStore m_positions;
   CSignalHistoryStore m_history;
   CRuntimeMemory     m_memory;
   CProfiler          m_profiler;
   CFunnel            m_funnel;
   CRuntimeController m_controller;
   CCheckpointManager m_checkpoint;
   CReplayEngine      m_replay;
   CShutdownManager   m_shutdown;
   CExecutionStatistics m_execStats;

   long               m_cycles;
   long               m_signalsTotal;
   long               m_trades;
   long               m_errors;
   long               m_rejections;

   bool               ApplySignalState(const ulong id, const ENUM_QME_SIGNAL_STATE to,
                                       const ENUM_QME_REJECT reason, const string note);
   void               RecordDecision(const SDecision &d, const long cycle);
   SSignalRecord      MakeHistoryRecord(const STradingSignal &s, const ENUM_QME_REJECT reason);
   bool               HandleExecution(const SDecision &d, CSymbolRuntime &rt);
   void               SaveCheckpoint(const datetime now);
   void               RecordCanonical(const CSymbolRuntime &rt);
   void               MaintainSignals(void);
   void               ManagePositions(void);
   void               CloseOppositePositions(const STradePlan &plan);
   void               AttachTickets(const ulong id, const SExecutionResult &res);
   void               RestoreState(void);
   void               TrackingAfterExecution(const STradePlan &plan, const SExecutionResult &res);

public:
                     CEngine(void);
                    ~CEngine(void) { Deinit("destructor"); }
   bool              Init(const SInputs &input, string &err);
   void              Deinit(const string reason);

   bool              Cycle(const bool force, string &note);
   bool              OnTick(void);
   void              OnTimer(void);
   void              OnTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                                   const MqlTradeResult &result);

   bool              Ready(void) { return(m_ready); }
   string            LastError(void) { return(m_error); }
   CConfig*          Config(void) { return(&m_cfg); }
   CScanner*         ScannerRef(void) { return(&m_scanner); }
   CAccountContext*  Account(void) { return(&m_account); }
   CExecutionGateway* Gateway(void) { return(&m_gateway); }
   CRiskEngine*      Risk(void) { return(&m_risk); }
   CSignalRegistry*  Signals(void) { return(&m_registry); }
   CSignalHistoryStore* History(void) { return(&m_history); }
   CPositionStateStore* Positions(void) { return(&m_positions); }
   CRuntimeController* Controller(void) { return(&m_controller); }
   CReplayEngine*    Replay(void) { return(&m_replay); }
   CEventLedger*     Ledger(void) { return(&m_ledger); }
   CExecutionStatistics* ExecStats(void) { return(&m_execStats); }
   long              Cycles(void) { return(m_cycles); }
   long              Trades(void) { return(m_trades); }
   long              Errors(void) { return(m_errors); }
   string            Status(void);
  };

//------------------------------------------------------------------//
CEngine::CEngine(void)
  {
   m_ready = false;
   m_inCycle = false;
   m_error = "";
   m_cycles = 0;
   m_signalsTotal = 0;
   m_trades = 0;
   m_errors = 0;
   m_rejections = 0;
  }

//------------------------------------------------------------------//
bool CEngine::Init(const SInputs &input, string &err)
  {
   err = "";
   m_in = input;

   if(!m_cfg.Init(m_in, err))
     {
      m_error = "configuration: " + err;
      return(false);
     }

   m_clock.Refresh();
   m_ledger.Init(QME_MAX_EVENT_QUEUE, m_cfg.In.logCycleDetail);

   //--- account (authority for everything that follows)
   if(!m_account.Init(m_in, m_cfg.In.magic, err))
     {
      m_error = "account: " + err;
      QmeLogMsg(QME_LOG_ERROR, "Engine", m_error);
      return(false);
     }

   //--- data + scanner
   if(!m_data.Init(m_in, err))
     {
      m_error = "market data: " + err;
      QmeLogMsg(QME_LOG_ERROR, "Engine", m_error);
      return(false);
     }
   if(!m_scanner.Init(&m_data, &m_cfg, m_in, err))
     {
      m_error = "scanner: " + err;
      QmeLogMsg(QME_LOG_ERROR, "Engine", m_error);
      return(false);
     }

   m_scheduler.Init(m_in);

   //--- intelligence / strategy
   m_weights.Init(false);
   m_weights.Reset();
   m_scorer.AttachWeights(&m_weights);
   m_strategies.Init();
   m_lifecycle.Attach(&m_ledger);
   m_dedup.Reset();

   m_signals.Attach(&m_scorer, &m_strategies, &m_lifecycle, &m_dedup);

   //--- risk / decision / execution
   m_risk.Init(&m_account, m_cfg.In.magic);
   if(!m_decisions.Init(&m_risk, &m_registry, err))
     {
      m_error = "decision engine: " + err;
      QmeLogMsg(QME_LOG_ERROR, "Engine", m_error);
      return(false);
     }
   if(!m_gateway.Init(&m_account, m_cfg, err))
     {
      m_error = "execution gateway: " + err;
      QmeLogMsg(QME_LOG_ERROR, "Engine", m_error);
      return(false);
     }
   m_transactions.Init(m_cfg.In.magic);

   //--- persistence
   if(!m_checkpoint.Init(m_cfg.In.persistState, "qme_state.txt", m_cfg.In.checkpointSec, err))
      QmeLogMsg(QME_LOG_WARN, "Engine", "persistence disabled: " + err);
   m_replay.Init(512);
   m_funnel.Reset();
   m_profiler.Init(m_cfg.In.profileCycles);
   RestoreState();

   //--- runtime mode
   m_controller.Init(m_cfg, m_account.Snapshot());

   m_ready = true;
   QmeLogMsg(QME_LOG_INFO, "Engine", "initialised on " + m_account.Snapshot().symbol +
             " magic " + IntegerToString((long)m_cfg.In.magic) + "; " + m_controller.Describe());
   return(true);
  }

//------------------------------------------------------------------//
void CEngine::Deinit(const string reason)
  {
   if(!m_ready && m_error == "") return;

   m_controller.BeginStop();
   m_shutdown.Request(reason);
   m_shutdown.SetCounters(m_cycles, m_signalsTotal, m_trades, m_errors);

   //--- 1. final checkpoint before anything is released
   if(m_cfg.In.persistState)
     {
      string err = "";
      string payload = CStateRecovery::Compose(*m_account.State(), m_positions, m_history,
                                               m_dedup, *m_gateway.Idempotency(), m_memory);
      const bool saved = m_checkpoint.Save(payload, TimeCurrent(), err);
      m_shutdown.MarkCheckpoint(saved);
      if(!saved) QmeLogMsg(QME_LOG_WARN, "Engine", "final checkpoint failed: " + err);
     }

   //--- 2. are the engine's positions still protected?
   const SReconcileReport rep = CPositionReconciler::Report(m_cfg.In.magic);
   m_shutdown.MarkPositions(rep.consistent);

   //--- 3. release ordered components
   m_gateway.Shutdown();
   m_shutdown.MarkJournal(true);
   m_risk.Shutdown();
   m_decisions.Shutdown();
   m_scanner.Shutdown();
   m_data.Shutdown();
   m_account.Shutdown();
   m_controller.Stopped();

   if(m_profiler.Enabled() && m_profiler.Count() > 0)
      QmeLogMsg(QME_LOG_INFO, "Engine", "profile: " + m_profiler.Report());
   QmeLogMsg(QME_LOG_INFO, "Engine", "funnel: " + m_funnel.Summary());
   QmeLogMsg(QME_LOG_INFO, "Engine", m_shutdown.Report());
   m_ready = false;
  }

//------------------------------------------------------------------//
void CEngine::RestoreState(void)
  {
   if(!m_cfg.In.persistState) return;

   string err = "";
   string payload = "";
   if(!m_checkpoint.Load(payload, err))
     {
      QmeLogMsg(QME_LOG_INFO, "Engine", "starting clean: " + err);
      return;
     }

   const SRecoveryReport rep = CStateRecovery::Apply(payload, *m_account.State(), m_positions,
                                                     m_history, m_dedup,
                                                     *m_gateway.Idempotency(), m_memory,
                                                     m_cfg.In.magic);
   if(!rep.loaded) return;

   //--- reconcile restored positions against the broker again
   const int stale = m_positions.ReconcileWithBroker(m_cfg.In.magic);
   if(stale > 0)
      QmeLogMsg(QME_LOG_WARN, "Engine", IntegerToString(stale) +
                " restored position(s) no longer exist at the broker");

   m_memory.Inc("recoveries");
   QmeLogMsg(QME_LOG_INFO, "Engine", "state restored: " + rep.note);
  }

//------------------------------------------------------------------//
void CEngine::SaveCheckpoint(const datetime now)
  {
   if(!m_checkpoint.Due(now)) return;
   string err = "";
   const string payload = CStateRecovery::Compose(*m_account.State(), m_positions, m_history,
                                                  m_dedup, *m_gateway.Idempotency(), m_memory);
   if(m_checkpoint.Save(payload, now, err))
      m_scheduler.MarkCheckpoint(now);
   else
     {
      m_errors++;
      QmeLogMsg(QME_LOG_WARN, "Engine", "checkpoint failed: " + err);
     }
  }

//------------------------------------------------------------------//
bool CEngine::ApplySignalState(const ulong id, const ENUM_QME_SIGNAL_STATE to,
                               const ENUM_QME_REJECT reason, const string note)
  {
   STradingSignal sig;
   if(!m_registry.Get(id, sig)) return(false);
   if(!m_lifecycle.Transition(sig, to, reason, note, TimeCurrent())) return(false);
   return(m_registry.Update(sig));
  }

//------------------------------------------------------------------//
//| Deterministic per-symbol fingerprint of the analysed state.           |
//|                                                                   |
//| Same inputs, same digest: this is what makes two runs comparable      |
//| without replaying the ticks. Written at debug level only.             |
//+------------------------------------------------------------------//
void CEngine::RecordCanonical(const CSymbolRuntime &rt)
  {
   SCanonicalSnapshot snap;
   QmeCanonicalClear(snap);
   snap.cycle      = m_cycles;
   snap.time       = TimeCurrent();
   snap.symbol     = rt.symbol;
   snap.tf         = m_cfg.In.tfEntry;
   snap.price      = rt.analysis[4].price;
   snap.atr        = rt.analysis[4].atr;
   snap.bias       = rt.analysis[4].bias.side;
   snap.biasScore  = rt.analysis[4].bias.score;
   snap.zoneCount  = rt.zones.ActiveCount(TimeCurrent());
   snap.session    = rt.analysis[4].session.session;
   snap.digest     = CCanonicalSnapshot::Digest(snap);
   m_memory.Inc("canonical_frames");

   if(m_cfg.In.logLevel <= QME_LOG_DEBUG)
      QmeLogMsg(QME_LOG_DEBUG, "Engine", "canonical " + CCanonicalSnapshot::Serialize(snap));
  }

//------------------------------------------------------------------//
//| Store the broker identity on the signal before its state advances.   |
//+------------------------------------------------------------------//
void CEngine::AttachTickets(const ulong id, const SExecutionResult &res)
  {
   STradingSignal sig;
   if(!m_registry.Get(id, sig)) return;
   sig.positionTicket = res.positionTicket;
   sig.orderTicket = res.orderTicket;
   sig.dealTicket = res.dealTicket;
   sig.execState = res.state;
   sig.attempts = res.attempts;
   m_registry.Update(sig);
  }

//------------------------------------------------------------------//
//| Expiry + monitoring bookkeeping. Runs every cycle and every timer.   |
//+------------------------------------------------------------------//
void CEngine::MaintainSignals(void)
  {
   const datetime now = TimeCurrent();
   int expired = 0;

   //--- expiry is per symbol because it needs that symbol's zones and price
   for(int i = 0; i < m_scanner.Count(); i++)
     {
      CSymbolRuntime *rt = m_scanner.At(i);
      if(rt == NULL) continue;
      const double price = rt.snapshot.bid > 0.0 ? rt.snapshot.bid : rt.analysis[4].price;
      expired += CSignalExpiry::Process(m_registry, m_lifecycle, rt.zones, now, price);
     }
   if(expired > 0) m_memory.Inc("signals_expired", expired);

   //--- an executed signal whose position exists is under management
   const int total = m_registry.Count();
   for(int i = 0; i < total; i++)
     {
      STradingSignal sig;
      if(!m_registry.At(i, sig)) continue;
      if(sig.state != QME_SIG_EXECUTED) continue;
      if(sig.positionTicket == 0) continue;
      if(!PositionSelectByTicket(sig.positionTicket)) continue;
      ApplySignalState(sig.id, QME_SIG_MONITORING, QME_REJ_NONE,
                       "position " + IntegerToString((long)sig.positionTicket) + " under management");
     }

   //--- keep the registry small: terminal records older than a day are history
   const int pruned = m_registry.RemoveTerminalOlderThan(now - 86400);
   if(pruned > 0) m_memory.Inc("signals_pruned", pruned);
  }

//------------------------------------------------------------------//
//| Position maintenance. Only ever TIGHTENS protection.                  |
//|                                                                   |
//| Break-even is disabled by default (breakEvenAtR == 0). When enabled,  |
//| the stop is moved to the entry price once the trade has earned N x R.  |
//| A position without any stop is never given a guessed level: it is      |
//| reported as a critical issue instead.                               |
//+------------------------------------------------------------------//
void CEngine::ManagePositions(void)
  {
   if(m_cfg.In.breakEvenAtR <= 0.0) return;

   for(int i = 0; i < m_positions.Count(); i++)
     {
      STrackedPosition p;
      if(!m_positions.At(i, p)) continue;
      if(p.closed) continue;
      if(!PositionSelectByTicket(p.ticket)) continue;

      const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      const double curSL = PositionGetDouble(POSITION_SL);
      const double curTP = PositionGetDouble(POSITION_TP);
      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);

      //--- keep the stored record in sync with the broker
      if(curSL > 0.0 && (MathAbs(curSL - p.sl) > QME_PRICE_EPS ||
                         MathAbs(curTP - p.tp) > QME_PRICE_EPS))
         m_positions.UpdateStops(p.ticket, curSL, curTP);

      if(curSL <= 0.0)
        {
         //--- never invent a level: this is an operator problem
         QmeLogMsg(QME_LOG_ERROR, "Engine", "position " +
                   IntegerToString((long)p.ticket) + " has no stop loss; break-even not applied");
         continue;
        }

      const double stopDistance = MathAbs(entry - curSL);
      if(stopDistance <= 0.0) continue;

      //--- already at or beyond break-even?
      if(isBuy && curSL >= entry - QME_PRICE_EPS) continue;
      if(!isBuy && curSL <= entry + QME_PRICE_EPS) continue;

      MqlTick tick;
      if(!SymbolInfoTick(p.symbol, tick)) continue;
      const double current = isBuy ? tick.bid : tick.ask;
      if(current <= 0.0) continue;

      const double profit = isBuy ? (current - entry) : (entry - current);
      if(profit < m_cfg.In.breakEvenAtR * stopDistance) continue;

      CSymbolRuntime *rt = m_scanner.Find(p.symbol);
      if(rt == NULL) continue;

      string why = "";
      if(CTradeManager::TightenStop(p.ticket, entry, rt.spec, why))
        {
         m_positions.UpdateStops(p.ticket, entry, curTP);
         m_memory.Inc("break_even_moves");
         QmeLogMsg(QME_LOG_INFO, "Engine", "break-even: position " +
                   IntegerToString((long)p.ticket) + " stop moved to " +
                   DoubleToString(entry, rt.spec.digits));
        }
      else if(StringLen(why) > 0)
         QmeLogMsg(QME_LOG_DEBUG, "Engine", "break-even skipped: " + why);
     }
  }

//------------------------------------------------------------------//
//| Optional: close an opposite position once the new one is filled.      |
//| Off by default. Runs AFTER a successful entry, never before, so a      |
//| failed entry can never leave the account flat by mistake.              |
//+------------------------------------------------------------------//
void CEngine::CloseOppositePositions(const STradePlan &plan)
  {
   if(!m_cfg.In.closeOnOppositeSignal) return;

   for(int i = 0; i < m_positions.Count(); i++)
     {
      STrackedPosition p;
      if(!m_positions.At(i, p)) continue;
      if(p.closed) continue;
      if(p.symbol != plan.symbol) continue;
      if(p.side == plan.side) continue;
      if(!PositionSelectByTicket(p.ticket)) continue;

      CSymbolRuntime *rt = m_scanner.Find(p.symbol);
      if(rt == NULL) continue;

      string why = "";
      if(CTradeManager::ClosePosition(p.ticket, 0.0, rt.spec, m_cfg.In.deviationPoints, why))
        {
         m_positions.Close(p.ticket);
         QmeLogMsg(QME_LOG_INFO, "Engine", "closed opposite position " +
                   IntegerToString((long)p.ticket) + " after a new " +
                   QmeSideName(plan.side) + " entry on " + plan.symbol);
        }
      else
         QmeLogMsg(QME_LOG_WARN, "Engine", "could not close opposite position " +
                   IntegerToString((long)p.ticket) + ": " + why);
     }
  }

//------------------------------------------------------------------//
SSignalRecord CEngine::MakeHistoryRecord(const STradingSignal &s, const ENUM_QME_REJECT reason)
  {
   SSignalRecord r;
   r.id = s.id;
   r.symbol = s.symbol;
   r.side = s.side;
   r.finalState = s.state;
   r.reason = reason;
   r.score = s.score;
   r.rr = s.rr;
   r.opened = s.created;
   r.closed = TimeCurrent();
   r.fingerprint = s.fingerprint;
   return(r);
  }

//------------------------------------------------------------------//
void CEngine::RecordDecision(const SDecision &d, const long cycle)
  {
   SReplayFrame f;
   QmeReplayFrameClear(f);
   f.cycle = cycle;
   f.time = d.time;
   f.symbol = d.symbol;
   f.side = d.side;
   f.score = d.score;
   f.rr = d.plan.rr;
   f.riskPct = d.risk.riskPct;
   f.approved = (d.verdict == QME_DEC_APPROVED);
   f.reason = d.reason;
   f.fingerprint = d.plan.fingerprint;
   m_replay.Record(f);

   if(!f.approved) m_rejections++;
  }

//------------------------------------------------------------------//
void CEngine::TrackingAfterExecution(const STradePlan &plan, const SExecutionResult &res)
  {
   if(!res.confirmed) return;
   STrackedPosition p;
   p.ticket = res.positionTicket;
   p.symbol = plan.symbol;
   p.side = plan.side;
   p.volume = res.filledVolume > 0.0 ? res.filledVolume : plan.volume;
   p.entry = res.filledPrice > 0.0 ? res.filledPrice : plan.entry;
   p.sl = plan.stopLoss;
   p.tp = plan.takeProfit;
   p.signalId = plan.signalId;
   p.opened = TimeCurrent();
   p.closed = false;
   if(p.ticket > 0) m_positions.Track(p);
  }

//------------------------------------------------------------------//
bool CEngine::HandleExecution(const SDecision &d, CSymbolRuntime &rt)
  {
   SExecutionResult res;
   m_execStats.RecordAttempt(d.plan.symbol);
   if(!m_gateway.Execute(d.plan, rt.spec, m_cfg, res))
     {
      m_execStats.RecordReject(d.plan.symbol);
      m_errors++;
      ApplySignalState(d.signalId, QME_SIG_EXECUTION_FAILED, res.reject,
                       StringLen(res.comment) > 0 ? res.comment : "execution failed");
      return(false);
     }

   m_trades++;
   m_execStats.RecordFill(d.plan.symbol, res.filledVolume > 0.0 ? res.filledVolume : d.plan.volume);
   TrackingAfterExecution(d.plan, res);
   AttachTickets(d.signalId, res);
   ApplySignalState(d.signalId, QME_SIG_EXECUTION_PENDING, QME_REJ_NONE, "sent to broker");
   ApplySignalState(d.signalId, QME_SIG_EXECUTED, QME_REJ_NONE,
                    "ticket " + IntegerToString((long)res.positionTicket));
   CloseOppositePositions(d.plan);
   m_scheduler.Cooldown(d.plan.symbol, TimeCurrent(), m_cfg.In.cooldownSecPerSymbol);
   return(true);
  }

//------------------------------------------------------------------//
bool CEngine::Cycle(const bool force, string &note)
  {
   note = "";
   if(!m_ready)
     {
      note = "engine not ready";
      return(false);
     }
   //--- re-entrancy guard: a cycle can never run inside another cycle
   if(m_inCycle)
     {
      note = "re-entrant cycle skipped";
      QmeLogMsg(QME_LOG_DEBUG, "Engine", note);
      return(false);
     }
   m_inCycle = true;

   const int pCycle = m_profiler.Section("cycle");
   m_profiler.Begin(pCycle);
   m_funnel.CycleBegin();

   m_cycles++;
   m_clock.Refresh();
   if(!m_account.Refresh())
     {
      m_errors++;
      m_controller.Fault("account refresh failed");
      note = "account refresh failed";
      m_inCycle = false;
      return(false);
     }

   if(!m_scheduler.ScanDue(TimeCurrent()))
     {
      note = "scan not due";
      m_inCycle = false;
      return(true);
     }
   m_scheduler.MarkScan(TimeCurrent());

   string scanNote = "";
   if(!m_scanner.Scan(force, scanNote))
     {
      m_errors++;
      note = "scan: " + scanNote;
      m_inCycle = false;
      return(false);
     }

   m_funnel.Pass(m_funnel.Stage("scan"));

   const SSessionResult session = m_scanner.Session();
   const SAccountContext acc = m_account.Snapshot();

   string tradeWhy = "";
   const bool mayTrade = m_controller.MayTrade(m_cfg, acc, session.tradingAllowed, tradeWhy);

   int approvedThisCycle = 0;
   int signalsThisCycle = 0;

   for(int i = 0; i < m_scanner.Count(); i++)
     {
      CSymbolRuntime *rt = m_scanner.At(i);
      if(rt == NULL) continue;
      if(!rt.snapshot.dataValid) continue;
      if(m_scheduler.IsCooling(rt.symbol, TimeCurrent())) continue;

      m_funnel.Pass(m_funnel.Stage("symbol"));
      RecordCanonical(*rt);

      STradingSignal sigs[];
      const int n = m_signals.Generate(rt.analysis[1], rt.analysis[2], rt.analysis[3],
                                       rt.analysis[4], rt.zones, rt.spec, m_cfg,
                                       m_registry, sigs);
      if(n <= 0) continue;

      for(int k = 0; k < n; k++)
        {
         signalsThisCycle++;
         m_signalsTotal++;

         SDecision dec;
         const double atr = rt.analysis[4].atr > 0.0 ? rt.analysis[4].atr : rt.analysis[3].atr;
         const double spread = rt.snapshot.spreadPoints;

         if(!mayTrade)
           {
            QmeDecisionClear(dec);
            dec.signalId = sigs[k].id;
            dec.symbol = sigs[k].symbol;
            dec.side = sigs[k].side;
            dec.score = sigs[k].score;
            dec.time = TimeCurrent();
            dec.verdict = QME_DEC_DEFERRED;
            dec.reason = QME_REJ_DISABLED_BY_CONFIG;
            dec.note = tradeWhy;
            RecordDecision(dec, m_cycles);
            m_history.Add(MakeHistoryRecord(sigs[k], QME_REJ_DISABLED_BY_CONFIG));
            m_funnel.Drop(m_funnel.Stage("trading"), QmeRejectName(QME_REJ_DISABLED_BY_CONFIG));
            continue;
           }

         if(!m_decisions.Decide(sigs[k], rt.spec, m_cfg, session.session,
                                session.tradingAllowed, atr, spread, dec))
           {
            RecordDecision(dec, m_cycles);
            m_history.Add(MakeHistoryRecord(sigs[k], dec.reason));
            m_funnel.Drop(m_funnel.Stage("decision"), QmeRejectName(dec.reason));
            continue;
           }

         RecordDecision(dec, m_cycles);
         m_funnel.Pass(m_funnel.Stage("decision"));
         if(HandleExecution(dec, *rt))
           {
            approvedThisCycle++;
            m_history.Add(MakeHistoryRecord(sigs[k], QME_REJ_NONE));
            m_funnel.Pass(m_funnel.Stage("executed"));
           }
         else
           {
            m_history.Add(MakeHistoryRecord(sigs[k], QME_REJ_EXECUTION_FAILED));
            m_funnel.Drop(m_funnel.Stage("executed"), "execution failed");
           }
        }
     }

   MaintainSignals();
   SaveCheckpoint(TimeCurrent());

   if(m_scheduler.HeartbeatDue(TimeCurrent()))
     {
      m_scheduler.MarkHeartbeat(TimeCurrent());
      QmeLogMsg(QME_LOG_INFO, "Engine", Status());
     }

   note = "cycle " + IntegerToString((int)m_cycles) + ": " + IntegerToString(signalsThisCycle) +
          " signal(s), " + IntegerToString(approvedThisCycle) + " executed";
   m_profiler.End(pCycle);
   m_inCycle = false;
   return(true);
  }

//------------------------------------------------------------------//
bool CEngine::OnTick(void)
  {
   string note = "";
   const bool ok = Cycle(false, note);
   if(!ok && StringLen(note) > 0)
      QmeLogMsg(QME_LOG_WARN, "Engine", note);
   return(ok);
  }

//------------------------------------------------------------------//
void CEngine::OnTimer(void)
  {
   if(!m_ready) return;
   if(m_shutdown.Requested()) return;

   const datetime now = TimeCurrent();
   if(m_scheduler.CheckpointDue(now)) SaveCheckpoint(now);

   //--- positions that disappeared at the broker are closed in our books
   m_positions.ReconcileWithBroker(m_cfg.In.magic);
   ManagePositions();
   MaintainSignals();
  }

//------------------------------------------------------------------//
void CEngine::OnTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                            const MqlTradeResult &result)
  {
   if(!m_ready) return;
   SExecutionResult res;
   if(!m_transactions.Handle(trans, request, result, res)) return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && res.positionTicket > 0)
     {
      STrackedPosition p;
      if(m_positions.Read(res.positionTicket, p))
        {
         m_positions.UpdateStops(res.positionTicket, p.sl, p.tp);
        }
     }
  }

//------------------------------------------------------------------//
string CEngine::Status(void)
  {
   const SAccountContext acc = m_account.Snapshot();
   return(m_controller.Describe() +
          " | cycles=" + IntegerToString((int)m_cycles) +
          " trades=" + IntegerToString((int)m_trades) +
          " errors=" + IntegerToString((int)m_errors) +
          " | " + m_scanner.Describe() +
          " | equity=" + QmeFmtMoney(acc.equity) +
          " | " + m_risk.Describe() +
          " | " + m_gateway.Describe() +
          " | " + m_checkpoint.Describe() +
          (m_profiler.Enabled() ? " | " + m_profiler.Report() : ""));
  }

#endif // __QME_RUNTIME_ENGINE_MQH__
//+------------------------------------------------------------------+
