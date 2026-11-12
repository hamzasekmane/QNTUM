//+------------------------------------------------------------------+
//|                          Strategy/MTF/CandidateCollector          |
//|  Turns analysis + zones into candidate hypotheses.                  |
//|                                                                   |
//|  For each side it looks for an ACTIVE zone of that side within       |
//|  `maxZoneDistAtr`, derives entry/stop/target from it, and records     |
//|  the evidence for every scoring factor.                             |
//|                                                                   |
//|  FACTOR MAPPING (the only place these mappings exist):              |
//|   HTF_BIAS          : HTF bias side matches and its score           |
//|   STRUCTURE         : structure trend matches, scaled by strength    |
//|   LIQUIDITY         : a pool on the correct side within 1.5 ATR      |
//|   SWEEP             : a sweep whose implied direction matches        |
//|   DISPLACEMENT      : displacement in the candidate direction        |
//|   BOS / MSS         : confirmed event in the candidate direction     |
//|   ORDER_BLOCK / FVG : zone originates from that imbalance            |
//|   PREMIUM_DISCOUNT  : buying in discount / selling in premium        |
//|   MOMENTUM          : momentum aligned with the candidate            |
//|   VOLATILITY        : preference for normal volatility               |
//|   SESSION           : configured session permission, scaled          |
//|   ENTRY_CONFIRM     : filled later by the EntryEngine                |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_CANDIDATECOLLECTOR_MQH__
#define __QME_STRATEGY_CANDIDATECOLLECTOR_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Config.mqh"
#include "../../Core/Utils.mqh"
#include "../../Account/SymbolSpecifications.mqh"
#include "../../Analysis/FactorCatalog.mqh"
#include "../../Zones/ZoneEngine.mqh"
#include "../../Intelligence/ScoringEngine.mqh"
#include "EntryRig.mqh"

struct SCandidateHypothesis
  {
   string            symbol;
   ENUM_TIMEFRAMES   tf;
   ENUM_QME_SIDE     side;
   STradingZone      zone;
   SEntrySpec        entry;
   SScoreInput       score;
   bool              hasSweep;
   bool              hasDisplacement;
   bool              hasBos;
   bool              hasMss;
   bool              hasOb;
   bool              hasFvg;
   bool              hasLiquidity;
   double            structureQuality;
   double            rangePosition;
   datetime          created;
   bool              valid;
   ENUM_QME_REJECT   reason;
   string            note;
  };

class CCandidateCollector
  {
public:
   static void       FillEvidence(const SMarketAnalysis &bias,
                                  const SMarketAnalysis &structure,
                                  const SMarketAnalysis &setup,
                                  const STradingZone &zone,
                                  const ENUM_QME_SIDE side,
                                  SCandidateHypothesis &h);

   static int        Collect(const SMarketAnalysis &bias, const SMarketAnalysis &structure,
                             const SMarketAnalysis &setup, CZoneEngine &zones,
                             const SSymbolSpec &spec, const CConfig &cfg,
                             const double price, const double atr, const double point,
                             const double rrTarget, const double maxStopAtr,
                             SCandidateHypothesis &out[], const int maxOut);
  };

//------------------------------------------------------------------//
void CCandidateCollector::FillEvidence(const SMarketAnalysis &bias,
                                       const SMarketAnalysis &structure,
                                       const SMarketAnalysis &setup,
                                       const STradingZone &zone,
                                       const ENUM_QME_SIDE side,
                                       SCandidateHypothesis &h)
  {
   QmeScoreInputClear(h.score);

   //--- HTF bias
   if(bias.bias.valid && bias.bias.side == side)
      QmeScoreInputSet(h.score, QME_F_HTF_BIAS, bias.bias.score);
   else if(bias.bias.valid)
      QmeScoreInputSet(h.score, QME_F_HTF_BIAS, 0.0);

   //--- structure (from the structure timeframe)
   if(structure.structure.valid)
     {
      const bool aligned = (side == QME_SIDE_BUY && structure.structure.trend == QME_TREND_UP) ||
                           (side == QME_SIDE_SELL && structure.structure.trend == QME_TREND_DOWN);
      double q = 0.0;
      if(aligned)
        {
         q = 0.5;
         if(structure.structure.higherHigh && structure.structure.higherLow) q += 0.25;
         if(structure.structure.lowerLow && structure.structure.lowerHigh)  q += 0.25;
         if(side == QME_SIDE_SELL && structure.structure.lowerLow) q += 0.0;
        }
      h.structureQuality = QmeClamp(q, 0.0, 1.0);
      QmeScoreInputSet(h.score, QME_F_STRUCTURE, h.structureQuality);
     }

   //--- liquidity on the correct side of the price
   if(structure.liquidity.valid)
     {
      const double dist = (side == QME_SIDE_BUY) ?
                          setup.location.distToSellSideAtr : setup.location.distToBuySideAtr;
      const bool has = (side == QME_SIDE_BUY) ? setup.location.hasSellSide : setup.location.hasBuySide;
      if(has && dist <= 1.5)
        {
         h.hasLiquidity = true;
         QmeScoreInputSet(h.score, QME_F_LIQUIDITY, QmeClamp(1.0 - dist / 1.5, 0.2, 1.0));
        }
      else
         QmeScoreInputSet(h.score, QME_F_LIQUIDITY, 0.0);
     }

   //--- sweep
   if(setup.sweep.valid && setup.sweep.tradeSide == side)
     {
      h.hasSweep = true;
      QmeScoreInputSet(h.score, QME_F_SWEEP,
                       QmeClamp(0.55 + 0.15 * setup.sweep.penetration, 0.0, 1.0));
     }

   //--- displacement
   if(setup.displacement.valid && setup.displacement.found && setup.displacement.side == side)
     {
      h.hasDisplacement = true;
      QmeScoreInputSet(h.score, QME_F_DISPLACEMENT, setup.displacement.score);
     }

   //--- BOS / MSS
   if(setup.bos.valid)
     {
      const bool up = (setup.bos.event == QME_STRUCT_BOS_UP);
      if((side == QME_SIDE_BUY && up) || (side == QME_SIDE_SELL && !up))
        {
         h.hasBos = true;
         QmeScoreInputSet(h.score, QME_F_BOS, QmeClamp(0.5 + 0.5 * setup.bos.strength, 0.0, 1.0));
        }
     }
   if(setup.mss.valid)
     {
      const bool up = (setup.mss.event == QME_STRUCT_MSS_UP);
      if((side == QME_SIDE_BUY && up) || (side == QME_SIDE_SELL && !up))
        {
         h.hasMss = true;
         QmeScoreInputSet(h.score, QME_F_MSS, QmeClamp(0.5 + 0.5 * setup.mss.strength, 0.0, 1.0));
        }
     }

   //--- imbalance provenance of the zone
   if(zone.source == QME_ZONE_SRC_ORDER_BLOCK)
     {
      h.hasOb = true;
      QmeScoreInputSet(h.score, QME_F_ORDER_BLOCK, zone.strength);
     }
   if(zone.source == QME_ZONE_SRC_FVG)
     {
      h.hasFvg = true;
      QmeScoreInputSet(h.score, QME_F_FVG, zone.strength);
     }
   //--- a zone that carries several sources is stronger on all of them
   const uint mask = zone.factorMask;
   if((mask & CFactorCatalog::Bit(QME_F_ORDER_BLOCK)) != 0 && !h.hasOb)
     {
      h.hasOb = true;
      QmeScoreInputSet(h.score, QME_F_ORDER_BLOCK, zone.strength * 0.8);
     }
   if((mask & CFactorCatalog::Bit(QME_F_FVG)) != 0 && !h.hasFvg)
     {
      h.hasFvg = true;
      QmeScoreInputSet(h.score, QME_F_FVG, zone.strength * 0.8);
     }

   //--- premium / discount
   if(setup.range.valid)
     {
      h.rangePosition = setup.range.position;
      double pd = 0.0;
      if(side == QME_SIDE_BUY)  pd = QmeClamp(1.0 - setup.range.position, 0.0, 1.0);
      if(side == QME_SIDE_SELL) pd = QmeClamp(setup.range.position, 0.0, 1.0);
      QmeScoreInputSet(h.score, QME_F_PREMIUM_DISCOUNT, pd);
     }

   //--- momentum
   if(setup.momentum.valid)
     {
      const double m = (side == QME_SIDE_BUY) ? setup.momentum.value : -setup.momentum.value;
      QmeScoreInputSet(h.score, QME_F_MOMENTUM, QmeClamp(m, 0.0, 1.0));
     }

   //--- volatility preference (normal is best; extreme is penalised)
   if(setup.volatility.valid)
     {
      double v = 1.0 - QmeClamp(MathAbs(setup.volatility.atrRatio - 1.0), 0.0, 1.0);
      if(setup.volatility.state == QME_VOL_EXTREME) v *= 0.3;
      if(setup.volatility.state == QME_VOL_LOW)     v *= 0.7;
      QmeScoreInputSet(h.score, QME_F_VOLATILITY, v);
     }

   //--- session
   if(setup.session.valid)
     {
      double s = 0.0;
      if(setup.session.tradingAllowed)
        {
         switch(setup.session.session)
           {
            case QME_SESSION_OVERLAP: s = 1.0; break;
            case QME_SESSION_LONDON:  s = 0.9; break;
            case QME_SESSION_NEWYORK: s = 0.85; break;
            case QME_SESSION_ASIA:    s = 0.55; break;
            default:                  s = 0.2; break;
           }
        }
      QmeScoreInputSet(h.score, QME_F_SESSION, s);
     }
  }

//------------------------------------------------------------------//
int CCandidateCollector::Collect(const SMarketAnalysis &bias, const SMarketAnalysis &structure,
                                 const SMarketAnalysis &setup, CZoneEngine &zones,
                                 const SSymbolSpec &spec, const CConfig &cfg,
                                 const double price, const double atr, const double point,
                                 const double rrTarget, const double maxStopAtr,
                                 SCandidateHypothesis &out[], const int maxOut)
  {
   ArrayResize(out, 0);
   if(price <= 0.0 || atr <= 0.0 || !setup.structureValid) return(0);

   const ENUM_QME_SIDE sides[2] = {QME_SIDE_BUY, QME_SIDE_SELL};
   for(int s = 0; s < 2 && ArraySize(out) < maxOut; s++)
     {
      const ENUM_QME_SIDE side = sides[s];
      if(side == QME_SIDE_BUY && !cfg.In.allowBuy)  continue;
      if(side == QME_SIDE_SELL && !cfg.In.allowSell) continue;

      // Do not trade a liquidity raid merely because its wick closed back
      // inside the pool. Require a later closed-bar MSS/CHoCH in the reversal
      // direction. Series index 0 is newest, so a smaller index is later.
      if(setup.liquidityOutcome.classification == QME_LIQUIDITY_BREAKOUT)
        {
         const bool bosAligned = setup.bos.valid &&
            ((side == QME_SIDE_BUY && setup.bos.event == QME_STRUCT_BOS_UP) ||
             (side == QME_SIDE_SELL && setup.bos.event == QME_STRUCT_BOS_DOWN));
         if(side != setup.liquidityEventSide || !bosAligned) continue;
        }
      if(setup.sweep.valid && setup.sweep.tradeSide == side)
        {
         const bool mssAligned = setup.mss.valid &&
            ((side == QME_SIDE_BUY && setup.mss.event == QME_STRUCT_MSS_UP) ||
             (side == QME_SIDE_SELL && setup.mss.event == QME_STRUCT_MSS_DOWN));
         if(!mssAligned || setup.mss.barIndex < 0 ||
            setup.sweep.barIndex < 0 || setup.mss.barIndex >= setup.sweep.barIndex)
            continue;
        }

      STradingZone zone;
      if(!zones.BestZone(side, price, atr, setup.barTime, 2.0, zone))
         continue;

      SEntrySpec entry = CEntryRig::FromZone(zone, side, price, atr, point, spec,
                                             MathMax(rrTarget, 2.0), maxStopAtr);
      if(!entry.valid)
         continue;

      // Reversal geometry is anchored to the confirmed raid wick. The first
      // opposite-side liquidity pool is the target; if it cannot pay 2R,
      // reject instead of silently targeting an arbitrary RR multiple.
      if(setup.sweep.valid && setup.sweep.tradeSide == side)
        {
         const double buffer = MathMax(0.10 * atr, 2.0 * point);
         entry.stop = (side == QME_SIDE_SELL) ? setup.sweep.extreme + buffer :
                                                setup.sweep.extreme - buffer;
         entry.stop = CSymbolSpecifications::NormalizePrice(spec, entry.stop);
         entry.stopDistance = MathAbs(entry.entry - entry.stop);
         if(entry.stopDistance <= 0.0 ||
            (maxStopAtr > 0.0 && entry.stopDistance > maxStopAtr * atr)) continue;
         double nearest = 0.0;
         double nearestDistance = DBL_MAX;
         for(int li=0; li<setup.liquidity.map.count; li++)
           {
            const SLiquidityLevel level = setup.liquidity.map.levels[li];
            const bool targetSide = (side == QME_SIDE_BUY) ? level.side == QME_SIDE_BUY :
                                                              level.side == QME_SIDE_SELL;
            const bool ahead = (side == QME_SIDE_BUY) ? level.price > entry.entry :
                                                        level.price < entry.entry;
            if(!targetSide || !ahead) continue;
            const double d=MathAbs(level.price-entry.entry);
            if(d < nearestDistance) { nearestDistance=d; nearest=level.price; }
           }
         if(nearest <= 0.0) continue;
         entry.target1 = CSymbolSpecifications::NormalizePrice(spec, nearest);
         entry.target2 = entry.target1;
         entry.rr = MathAbs(entry.target1-entry.entry)/entry.stopDistance;
         if(entry.rr + QME_EPSILON < 2.0) continue;
        }
      if(entry.rr + QME_EPSILON < 2.0) continue;
      string why = "";
      if(!CEntryTypes::Validate(entry, spec,
                                CSymbolSpecifications::MinStopDistance(spec), why))
         continue;

      SCandidateHypothesis h;
      h.symbol = setup.symbol;
      h.tf = setup.tf;
      h.side = side;
      h.zone = zone;
      h.entry = entry;
      h.hasSweep = false;
      h.hasDisplacement = false;
      h.hasBos = false;
      h.hasMss = false;
      h.hasOb = false;
      h.hasFvg = false;
      h.hasLiquidity = false;
      h.structureQuality = 0.0;
      h.rangePosition = setup.range.valid ? setup.range.position : 0.5;
      h.created = setup.barTime;
      h.valid = true;
      h.reason = QME_REJ_NONE;
      h.note = "";

      FillEvidence(bias, structure, setup, zone, side, h);

      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = h;
     }
   return(ArraySize(out));
  }

#endif // __QME_STRATEGY_CANDIDATECOLLECTOR_MQH__
//+------------------------------------------------------------------+
