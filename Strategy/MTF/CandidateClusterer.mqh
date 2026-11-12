//+------------------------------------------------------------------+
//|                          Strategy/MTF/CandidateClusterer          |
//|  Merges per-timeframe hypotheses into ONE candidate per side.        |
//|                                                                   |
//|  RULES                                                             |
//|   * a candidate is identified by (symbol, side); two candidates of    |
//|     the same side would produce duplicate orders, so the clusterer    |
//|     keeps exactly one;                                              |
//|   * the PRIMARY timeframe is the highest timeframe that produced a     |
//|     hypothesis (structure is most reliable there);                    |
//|   * evidence is the MAXIMUM raw value observed across timeframes,      |
//|     i.e. a factor counts once no matter how many timeframes repeat it; |
//|   * the entry geometry always comes from the primary timeframe zone.   |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_CLUSTERER_MQH__
#define __QME_STRATEGY_CLUSTERER_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Core/Logger.mqh"
#include "../../Intelligence/ScoringEngine.mqh"
#include "CandidateCollector.mqh"

struct SMergedCandidate
  {
   STradeCandidate   cand;
   SScoreInput       score;
   SEntrySpec        entry;
   int               timeframes;
   double            bestStructureQuality;
   bool              hasSweep;
   bool              hasDisplacement;
   bool              hasBos;
   bool              hasMss;
   bool              hasOb;
   bool              hasFvg;
   double            rangePosition;
   bool              valid;
  };

class CCandidateClusterer
  {
public:
   static int        Merge(const SCandidateHypothesis &hyps[], const int count,
                           SMergedCandidate &out[], const int maxOut);
  };

//------------------------------------------------------------------//
int CCandidateClusterer::Merge(const SCandidateHypothesis &hyps[], const int count,
                               SMergedCandidate &out[], const int maxOut)
  {
   ArrayResize(out, 0);
   if(count <= 0 || maxOut <= 0) return(0);

   const ENUM_QME_SIDE sides[2] = {QME_SIDE_BUY, QME_SIDE_SELL};
   for(int s = 0; s < 2 && ArraySize(out) < maxOut; s++)
     {
      const ENUM_QME_SIDE side = sides[s];

      //--- pick the primary hypothesis: highest timeframe, then best structure
      int primary = -1;
      int primaryMinutes = -1;
      for(int i = 0; i < count; i++)
        {
         if(!hyps[i].valid || hyps[i].side != side) continue;
         const int m = QmeTimeframeMinutes(hyps[i].tf);
         if(primary < 0 || m > primaryMinutes ||
            (m == primaryMinutes && hyps[i].structureQuality > hyps[primary].structureQuality))
           {
            primary = i;
            primaryMinutes = m;
           }
        }
      if(primary < 0) continue;

      SMergedCandidate mc;
      QmeCandidateClear(mc.cand);
      QmeScoreInputClear(mc.score);
      mc.entry = hyps[primary].entry;
      mc.timeframes = 0;
      mc.bestStructureQuality = 0.0;
      mc.hasSweep = false;
      mc.hasDisplacement = false;
      mc.hasBos = false;
      mc.hasMss = false;
      mc.hasOb = false;
      mc.hasFvg = false;
      mc.rangePosition = hyps[primary].rangePosition;
      mc.valid = false;

      //--- merge evidence across all hypotheses of this side
      for(int i = 0; i < count; i++)
        {
         if(!hyps[i].valid || hyps[i].side != side) continue;
         mc.timeframes++;

         for(int f = 0; f < (int)QME_F_COUNT; f++)
           {
            if(!hyps[i].score.available[f]) continue;
            if(!mc.score.available[f])
              {
               mc.score.available[f] = true;
               mc.score.raw[f] = hyps[i].score.raw[f];
              }
            else if(hyps[i].score.raw[f] > mc.score.raw[f])
               mc.score.raw[f] = hyps[i].score.raw[f];
           }
         mc.hasSweep        = mc.hasSweep || hyps[i].hasSweep;
         mc.hasDisplacement = mc.hasDisplacement || hyps[i].hasDisplacement;
         mc.hasBos          = mc.hasBos || hyps[i].hasBos;
         mc.hasMss          = mc.hasMss || hyps[i].hasMss;
         mc.hasOb           = mc.hasOb || hyps[i].hasOb;
         mc.hasFvg          = mc.hasFvg || hyps[i].hasFvg;
         if(hyps[i].structureQuality > mc.bestStructureQuality)
            mc.bestStructureQuality = hyps[i].structureQuality;
        }

      //--- penalties: a setup that relies only on structure without any
      //--- trigger is suspicious; the scoring engine would over-rate it.
      int triggers = 0;
      if(mc.hasSweep) triggers++;
      if(mc.hasDisplacement) triggers++;
      if(mc.hasBos) triggers++;
      if(mc.hasMss) triggers++;
      if(mc.hasOb) triggers++;
      if(mc.hasFvg) triggers++;
      if(triggers == 0)
         QmeScoreInputPenalty(mc.score, 12.0);
      else if(triggers == 1)
         QmeScoreInputPenalty(mc.score, 4.0);

      //--- fill the transport candidate
      mc.cand.symbol = hyps[primary].symbol;
      mc.cand.side = side;
      mc.cand.tf = hyps[primary].tf;
      mc.cand.zoneId = hyps[primary].zone.id;
      mc.cand.source = hyps[primary].zone.source;
      mc.cand.zoneUpper = MathMax(hyps[primary].zone.upper, hyps[primary].zone.lower);
      mc.cand.zoneLower = MathMin(hyps[primary].zone.upper, hyps[primary].zone.lower);
      mc.cand.entry = mc.entry.entry;
      mc.cand.stopLoss = mc.entry.stop;
      mc.cand.takeProfit = mc.entry.target1;
      mc.cand.rr = mc.entry.rr;
      mc.cand.created = hyps[primary].created;
      // The setup gate consumes SMergedCandidate.valid (not cand.valid).
      // Derive both flags from the producer contract instead of marking the
      // transport record valid unconditionally.
      mc.cand.valid = (hyps[primary].valid && hyps[primary].entry.valid &&
                       mc.entry.valid && mc.cand.entry > 0.0 &&
                       mc.cand.stopLoss > 0.0 && mc.cand.takeProfit > 0.0);
      mc.valid = mc.cand.valid;
      if(!mc.valid)
        {
         QmeLogMsg(QME_LOG_WARN,"CandidateMerge","discard invalid merged candidate side="+
                   QmeSideName(side)+" hypValid="+QmeBoolStr(hyps[primary].valid)+
                   " entryValid="+QmeBoolStr(mc.entry.valid));
         continue;
        }

      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = mc;
      static datetime lastMergeTrace=0;
      const datetime traceNow=TimeCurrent();
      if(traceNow-lastMergeTrace>=30)
        {
         lastMergeTrace=traceNow;
         int availableFactors=0;
         for(int fi=0;fi<(int)QME_F_COUNT;fi++) if(mc.score.available[fi]) availableFactors++;
         QmeLogMsg(QME_LOG_INFO,"CandidateMerge",mc.cand.symbol+" "+QmeSideName(side)+
                   " hypotheses="+IntegerToString(mc.timeframes)+
                   " candidateValid="+QmeBoolStr(mc.cand.valid)+
                   " mergedValid="+QmeBoolStr(mc.valid)+
                   " evidenceFactors="+IntegerToString(availableFactors));
        }
     }
   return(ArraySize(out));
  }

#endif // __QME_STRATEGY_CLUSTERER_MQH__
//+------------------------------------------------------------------+
