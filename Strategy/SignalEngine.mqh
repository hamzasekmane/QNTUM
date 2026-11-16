//+------------------------------------------------------------------+
//|                                        Strategy/SignalEngine      |
//|  The strategy orchestrator for ONE symbol.                          |
//|                                                                   |
//|  Pipeline:                                                        |
//|   CandidateCollector -> CandidateClusterer -> MtfConfluence ->      |
//|   SetupEngine -> EntryEngine -> ScoringEngine -> SignalQuality ->   |
//|   SignalRegistry (DETECTED -> EVALUATING -> APPROVED / REJECTED)    |
//|                                                                   |
//|  Every rejected hypothesis is recorded with its exact reason: the     |
//|  engine never drops a candidate silently.                             |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SIGNALENGINE_MQH__
#define __QME_STRATEGY_SIGNALENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "../Zones/ZoneEngine.mqh"
#include "../Intelligence/ScoringEngine.mqh"
#include "../Intelligence/MtfConfluenceEngine.mqh"
#include "../Intelligence/SignalQualityEngine.mqh"
#include "MTF/CandidateCollector.mqh"
#include "MTF/CandidateClusterer.mqh"
#include "MTF/EntryEngine.mqh"
#include "SetupEngine.mqh"
#include "SignalTypes.mqh"
#include "SignalRegistry.mqh"
#include "SignalLifecycle.mqh"
#include "SignalDeduplicator.mqh"
#include "StrategyRegistry.mqh"

class CSignalEngine
  {
private:
   CScoringEngine    *m_scorer;
   CStrategyRegistry *m_strategies;
   CSignalLifecycle  *m_lifecycle;
   CSignalDeduplicator *m_dedup;
   long               m_sequence;

   //--- funnel counters (prove nothing is dropped)
   long               m_hyps;
   long               m_merged;
   long               m_setupFail;
   long               m_entryFail;
   long               m_qualityFail;
   long               m_approved;
   string             m_lastOutcome;
   SCandidateRejectCounts m_lastCandidateRejects;

   //--- bounded closed-bar deterministic rejection cache (prevents 5s log/registry spam)
   string             m_rejectFp[64];
   datetime           m_rejectEntryBar[64];
   ENUM_QME_REJECT    m_rejectReason[64];
   int                m_rejectCount;
   int                m_rejectHead;

   static bool        IsDeterministicReject(const ENUM_QME_REJECT reason);
   bool               WasRejectedForClosedBars(const string fp, const datetime entryBarTime);
   void               RememberDeterministicReject(const string fp, const datetime entryBarTime,
                                                   const ENUM_QME_REJECT reason);
   bool               RegistryHasFingerprint(CSignalRegistry &registry, const string fp);
   int                BuildViews(const SMarketAnalysis &context, const SMarketAnalysis &bias,
                                 const SMarketAnalysis &structure, const SMarketAnalysis &setup,
                                 const SMarketAnalysis &entryTf,
                                 const ENUM_QME_SIDE side, STfView &views[]);

public:
                     CSignalEngine(void);
   void              Attach(CScoringEngine *scorer, CStrategyRegistry *strategies,
                            CSignalLifecycle *lifecycle, CSignalDeduplicator *dedup);

   int               Generate(const SMarketAnalysis &context, const SMarketAnalysis &bias,
                              const SMarketAnalysis &structure, const SMarketAnalysis &setup,
                              const SMarketAnalysis &entryTf,
                              CZoneEngine &zones, const SSymbolSpec &spec,
                              const CConfig &cfg, const SDataQuality &dq,
                              CSignalRegistry &registry, STradingSignal &out[]);

   string            Stats(void);
   string            LastOutcome(void) { return(m_lastOutcome); }
  };

//------------------------------------------------------------------//
CSignalEngine::CSignalEngine(void)
  {
   m_scorer = NULL;
   m_strategies = NULL;
   m_lifecycle = NULL;
   m_dedup = NULL;
   m_sequence = 0;
   m_hyps = 0;
   m_merged = 0;
   m_setupFail = 0;
   m_entryFail = 0;
   m_qualityFail = 0;
   m_approved = 0;
   m_lastOutcome = "no signal analysis yet";
   m_rejectCount = 0;
   m_rejectHead = 0;
   for(int i = 0; i < 64; i++)
     {
      m_rejectFp[i] = "";
      m_rejectEntryBar[i] = 0;
      m_rejectReason[i] = QME_REJ_NONE;
     }
   QmeCandidateRejectCountsClear(m_lastCandidateRejects);
  }

//------------------------------------------------------------------//
bool CSignalEngine::IsDeterministicReject(const ENUM_QME_REJECT reason)
  {
   switch(reason)
     {
      case QME_REJ_NO_CONFLUENCE:
      case QME_REJ_NO_STRUCTURE:
      case QME_REJ_LOW_SCORE:
      case QME_REJ_INVALIDATED:
      case QME_REJ_RR:
      case QME_REJ_SL_INVALID:
      case QME_REJ_TP_INVALID:
      case QME_REJ_INTERNAL:
         return(true);
     }
   return(false);
  }

bool CSignalEngine::WasRejectedForClosedBars(const string fp, const datetime entryBarTime)
  {
   if(StringLen(fp) == 0 || entryBarTime <= 0) return(false);
   for(int i = 0; i < m_rejectCount; i++)
     {
      if(m_rejectFp[i] == fp && m_rejectEntryBar[i] == entryBarTime)
         return(true);
     }
   return(false);
  }

void CSignalEngine::RememberDeterministicReject(const string fp, const datetime entryBarTime,
                                                const ENUM_QME_REJECT reason)
  {
   if(StringLen(fp) == 0 || entryBarTime <= 0 || !IsDeterministicReject(reason)) return;
   for(int i = 0; i < m_rejectCount; i++)
     {
      if(m_rejectFp[i] == fp)
        {
         m_rejectEntryBar[i] = entryBarTime;
         m_rejectReason[i] = reason;
         return;
        }
     }
   const int slot = (m_rejectCount < 64) ? m_rejectCount++ : m_rejectHead;
   if(m_rejectCount >= 64) m_rejectHead = (m_rejectHead + 1) % 64;
   m_rejectFp[slot] = fp;
   m_rejectEntryBar[slot] = entryBarTime;
   m_rejectReason[slot] = reason;
  }

//------------------------------------------------------------------//
void CSignalEngine::Attach(CScoringEngine *scorer, CStrategyRegistry *strategies,
                           CSignalLifecycle *lifecycle, CSignalDeduplicator *dedup)
  {
   m_scorer = scorer;
   m_strategies = strategies;
   m_lifecycle = lifecycle;
   m_dedup = dedup;
  }

//------------------------------------------------------------------//
bool CSignalEngine::RegistryHasFingerprint(CSignalRegistry &registry, const string fp)
  {
   // Rejected/expired records are not execution claims and may be reevaluated
   // during the same setup bar. Registry itself defines live duplicate states.
   return(registry.HasLiveFingerprint(fp));
  }

//------------------------------------------------------------------//
int CSignalEngine::BuildViews(const SMarketAnalysis &context, const SMarketAnalysis &bias,
                              const SMarketAnalysis &structure, const SMarketAnalysis &setup,
                              const SMarketAnalysis &entryTf,
                              const ENUM_QME_SIDE side, STfView &views[])
  {
   ArrayResize(views, 0);

   // Keep the configured five-timeframe denominator stable. A missing or
   // invalid evidence view contributes zero agreement at its own timeframe
   // weight instead of silently disappearing and inflating confluence.
   STfView v;
   v.tf=context.tf; v.direction=QME_SIDE_NONE; v.strength=0.0;
   if(context.bias.valid && context.bias.side!=QME_SIDE_NONE)
     { v.direction=context.bias.side; v.strength=context.bias.score; }
   else if(context.structure.valid && (context.structure.trend==QME_TREND_UP || context.structure.trend==QME_TREND_DOWN))
     {
      v.direction=(context.structure.trend==QME_TREND_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=0.45;
     }
   ArrayResize(views,ArraySize(views)+1); views[ArraySize(views)-1]=v;

   v.tf=bias.tf; v.direction=QME_SIDE_NONE; v.strength=0.0;
   if(bias.bias.valid && bias.bias.side!=QME_SIDE_NONE)
     { v.direction=bias.bias.side; v.strength=bias.bias.score; }
   else if(bias.structure.valid && (bias.structure.trend==QME_TREND_UP || bias.structure.trend==QME_TREND_DOWN))
     {
      v.direction=(bias.structure.trend==QME_TREND_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=0.45;
     }
   ArrayResize(views,ArraySize(views)+1); views[ArraySize(views)-1]=v;

   v.tf=structure.tf; v.direction=QME_SIDE_NONE; v.strength=0.0;
   if(structure.structure.valid && (structure.structure.trend==QME_TREND_UP || structure.structure.trend==QME_TREND_DOWN))
     {
      v.direction=(structure.structure.trend==QME_TREND_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      const double tStr=structure.trend.valid ? structure.trend.strength : 0.30;
      v.strength=QmeClamp(0.5+0.5*tStr,0.0,1.0);
     }
   else if(structure.trend.valid && (structure.trend.trend==QME_TREND_UP || structure.trend.trend==QME_TREND_DOWN))
     {
      v.direction=(structure.trend.trend==QME_TREND_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=QmeClamp(structure.trend.strength,0.35,1.0);
     }
   ArrayResize(views,ArraySize(views)+1); views[ArraySize(views)-1]=v;

   v.tf=setup.tf; v.direction=QME_SIDE_NONE; v.strength=0.0;
   if(setup.trend.valid && (setup.trend.trend==QME_TREND_UP || setup.trend.trend==QME_TREND_DOWN))
     {
      v.direction=(setup.trend.trend==QME_TREND_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=MathMax(setup.trend.strength,0.45);
     }
   else if(setup.structure.valid && (setup.structure.trend==QME_TREND_UP || setup.structure.trend==QME_TREND_DOWN))
     {
      v.direction=(setup.structure.trend==QME_TREND_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=0.50;
     }
   else if(setup.mss.valid)
     {
      v.direction=(setup.mss.event==QME_STRUCT_MSS_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=0.45;
     }
   else if(setup.bos.valid)
     {
      v.direction=(setup.bos.event==QME_STRUCT_BOS_UP) ? QME_SIDE_BUY : QME_SIDE_SELL;
      v.strength=0.40;
     }
   ArrayResize(views,ArraySize(views)+1); views[ArraySize(views)-1]=v;

   v.tf=entryTf.tf; v.direction=QME_SIDE_NONE; v.strength=0.0;
   if(entryTf.momentum.valid && entryTf.momentum.direction!=QME_SIDE_NONE &&
      MathAbs(entryTf.momentum.value)>0.10)
     {
      v.direction=entryTf.momentum.direction;
      v.strength=QmeClamp(MathAbs(entryTf.momentum.value),0.0,1.0);
     }
   else if(entryTf.displacement.valid && entryTf.displacement.found &&
           entryTf.displacement.side!=QME_SIDE_NONE)
     {
      v.direction=entryTf.displacement.side;
      v.strength=QmeClamp(entryTf.displacement.score,0.35,0.85);
     }
   else if(entryTf.pattern.valid && entryTf.pattern.bias!=QME_SIDE_NONE)
     {
      v.direction=entryTf.pattern.bias;
      v.strength=QmeClamp(entryTf.pattern.quality,0.30,0.75);
     }
   ArrayResize(views,ArraySize(views)+1); views[ArraySize(views)-1]=v;

   if(side==QME_SIDE_NONE) ArrayResize(views,0);
   return(ArraySize(views));
  }

//------------------------------------------------------------------//
int CSignalEngine::Generate(const SMarketAnalysis &context, const SMarketAnalysis &bias,
                            const SMarketAnalysis &structure, const SMarketAnalysis &setup,
                            const SMarketAnalysis &entryTf,
                            CZoneEngine &zones, const SSymbolSpec &spec,
                            const CConfig &cfg, const SDataQuality &dq,
                            CSignalRegistry &registry, STradingSignal &out[])
  {
   ArrayResize(out, 0);
   m_lastOutcome = "no signal candidate";
   if(m_scorer == NULL || m_strategies == NULL || m_lifecycle == NULL)
     {
      m_lastOutcome = "signal engine dependencies not attached";
      return(0);
     }

   const string symbol = setup.symbol;
   const double price = setup.price;
   const double atr = setup.atr;
   const double point = spec.point;
   if(price <= 0.0 || atr <= 0.0)
     { m_lastOutcome = "setup price/ATR unavailable"; return(0); }

   //--- 1. hypotheses per side (setup timeframe)
   SCandidateHypothesis hyps[];
   SCandidateRejectCounts candidateRejects;
   const int nHyps = CCandidateCollector::Collect(context, structure, setup, zones, spec, cfg,
                                                  price, atr, point,
                                                  cfg.In.minRR * 1.1, 4.0,
                                                  hyps, QME_MAX_CANDIDATES,candidateRejects);
   m_lastCandidateRejects = candidateRejects;
   m_hyps += nHyps;
   if(nHyps == 0)
      m_lastOutcome = "no candidates: zone=" + IntegerToString(candidateRejects.noZone) +
                      " sweepGate=" + IntegerToString(candidateRejects.sweepNotConfirmed) +
                      " breakoutGate=" + IntegerToString(candidateRejects.breakoutNotConfirmed) +
                      " entry=" + IntegerToString(candidateRejects.invalidEntry) +
                      " rr=" + IntegerToString(candidateRejects.rrRejected) +
                      " setupStructure=" + IntegerToString(candidateRejects.noSetupStructure);

   //--- 2. one candidate per side
   SMergedCandidate merged[];
   const int nMerged = CCandidateClusterer::Merge(hyps, nHyps, merged, 2);
   m_merged += nMerged;

   for(int i = 0; i < nMerged; i++)
     {
      const string fp = QmeFingerprint(symbol, merged[i].cand.side, merged[i].cand.tf,
                                       (long)merged[i].cand.zoneId, setup.barTime);
      if(RegistryHasFingerprint(registry, fp))
        { m_lastOutcome = "live/unresolved fingerprint blocks duplicate"; continue; }
      // An INTERNAL rejection is deterministic for this closed-bar fingerprint.
      // Suppress repeats until setup.barTime changes; live/unresolved and sent
      // plans retain their stronger registry/idempotency protections above.
      if(registry.HasInternalRejectFingerprint(fp))
        { m_lastOutcome = "identical INTERNAL rejection suppressed until new closed bar"; continue; }
      const datetime cacheBarTime = (entryTf.barTime > 0) ? entryTf.barTime : setup.barTime;
      if(WasRejectedForClosedBars(fp, cacheBarTime))
        { m_lastOutcome = "identical closed-bar rejection suppressed until new bar"; continue; }
      if(m_dedup != NULL && m_dedup.IsDuplicate(fp, cfg.In.cooldownSecPerSymbol, TimeCurrent()))
        { m_lastOutcome = "fingerprint cooldown active"; continue; }

      const string playbook = m_strategies.PlaybookFor(merged[i]);
      if(!m_strategies.IsEnabled(playbook))
        { m_lastOutcome = "playbook disabled: " + playbook; continue; }

      //--- 3. confluence + preliminary score (visible even on SetupGate rejection)
      STfView views[];
      const int nViews = BuildViews(context, bias, structure, setup, entryTf, merged[i].cand.side, views);
      const SConfluenceResult conf = CMtfConfluenceEngine::Evaluate(merged[i].cand.side,
                                                                    views, nViews);

      SFactorBreakdown prelimBreakdown;
      const double prelimScore = m_scorer.Score(merged[i].score, prelimBreakdown);

      //--- 4. setup gate
      const SSetupVerdict verdict = CSetupEngine::Evaluate(merged[i], conf, cfg, dq);

      //--- build the signal record up front so a rejection is recorded, not lost
      STradingSignal sig;
      QmeSignalClear(sig);
      m_sequence++;
      sig.id = CSignalTypes::MakeId(symbol, merged[i].cand.side, merged[i].cand.tf,
                                    merged[i].cand.zoneId, setup.barTime, m_sequence);
      sig.symbol = symbol;
      sig.side = merged[i].cand.side;
      sig.tf = merged[i].cand.tf;
      sig.entryType = merged[i].entry.type;
      sig.entry = merged[i].entry.entry;
      sig.stopLoss = merged[i].entry.stop;
      sig.takeProfit1 = merged[i].entry.target1;
      sig.takeProfit2 = merged[i].entry.target2;
      sig.rr = merged[i].entry.rr;
      sig.riskReward = merged[i].entry.rr;
      sig.zoneId = merged[i].cand.zoneId;
      sig.source = merged[i].cand.source;
      sig.barTime = setup.barTime;
      sig.fingerprint = fp;
      sig.score = prelimScore;
      sig.confidence = conf.score;
      sig.breakdown = prelimBreakdown;
      sig.created = TimeCurrent();
      sig.updated = sig.created;
      sig.expires = sig.created + (datetime)(cfg.In.signalExpiryMinutes * 60);
      sig.state = QME_SIG_DETECTED;
      sig.execState = QME_EXEC_NONE;
      sig.mode = (int)setup.valid;
      sig.reject = QME_REJ_NONE;

      ENUM_QME_REJECT addReject = QME_REJ_NONE;
      string addWhy = "";
      if(!registry.Add(sig, addReject, addWhy))
        {
         QmeLogMsg(QME_LOG_WARN, "SignalEngine", symbol + " signal not stored: " +
                   QmeRejectName(addReject) + " " + addWhy);
         continue;
        }
      m_lifecycle.Transition(sig, QME_SIG_EVALUATING, QME_REJ_NONE, "pipeline", sig.updated);
      registry.Update(sig);

      if(!verdict.ok)
        {
         m_setupFail++;
         m_lastOutcome = "setup rejected: " + QmeRejectName(verdict.reason) + " " + verdict.note;
         m_lifecycle.Transition(sig, QME_SIG_REJECTED, verdict.reason,
                                verdict.note + " playbook=" + playbook, sig.updated);
         registry.Update(sig);
         RememberDeterministicReject(fp, cacheBarTime, verdict.reason);
         continue;
        }

      //--- 5. entry confirmation on the entry timeframe
      const SEntryConfirmation conf2 = CEntryEngine::Confirm(entryTf, merged[i].entry,
                                                             sig.side);
      if(!conf2.confirmed)
        {
         m_entryFail++;
         SScoreInput sc = merged[i].score;
         QmeScoreInputSet(sc, QME_F_ENTRY_CONFIRM, 0.0);
         m_lastOutcome = "entry rejected: " + QmeRejectName(conf2.reason) + " " + conf2.note;
         m_lifecycle.Transition(sig, QME_SIG_REJECTED, conf2.reason,
                                "entry not confirmed: " + conf2.note, sig.updated);
         registry.Update(sig);
         RememberDeterministicReject(fp, cacheBarTime, conf2.reason);
         continue;
        }

      //--- 6. scoring
      SScoreInput score = merged[i].score;
      QmeScoreInputSet(score, QME_F_ENTRY_CONFIRM, conf2.evidence);
      QmeScoreInputPenalty(score, verdict.penalty);

      SFactorBreakdown breakdown;
      const double finalScore = m_scorer.Score(score, breakdown);
      sig.score = finalScore;
      sig.confidence = conf.score;             // confluence, explicitly NOT a probability
      sig.breakdown = breakdown;
      sig.factorMask = 0;
      for(int f = 0; f < (int)QME_F_COUNT; f++)
         if(breakdown.items[f].available &&
            breakdown.items[f].contribution > 0.0)
            sig.factorMask |= CFactorCatalog::Bit((ENUM_QME_FACTOR)f);

      if(finalScore < cfg.In.minScore)
        {
         m_qualityFail++;
         m_lastOutcome = "score rejected: " + QmeFmt(finalScore,1) + " < " + QmeFmt(cfg.In.minScore,1);
         m_lifecycle.Transition(sig, QME_SIG_REJECTED, QME_REJ_LOW_SCORE,
                                "score " + QmeFmt(finalScore, 1) + " < " +
                                QmeFmt(cfg.In.minScore, 1), sig.updated);
         registry.Update(sig);
         RememberDeterministicReject(fp, cacheBarTime, QME_REJ_LOW_SCORE);
         continue;
        }

      //--- 7. signal-level validation (stop/target/rr)
      ENUM_QME_REJECT vReject = QME_REJ_NONE;
      string vWhy = "";
      if(!CSignalTypes::Validate(sig, cfg.In.minRR, vReject, vWhy))
        {
         m_qualityFail++;
         m_lastOutcome = "signal invalid: " + QmeRejectName(vReject) + " " + vWhy;
         m_lifecycle.Transition(sig, QME_SIG_REJECTED, vReject, vWhy, sig.updated);
         registry.Update(sig);
         RememberDeterministicReject(fp, cacheBarTime, vReject);
         continue;
        }

      //--- 8. quality gate
      const double spreadCap = (cfg.In.maxSpreadAtrRatio > 0.0) ? atr / point * cfg.In.maxSpreadAtrRatio : 0.0;
      const SQualityResult q = CSignalQualityEngine::Evaluate(finalScore, conf.score, sig.rr,
                                                              cfg.In.minRR, setup.spreadPoints,
                                                              spreadCap, dq,
                                                              0.55);
      if(!q.acceptable)
        {
         m_qualityFail++;
         m_lastOutcome = "signal quality rejected: " + QmeRejectName(q.reason) + " " + q.note;
         m_lifecycle.Transition(sig, QME_SIG_REJECTED, q.reason, q.note, sig.updated);
         registry.Update(sig);
         RememberDeterministicReject(fp, cacheBarTime, q.reason);
         continue;
        }

      //--- 9. approve
      m_lifecycle.Transition(sig, QME_SIG_APPROVED, QME_REJ_NONE,
                             "score=" + QmeFmt(finalScore, 1) + " conf=" +
                             QmeFmt(conf.score, 2) + " playbook=" + playbook, sig.updated);
      registry.Update(sig);
      m_strategies.RecordSignal(playbook);
      m_approved++;
      m_lastOutcome = "signal approved: " + symbol + " " + QmeSideName(sig.side) +
                      " score=" + QmeFmt(finalScore,1);

      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = sig;
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
string CSignalEngine::Stats(void)
  {
   return("hyp=" + IntegerToString((int)m_hyps) +
          " merged=" + IntegerToString((int)m_merged) +
          " setupFail=" + IntegerToString((int)m_setupFail) +
          " entryFail=" + IntegerToString((int)m_entryFail) +
          " qualityFail=" + IntegerToString((int)m_qualityFail) +
          " approved=" + IntegerToString((int)m_approved) +
          " lastCandidateGates(zone=" + IntegerToString(m_lastCandidateRejects.noZone) +
          ",sweep=" + IntegerToString(m_lastCandidateRejects.sweepNotConfirmed) +
          ",breakout=" + IntegerToString(m_lastCandidateRejects.breakoutNotConfirmed) +
          ",entry=" + IntegerToString(m_lastCandidateRejects.invalidEntry) +
          ",rr=" + IntegerToString(m_lastCandidateRejects.rrRejected) + ")");
  }

#endif // __QME_STRATEGY_SIGNALENGINE_MQH__
//+------------------------------------------------------------------+
