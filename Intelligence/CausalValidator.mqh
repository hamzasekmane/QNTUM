//+------------------------------------------------------------------+
//|                                  Intelligence/CausalValidator     |
//|  Defence against look-ahead bias at the decision boundary.           |
//|                                                                   |
//|  A decision taken at `decisionTime` may only use evidence whose       |
//|  timestamp is strictly in the past, and the entry-timeframe bar must  |
//|  already be CLOSED at decision time.                                |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_CAUSALVALIDATOR_MQH__
#define __QME_INTEL_CAUSALVALIDATOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/HistoryGuard.mqh"
#include "../Analysis/FactorCatalog.mqh"

class CCausalValidator
  {
public:
   //--- every timestamp referenced by the analysis must predate the decision
   static bool       EvidenceIsCausal(const SMarketAnalysis &a, const datetime decisionTime,
                                      const ENUM_TIMEFRAMES decisionTf, string &why);

   //--- a bar may only be consumed once closed
   static bool       BarIsUsable(const datetime barTime, const ENUM_TIMEFRAMES tf,
                                 const datetime decisionTime);

   //--- evidence from a lower timeframe may not be older than the higher
   //--- timeframe's own last closed bar (guards against stale mixed data)
   static bool       TimeframesAreCoherent(const SMarketAnalysis &fast,
                                           const SMarketAnalysis &slow, string &why);
  };

//------------------------------------------------------------------//
bool CCausalValidator::BarIsUsable(const datetime barTime, const ENUM_TIMEFRAMES tf,
                                   const datetime decisionTime)
  {
   if(barTime <= 0 || decisionTime <= 0) return(false);
   return(barTime + PeriodSeconds(tf) <= decisionTime);
  }

//------------------------------------------------------------------//
bool CCausalValidator::EvidenceIsCausal(const SMarketAnalysis &a, const datetime decisionTime,
                                        const ENUM_TIMEFRAMES decisionTf, string &why)
  {
   why = "";
   if(decisionTime <= 0) { why = "decision time unknown"; return(false); }
   if(a.barTime <= 0) { why = "analysis has no bar time"; return(false); }

   if(!BarIsUsable(a.barTime, a.tf, decisionTime))
     {
      why = "analysis bar " + QmeStamp(a.barTime) + " is not closed at decision time";
      return(false);
     }

   //--- structure evidence
   if(a.structure.valid)
     {
      if(a.structure.lastSwingHighTime > 0 && a.structure.lastSwingHighTime > decisionTime)
        { why = "swing high timestamp in the future"; return(false); }
      if(a.structure.lastSwingLowTime > 0 && a.structure.lastSwingLowTime > decisionTime)
        { why = "swing low timestamp in the future"; return(false); }
     }

   //--- liquidity evidence
   if(a.liquidity.valid)
     {
      for(int i = 0; i < a.liquidity.map.count; i++)
        {
         const datetime t = a.liquidity.map.levels[i].birthTime;
         if(t > 0 && t > decisionTime)
           { why = "liquidity level timestamp in the future"; return(false); }
        }
     }

   //--- structural events (MQL5 has no aggregate init for struct arrays)
   if(a.bos.valid && a.bos.time > decisionTime)
     { why = "structure event timestamp in the future"; return(false); }
   if(a.mss.valid && a.mss.time > decisionTime)
     { why = "structure event timestamp in the future"; return(false); }
   if(a.breakout.valid && a.breakout.time > decisionTime)
     { why = "structure event timestamp in the future"; return(false); }

   //--- price action evidence
   if(a.displacement.valid && a.displacement.time > decisionTime)
     { why = "displacement timestamp in the future"; return(false); }
   for(int i = 0; i < a.fvgCount; i++)
      if(a.fvgs[i].time > decisionTime)
        { why = "FVG timestamp in the future"; return(false); }
   for(int i = 0; i < a.obCount; i++)
      if(a.orderBlocks[i].time > decisionTime)
        { why = "order block timestamp in the future"; return(false); }

   //--- entry timeframe shorter than the analysed one is a configuration bug
   if(PeriodSeconds(decisionTf) > PeriodSeconds(a.tf))
     {
      why = "decision timeframe is slower than the analysis timeframe";
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CCausalValidator::TimeframesAreCoherent(const SMarketAnalysis &fast,
                                             const SMarketAnalysis &slow, string &why)
  {
   why = "";
   if(!fast.valid || !slow.valid) { why = "analysis invalid"; return(false); }
   if(PeriodSeconds(fast.tf) > PeriodSeconds(slow.tf))
     { why = "arguments reversed"; return(false); }
   if(!QmeCrossTimeframeConsistent(fast.barTime, fast.tf, slow.barTime, slow.tf))
     {
      why = QmeTimeframeName(fast.tf) + " data does not reach " +
            QmeTimeframeName(slow.tf) + " last bar";
      return(false);
     }
   return(true);
  }

#endif // __QME_INTEL_CAUSALVALIDATOR_MQH__
//+------------------------------------------------------------------+
