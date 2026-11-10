//+------------------------------------------------------------------+
//|                                     Strategy/MTF/EntryEngine      |
//|  Entry confirmation on the fastest timeframe.                        |
//|                                                                   |
//|  A setup is NOT an entry. The entry engine requires at least one      |
//|  of these on the entry timeframe, using closed bars only:            |
//|   * a candle pattern whose bias matches the trade direction;          |
//|   * a momentum reading aligned with the direction;                    |
//|   * a reaction at the entry zone.                                    |
//|  The result feeds the ENTRY_CONFIRM scoring factor.                   |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_ENTRYENGINE_MQH__
#define __QME_STRATEGY_ENTRYENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Analysis/FactorCatalog.mqh"
#include "EntryTypes.mqh"

struct SEntryConfirmation
  {
   bool              confirmed;
   double            evidence;     // 0..1 for QME_F_ENTRY_CONFIRM
   ENUM_QME_REJECT   reason;
   string            note;
  };

class CEntryEngine
  {
public:
   static SEntryConfirmation Confirm(const SMarketAnalysis &entryTf,
                                     const SEntrySpec &entry,
                                     const ENUM_QME_SIDE side,
                                     const double minEvidence = 0.35);
  };

//------------------------------------------------------------------//
SEntryConfirmation CEntryEngine::Confirm(const SMarketAnalysis &entryTf,
                                         const SEntrySpec &entry,
                                         const ENUM_QME_SIDE side,
                                         const double minEvidence)
  {
   SEntryConfirmation r;
   r.confirmed = false;
   r.evidence = 0.0;
   r.reason = QME_REJ_NONE;
   r.note = "";

   if(!entry.valid)
     {
      r.reason = QME_REJ_INTERNAL;
      r.note = "entry specification invalid";
      return(r);
     }
   if(!entryTf.valid)
     {
      r.reason = QME_REJ_NO_DATA;
      r.note = "entry timeframe analysis unavailable";
      return(r);
     }

   double evidence = 0.0;
   string reasons = "";

   //--- 1. candle pattern in the trade direction
   if(entryTf.pattern.valid && entryTf.pattern.bias == side)
     {
      const double e = 0.45 + 0.40 * QmeClamp(entryTf.pattern.quality, 0.0, 1.0);
      if(e > evidence) evidence = e;
      reasons += "pattern(" + IntegerToString((int)entryTf.pattern.pattern) + ") ";
     }

   //--- 2. momentum alignment
   if(entryTf.momentum.valid)
     {
      const double m = (side == QME_SIDE_BUY) ? entryTf.momentum.value : -entryTf.momentum.value;
      if(m > 0.15)
        {
         const double e = 0.35 + 0.45 * QmeClamp(m, 0.0, 1.0);
         if(e > evidence) evidence = e;
         reasons += "momentum ";
        }
     }

   //--- 3. reaction at the entry zone edge
   if(entryTf.reaction.valid && entryTf.reaction.side == side)
     {
      const double e = 0.50 + 0.40 * QmeClamp(entryTf.reaction.strength, 0.0, 1.0);
      if(e > evidence) evidence = e;
      reasons += "reaction ";
     }

   //--- 4. displacement in the trade direction supports the entry
   if(entryTf.displacement.valid && entryTf.displacement.found &&
      entryTf.displacement.side == side)
     {
      const double e = 0.40 + 0.40 * QmeClamp(entryTf.displacement.score, 0.0, 1.0);
      if(e > evidence) evidence = e;
      reasons += "displacement ";
     }

   r.evidence = QmeClamp(evidence, 0.0, 1.0);

   //--- a market entry that is already far from the zone is stale
   if(entry.type == QME_ENTRY_MARKET && entryTf.price > 0.0 && entryTf.atr > 0.0)
     {
      const double drift = MathAbs(entryTf.price - entry.entry) / entryTf.atr;
      if(drift > 0.75)
        {
         r.reason = QME_REJ_EXPIRED;
         r.note = "price drifted " + QmeFmt(drift, 2) + " ATR from the entry";
         return(r);
        }
     }

   if(r.evidence < minEvidence)
     {
      r.reason = QME_REJ_LOW_SCORE;
      r.note = "entry confirmation " + QmeFmt(r.evidence, 2) + " < " + QmeFmt(minEvidence, 2);
      return(r);
     }

   r.confirmed = true;
   r.note = reasons;
   return(r);
  }

#endif // __QME_STRATEGY_ENTRYENGINE_MQH__
//+------------------------------------------------------------------+
