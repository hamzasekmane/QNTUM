//+------------------------------------------------------------------+
//|                                         Strategy/SetupEngine      |
//|  Decides whether a merged candidate is a tradable SETUP.             |
//|                                                                   |
//|  HARD RULES (each returns an explicit rejection reason):             |
//|   1. the candidate must be valid and its zone still active;           |
//|   2. HTF alignment is required when InpRequireHtfAlignment is set;    |
//|   3. at least two independent confirmations are required when the      |
//|      configuration asks for a minimum confluence;                     |
//|   4. a setup in the wrong premium/discount half is penalised, and      |
//|      rejected outright for demand bought in premium / supply sold in   |
//|      discount (the classic losing combination);                       |
//|   5. insufficient data quality rejects the setup.                     |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SETUPENGINE_MQH__
#define __QME_STRATEGY_SETUPENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Intelligence/MtfConfluenceEngine.mqh"
#include "MTF/CandidateClusterer.mqh"

struct SSetupVerdict
  {
   bool              ok;
   ENUM_QME_REJECT   reason;
   string            note;
   double            confluence;
   bool              htfAligned;
   int               confirmations;
   double            penalty;
  };

class CSetupEngine
  {
public:
   static SSetupVerdict Evaluate(const SMergedCandidate &mc, const SConfluenceResult &conf,
                                 const CConfig &cfg, const SDataQuality &dq);
   static int        CountConfirmations(const SMergedCandidate &mc);
  };

//------------------------------------------------------------------//
int CSetupEngine::CountConfirmations(const SMergedCandidate &mc)
  {
   int n = 0;
   if(mc.hasSweep) n++;
   if(mc.hasDisplacement) n++;
   if(mc.hasBos) n++;
   if(mc.hasMss) n++;
   if(mc.hasOb) n++;
   if(mc.hasFvg) n++;
   return(n);
  }

//------------------------------------------------------------------//
SSetupVerdict CSetupEngine::Evaluate(const SMergedCandidate &mc, const SConfluenceResult &conf,
                                     const CConfig &cfg, const SDataQuality &dq)
  {
   SSetupVerdict v;
   v.ok = false;
   v.reason = QME_REJ_NONE;
   v.note = "";
   v.confluence = conf.valid ? conf.score : 0.0;
   v.htfAligned = conf.valid ? conf.htfAligned : false;
   v.confirmations = CountConfirmations(mc);
   v.penalty = 0.0;

   if(!mc.valid)
     {
      v.reason = QME_REJ_INTERNAL;
      v.note = "candidate not marked valid";
      return(v);
     }

   //--- 5. data quality
   if(!dq.ok)
     {
      v.reason = dq.stale ? QME_REJ_STALE_DATA : QME_REJ_DATA_QUALITY;
      v.note = dq.note;
      return(v);
     }

   //--- 2. HTF alignment
   if(cfg.In.requireHtfAlignment && !v.htfAligned)
     {
      v.reason = QME_REJ_NO_CONFLUENCE;
      v.note = "higher timeframe does not agree with the candidate direction";
      return(v);
     }

   //--- 3. minimum confluence
   if(!conf.valid || conf.score < cfg.In.minConfluence)
     {
      v.reason = QME_REJ_NO_CONFLUENCE;
      v.note = "confluence " + QmeFmt(v.confluence, 2) + " < " + QmeFmt(cfg.In.minConfluence, 2);
      return(v);
     }
   if(v.confirmations < 2)
     {
      v.reason = QME_REJ_NO_CONFLUENCE;
      v.note = "only " + IntegerToString(v.confirmations) + " independent confirmations";
      return(v);
     }

   //--- 4. premium / discount sanity
   //--- buying demand high in the range (or selling supply low in the range)
   //--- is the worst location; reject it instead of hoping.
   if(mc.cand.side == QME_SIDE_BUY && mc.rangePosition > 0.80)
     {
      v.reason = QME_REJ_NO_STRUCTURE;
      v.note = "demand entry in deep premium (pos " + QmeFmt(mc.rangePosition, 2) + ")";
      return(v);
     }
   if(mc.cand.side == QME_SIDE_SELL && mc.rangePosition < 0.20)
     {
      v.reason = QME_REJ_NO_STRUCTURE;
      v.note = "supply entry in deep discount (pos " + QmeFmt(mc.rangePosition, 2) + ")";
      return(v);
     }

   //--- soft penalty for a mediocre location (not a rejection)
   if(mc.cand.side == QME_SIDE_BUY && mc.rangePosition > 0.65)  v.penalty += 6.0;
   if(mc.cand.side == QME_SIDE_SELL && mc.rangePosition < 0.35) v.penalty += 6.0;

   v.ok = true;
   return(v);
  }

#endif // __QME_STRATEGY_SETUPENGINE_MQH__
//+------------------------------------------------------------------+
