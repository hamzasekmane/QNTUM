//+------------------------------------------------------------------+
//|                                              Risk/RiskEngine      |
//|  Owns the risk decision for one signal: sizing + full validation.     |
//|                                                                   |
//|  CONTRACT                                                         |
//|    bool Evaluate(signal, spec, cfg, session, atr, spreadPoints,       |
//|                  plan, assessment)                                   |
//|  On success `plan.riskPassed` and `plan.authorized` are set and the    |
//|  plan carries a broker-legal volume and protective stop.               |
//|  On failure the assessment states the exact reason; no plan is ever    |
//|  emitted with volume > 0 and passed == false.                          |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_ENGINE_MQH__
#define __QME_RISK_ENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountContext.mqh"
#include "../Account/AccountState.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "RiskBudget.mqh"
#include "PortfolioRisk.mqh"
#include "PreTradeValidator.mqh"

class CRiskEngine
  {
private:
   CAccountContext   *m_account;
   CPortfolioSnapshot m_portfolio;
   ulong              m_magic;
   long               m_passed;
   long               m_rejected;
   ENUM_QME_REJECT    m_lastReject;
   string             m_lastRejectNote;

public:
                     CRiskEngine(void);
   void              Init(CAccountContext *account, const ulong magic);
   void              Shutdown(void);

   //--- sizing only (used by the analysis/simulation mode)
   double            SizePosition(const STradingSignal &s, const SSymbolSpec &spec,
                                  const double equity, const double riskPct);

   bool              Evaluate(const STradingSignal &s, const SSymbolSpec &spec,
                              const CConfig &cfg, const ENUM_QME_SESSION session,
                              const bool sessionAllowed, const double atr,
                              const double spreadPoints, STradePlan &plan,
                              SRiskAssessment &out);

   void              RefreshPortfolio(void);
   CPortfolioSnapshot* Portfolio(void) { return(&m_portfolio); }
   long              Passed(void) { return(m_passed); }
   long              Rejected(void) { return(m_rejected); }
   ENUM_QME_REJECT   LastReject(void) { return(m_lastReject); }
   string            LastRejectNote(void) { return(m_lastRejectNote); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CRiskEngine::CRiskEngine(void)
  {
   m_account = NULL;
   m_magic = 0;
   m_passed = 0;
   m_rejected = 0;
   m_lastReject = QME_REJ_NONE;
   m_lastRejectNote = "";
  }

//------------------------------------------------------------------//
void CRiskEngine::Init(CAccountContext *account, const ulong magic)
  {
   m_account = account;
   m_magic = magic;
   m_portfolio.Clear();
   QmeLogMsg(QME_LOG_INFO, "Risk", "risk engine initialised for magic " +
             IntegerToString((long)magic));
  }

void CRiskEngine::Shutdown(void)
  {
   m_portfolio.Clear();
   QmeLogMsg(QME_LOG_INFO, "Risk", "risk engine stopped (passed=" +
             IntegerToString((int)m_passed) + " rejected=" +
             IntegerToString((int)m_rejected) + ")");
  }

//------------------------------------------------------------------//
void CRiskEngine::RefreshPortfolio(void)
  {
   const double equity = (m_account != NULL) ? m_account.Equity() : 0.0;
   m_portfolio.Build(m_magic, equity);
  }

//------------------------------------------------------------------//
double CRiskEngine::SizePosition(const STradingSignal &s, const SSymbolSpec &spec,
                                 const double equity, const double riskPct)
  {
   if(equity <= 0.0 || riskPct <= 0.0) return(0.0);
   const double stopDistance = MathAbs(s.entry - s.stopLoss);
   if(stopDistance <= 0.0) return(0.0);
   const double riskMoney = equity * riskPct / 100.0;
   return(CRiskBudget::VolumeForRisk(spec, riskMoney, stopDistance));
  }

//------------------------------------------------------------------//
bool CRiskEngine::Evaluate(const STradingSignal &s, const SSymbolSpec &spec,
                           const CConfig &cfg, const ENUM_QME_SESSION session,
                           const bool sessionAllowed, const double atr,
                           const double spreadPoints, STradePlan &plan,
                           SRiskAssessment &out)
  {
   QmeRiskClear(out);
   QmePlanClear(plan);

   if(m_account == NULL)
     {
      out.reason = QME_REJ_INTERNAL;
      out.note = "risk engine has no account context";
      m_rejected++;
      return(false);
     }

   const SAccountContext acc = m_account.Snapshot();
   RefreshPortfolio();

   //--- 1. size the position from the signal's own stop
   const double stopDistance = MathAbs(s.entry - s.stopLoss);
   if(stopDistance <= 0.0)
     {
      out.reason = QME_REJ_SL_INVALID;
      out.note = "stop distance is zero";
      m_rejected++;
      m_lastReject = out.reason;
      m_lastRejectNote = out.note;
      return(false);
     }

   const double riskMoney = CRiskBudget::RiskMoney(acc, cfg.In.riskPerTradePct);
   const double volume = CRiskBudget::VolumeForRisk(spec, riskMoney, stopDistance);
   if(volume <= 0.0)
     {
      out.reason = QME_REJ_VOLUME_INVALID;
      out.note = "cannot size a volume within the broker limits for a risk of " +
                 QmeFmtMoney(riskMoney);
      out.riskMoney = riskMoney;
      out.stopDistance = stopDistance;
      m_rejected++;
      m_lastReject = out.reason;
      m_lastRejectNote = out.note;
      return(false);
     }

   //--- 2. build the plan (normalised prices, broker-legal volume).
   //--- Built here rather than in the strategy layer so the risk engine has
   //--- no dependency on Strategy/*; the plan is the transport object only.
   QmePlanClear(plan);
   plan.signalId = s.id;
   plan.symbol = s.symbol;
   plan.side = s.side;
   plan.entryType = s.entryType;
   plan.entry = CSymbolSpecifications::NormalizePrice(spec, s.entry);
   plan.stopLoss = CSymbolSpecifications::NormalizePrice(spec, s.stopLoss);
   plan.takeProfit = CSymbolSpecifications::NormalizePrice(spec, s.takeProfit1);
   plan.volume = volume;
   plan.riskMoney = CRiskBudget::ActualRiskMoney(spec, volume, stopDistance);
   plan.rr = QmeComputeRR(plan.side, plan.entry, plan.stopLoss, plan.takeProfit);
   plan.score = s.score;
   plan.magic = m_magic;
   plan.accountMode = acc.mode;
   plan.fingerprint = s.fingerprint;
   plan.created = TimeCurrent();
   plan.authorized = false;
   plan.riskPassed = false;
   plan.reject = QME_REJ_NONE;
   if(plan.signalId == 0 || plan.volume <= 0.0)
     {
      out.reason = QME_REJ_VOLUME_INVALID;
      out.note = "plan could not be built";
      m_rejected++;
      m_lastReject = out.reason;
      m_lastRejectNote = out.note;
      return(false);
     }

   //--- 3. full pre-trade validation
   const bool ok = CPreTradeValidator::Validate(plan, spec, acc, *m_account.State(),
                                                m_portfolio, cfg, session, sessionAllowed,
                                                atr, spreadPoints, out);
   if(!ok)
     {
      m_rejected++;
      m_lastReject = out.reason;
      m_lastRejectNote = out.note;
      QmeLogMsg(QME_LOG_WARN, "Risk", s.symbol + " " + QmeSideName(s.side) +
                " rejected: " + QmeRejectName(out.reason) + " - " + out.note);
      plan.riskPassed = false;
      plan.authorized = false;
      plan.reject = out.reason;
      return(false);
     }

   plan.riskPassed = true;
   plan.reject = QME_REJ_NONE;
   m_passed++;
   return(true);
  }

//------------------------------------------------------------------//
string CRiskEngine::Describe(void)
  {
   return("risk passed=" + IntegerToString((int)m_passed) +
          " rejected=" + IntegerToString((int)m_rejected) +
          " open=" + IntegerToString(m_portfolio.Count()) +
          " openRisk=" + QmeFmtMoney(m_portfolio.TotalRiskMoney()) +
          " notional=" + QmeFmtMoney(m_portfolio.TotalNotional()) +
          (m_lastReject != QME_REJ_NONE ?
           " lastReject=" + QmeRejectName(m_lastReject) + " (" + m_lastRejectNote + ")" : ""));
  }

#endif // __QME_RISK_ENGINE_MQH__
//+------------------------------------------------------------------+
