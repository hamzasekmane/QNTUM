//+------------------------------------------------------------------+
//|                                        Strategy/DecisionEngine    |
//|  Converts a generated signal into an APPROVED or REJECTED decision.  |
//|                                                                   |
//|  This is the boundary between "the setup looks good" and "we are      |
//|  allowed to trade it". Nothing crosses it without passing the full    |
//|  risk engine, and the reason for every refusal is preserved so the    |
//|  dashboard can explain why a signal did not become a trade.           |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_DECISION_MQH__
#define __QME_STRATEGY_DECISION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Logger.mqh"
#include "../Risk/RiskEngine.mqh"
#include "SignalTypes.mqh"
#include "SignalRegistry.mqh"
#include "SignalLifecycle.mqh"

enum ENUM_QME_DECISION
  {
   QME_DEC_NONE = 0,
   QME_DEC_APPROVED,
   QME_DEC_REJECTED,
   QME_DEC_DEFERRED
  };

struct SDecision
  {
   ulong             signalId;
   string            symbol;
   ENUM_QME_SIDE     side;
   ENUM_QME_DECISION verdict;
   ENUM_QME_REJECT   reason;
   string            note;
   double            score;
   datetime          time;
   STradePlan        plan;
   SRiskAssessment   risk;
  };

void QmeDecisionClear(SDecision &d)
  {
   d.signalId = 0;
   d.symbol = "";
   d.side = QME_SIDE_NONE;
   d.verdict = QME_DEC_NONE;
   d.reason = QME_REJ_NONE;
   d.note = "";
   d.score = 0.0;
   d.time = 0;
   QmePlanClear(d.plan);
   QmeRiskClear(d.risk);
  }

class CDecisionEngine
  {
private:
   CRiskEngine       *m_risk;
   CSignalRegistry   *m_registry;
   CSignalLifecycle   m_lifecycle;
   long               m_approved;
   long               m_rejected;
   long               m_deferred;

public:
                     CDecisionEngine(void);
   bool              Init(CRiskEngine *risk, CSignalRegistry *registry, string &err);
   void              Shutdown(void);

   bool              ApplyState(const ulong id, const ENUM_QME_SIGNAL_STATE to,
                               const ENUM_QME_REJECT reason, const string note);
   bool              Decide(const STradingSignal &s, const SSymbolSpec &spec,
                            const CConfig &cfg, const ENUM_QME_SESSION session,
                            const bool sessionAllowed, const double atr,
                            const double spreadPoints, SDecision &out);

   long              Approved(void) { return(m_approved); }
   long              Rejected(void) { return(m_rejected); }
   long              Deferred(void) { return(m_deferred); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CDecisionEngine::CDecisionEngine(void)
  {
   m_risk = NULL;
   m_registry = NULL;
   m_approved = 0;
   m_rejected = 0;
   m_deferred = 0;
  }

//------------------------------------------------------------------//
bool CDecisionEngine::Init(CRiskEngine *risk, CSignalRegistry *registry, string &err)
  {
   err = "";
   if(risk == NULL) { err = "decision engine needs a risk engine"; return(false); }
   m_risk = risk;
   m_registry = registry;
   m_approved = 0; m_rejected = 0; m_deferred = 0;
   return(true);
  }

void CDecisionEngine::Shutdown(void)
  {
   QmeLogMsg(QME_LOG_INFO, "Decision", Describe());
  }

//------------------------------------------------------------------//
//| Apply a state change through the single legal mutator.               |
//+------------------------------------------------------------------//
bool CDecisionEngine::ApplyState(const ulong id, const ENUM_QME_SIGNAL_STATE to,
                                 const ENUM_QME_REJECT reason, const string note)
  {
   if(m_registry == NULL) return(false);
   STradingSignal sig;
   if(!m_registry.Get(id, sig)) return(false);
   if(!m_lifecycle.Transition(sig, to, reason, note, TimeCurrent())) return(false);
   return(m_registry.Update(sig));
  }

//------------------------------------------------------------------//
bool CDecisionEngine::Decide(const STradingSignal &s, const SSymbolSpec &spec,
                             const CConfig &cfg, const ENUM_QME_SESSION session,
                             const bool sessionAllowed, const double atr,
                             const double spreadPoints, SDecision &out)
  {
   QmeDecisionClear(out);
   out.signalId = s.id;
   out.symbol = s.symbol;
   out.side = s.side;
   out.score = s.score;
   out.time = TimeCurrent();

   if(m_risk == NULL)
     {
      out.verdict = QME_DEC_REJECTED;
      out.reason = QME_REJ_INTERNAL;
      out.note = "decision engine has no risk engine";
      m_rejected++;
      return(false);
     }

   //--- the strategy's own confidence floor is re-checked here: a signal that
   //--- slipped under the floor (score updated after generation) never trades
   if(s.score < cfg.In.minScore)
     {
      out.verdict = QME_DEC_REJECTED;
      out.reason = QME_REJ_LOW_SCORE;
      out.note = "score " + QmeFmt(s.score, 1) + " < " + QmeFmt(cfg.In.minScore, 1);
      m_rejected++;
      return(false);
     }

   const bool riskOk = m_risk.Evaluate(s, spec, cfg, session, sessionAllowed, atr,
                                       spreadPoints, out.plan, out.risk);
   if(!riskOk)
     {
      out.verdict = QME_DEC_REJECTED;
      out.reason = out.risk.reason;
      out.note = out.risk.note;
      m_rejected++;
      ApplyState(s.id, QME_SIG_REJECTED, out.reason, out.note);
      return(false);
     }

   out.verdict = QME_DEC_APPROVED;
   out.reason = QME_REJ_NONE;
   out.note = "risk passed, " + IntegerToString(out.risk.checksRun) + " checks";
   m_approved++;

   ApplyState(s.id, QME_SIG_APPROVED, QME_REJ_NONE, out.note);
   return(true);
  }

//------------------------------------------------------------------//
string CDecisionEngine::Describe(void)
  {
   return("decisions approved=" + IntegerToString((int)m_approved) +
          " rejected=" + IntegerToString((int)m_rejected) +
          " deferred=" + IntegerToString((int)m_deferred));
  }

#endif // __QME_STRATEGY_DECISION_MQH__
//+------------------------------------------------------------------+
