//+------------------------------------------------------------------+
//|                                          Analysis/FactorCatalog   |
//|  Single registry of scoring factors: id, family, default weight.     |
//|                                                                   |
//|  WHY: ScoringEngine and AdaptiveWeights must never hard-code a        |
//|  factor list; otherwise adding/removing a factor silently desyncs     |
//|  the scoring, the breakdown display and the calibration.              |
//|                                                                   |
//|  Families exist so correlated evidence is not double-counted:          |
//|  e.g. BOS and MSS both belong to QME_FAM_STRUCTURE, so at most one    |
//|  of them contributes its full weight to a single candidate.           |
//|                                                                   |
//|  This file also defines SMarketAnalysis, the canonical per-symbol      |
//|  analysis aggregate produced by the Scanner and consumed by           |
//|  Zones / Intelligence / Strategy.                                    |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_FACTORCATALOG_MQH__
#define __QME_ANALYSIS_FACTORCATALOG_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "Market/RegimeEngine.mqh"
#include "Market/BiasEngine.mqh"
#include "Market/TrendEngine.mqh"
#include "Market/MomentumEngine.mqh"
#include "Market/VolatilityEngine.mqh"
#include "Market/SessionEngine.mqh"
#include "Structure/StructureEngine.mqh"
#include "Structure/BosEngine.mqh"
#include "Structure/MssEngine.mqh"
#include "Structure/BreakoutEngine.mqh"
#include "Liquidity/LiquidityEngine.mqh"
#include "Liquidity/LiquiditySweep.mqh"
#include "Liquidity/VolumeProfile.mqh"
#include "PriceAction/CandleEngine.mqh"
#include "PriceAction/CandlePatternEngine.mqh"
#include "PriceAction/DisplacementEngine.mqh"
#include "PriceAction/FvgEngine.mqh"
#include "PriceAction/OrderBlockEngine.mqh"
#include "PriceAction/PremiumDiscountEngine.mqh"
#include "PriceAction/ReactionEngine.mqh"
#include "PriceAction/LocationEngine.mqh"

#define QME_MAX_FVGS   8
#define QME_MAX_OBS    8

struct SFactorMeta
  {
   ENUM_QME_FACTOR       factor;
   ENUM_QME_FACTOR_FAMILY family;
   double                defaultWeight;
  };

class CFactorCatalog
  {
public:
   static int        Count(void) { return((int)QME_F_COUNT); }
   static void       Get(const ENUM_QME_FACTOR f, SFactorMeta &out);
   static double     DefaultWeight(const ENUM_QME_FACTOR f);
   static ENUM_QME_FACTOR_FAMILY Family(const ENUM_QME_FACTOR f);
   //--- bit used in zone.factorMask / signal.factorMask (max 14 factors -> uint)
   static uint       Bit(const ENUM_QME_FACTOR f);
   static double     TotalDefaultWeight(void);
  };

//------------------------------------------------------------------//
void CFactorCatalog::Get(const ENUM_QME_FACTOR f, SFactorMeta &out)
  {
   out.factor = f;
   out.family = QME_FAM_CONTEXT;
   out.defaultWeight = 1.0;

   switch(f)
     {
      case QME_F_HTF_BIAS:
         out.family = QME_FAM_DIRECTION;  out.defaultWeight = 2.0; break;
      case QME_F_STRUCTURE:
         out.family = QME_FAM_STRUCTURE;  out.defaultWeight = 1.6; break;
      case QME_F_LIQUIDITY:
         out.family = QME_FAM_LIQUIDITY;  out.defaultWeight = 1.2; break;
      case QME_F_SWEEP:
         out.family = QME_FAM_LIQUIDITY;  out.defaultWeight = 1.5; break;
      case QME_F_DISPLACEMENT:
         out.family = QME_FAM_IMBALANCE;  out.defaultWeight = 1.3; break;
      case QME_F_BOS:
         out.family = QME_FAM_STRUCTURE;  out.defaultWeight = 1.2; break;
      case QME_F_MSS:
         out.family = QME_FAM_STRUCTURE;  out.defaultWeight = 1.2; break;
      case QME_F_ORDER_BLOCK:
         out.family = QME_FAM_IMBALANCE;  out.defaultWeight = 1.4; break;
      case QME_F_FVG:
         out.family = QME_FAM_IMBALANCE;  out.defaultWeight = 1.0; break;
      case QME_F_PREMIUM_DISCOUNT:
         out.family = QME_FAM_CONTEXT;    out.defaultWeight = 0.9; break;
      case QME_F_MOMENTUM:
         out.family = QME_FAM_MOMENTUM;   out.defaultWeight = 1.0; break;
      case QME_F_VOLATILITY:
         out.family = QME_FAM_CONTEXT;    out.defaultWeight = 0.7; break;
      case QME_F_SESSION:
         out.family = QME_FAM_CONTEXT;    out.defaultWeight = 0.5; break;
      case QME_F_ENTRY_CONFIRM:
         out.family = QME_FAM_MOMENTUM;   out.defaultWeight = 1.4; break;
     }
  }

double CFactorCatalog::DefaultWeight(const ENUM_QME_FACTOR f)
  {
   SFactorMeta m;
   Get(f, m);
   return(m.defaultWeight);
  }

ENUM_QME_FACTOR_FAMILY CFactorCatalog::Family(const ENUM_QME_FACTOR f)
  {
   SFactorMeta m;
   Get(f, m);
   return(m.family);
  }

uint CFactorCatalog::Bit(const ENUM_QME_FACTOR f)
  {
   const int i = (int)f;
   if(i < 0 || i >= 32) return(0);
   return((uint)1 << i);
  }

double CFactorCatalog::TotalDefaultWeight(void)
  {
   double s = 0.0;
   for(int i = 0; i < (int)QME_F_COUNT; i++)
      s += DefaultWeight((ENUM_QME_FACTOR)i);
   return(s);
  }

//+------------------------------------------------------------------+
//| SMarketAnalysis — canonical analysis output for ONE symbol and      |
//| ONE timeframe. Produced by CScanner, consumed by Zones,             |
//| Intelligence and Strategy. No pointers, no ownership.               |
//+------------------------------------------------------------------+
struct SMarketAnalysis
  {
   //--- identity
   string               symbol;
   ENUM_TIMEFRAMES      tf;
   datetime             barTime;
   double               price;         // newest closed close
   double               atr;
   double               avgBody;
   double               avgRange;
   double               spreadPoints;

   //--- market context
   SRegimeResult        regime;
   STrendResult         trend;
   SMomentumResult      momentum;
   SVolatilityResult    volatility;
   SBiasResult          bias;
   SSessionResult       session;

   //--- structure
   SStructureState      structure;
   SStructureEvent      bos;
   SStructureEvent      mss;
   SStructureEvent      breakout;

   //--- liquidity
   SLiquidityAnalysis   liquidity;
   SSweepResult         sweep;
   SVolumeProfile       volumeProfile;
   SLocationResult      location;

   //--- price action
   SCandleFacts         candle;
   SPatternResult       pattern;
   SDisplacementResult  displacement;
   SFvgRecord           fvgs[QME_MAX_FVGS];
   int                  fvgCount;
   SOrderBlockRecord    orderBlocks[QME_MAX_OBS];
   int                  obCount;
   SRangeContext        range;
   SReactionResult      reaction;

   //--- validity
   bool                 structureValid;
   bool                 liquidityValid;
   bool                 valid;
  };

void QmeAnalysisClear(SMarketAnalysis &a)
  {
   a.symbol = "";
   a.tf = PERIOD_CURRENT;
   a.barTime = 0;
   a.price = 0.0;
   a.atr = 0.0;
   a.avgBody = 0.0;
   a.avgRange = 0.0;
   a.spreadPoints = 0.0;

   a.regime.valid = false;
   a.trend.valid = false;
   a.momentum.valid = false;
   a.volatility.valid = false;
   a.bias.valid = false;
   a.session.valid = false;

   QmeStructureReset(a.structure);
   QmeStructureEventClear(a.bos);
   QmeStructureEventClear(a.mss);
   QmeStructureEventClear(a.breakout);

   QmeLiquidityReset(a.liquidity.map);
   a.liquidity.valid = false;
   a.liquidity.sessionTag = QME_SESSION_UNKNOWN;
   a.liquidity.dayWeek.pdh = 0.0; a.liquidity.dayWeek.pdl = 0.0;
   a.liquidity.dayWeek.pwh = 0.0; a.liquidity.dayWeek.pwl = 0.0;
   a.liquidity.dayWeek.dayValid = false;
   a.liquidity.dayWeek.weekValid = false;
   a.liquidity.dayWeek.valid = false;
   a.liquidity.dayWeek.dayBarTime = 0;
   a.liquidity.dayWeek.weekBarTime = 0;
   a.liquidity.session.high = 0.0;
   a.liquidity.session.low = 0.0;
   a.liquidity.session.sessionStart = 0;
   a.liquidity.session.session = QME_SESSION_UNKNOWN;
   a.liquidity.session.barsUsed = 0;
   a.liquidity.session.valid = false;

   QmeSweepClear(a.sweep);
   a.volumeProfile.valid = false;
   a.volumeProfile.nodeCount = 0;
   a.volumeProfile.poc = 0.0;
   a.volumeProfile.valueAreaHigh = 0.0;
   a.volumeProfile.valueAreaLow = 0.0;
   a.volumeProfile.totalVolume = 0.0;

   a.location.valid = false;

   QmeCandleFactsClear(a.candle);
   a.pattern.valid = false;
   a.pattern.pattern = QME_CANDLE_NONE;
   a.pattern.bias = QME_SIDE_NONE;
   a.pattern.quality = 0.0;
   QmeDisplacementClear(a.displacement);

   a.fvgCount = 0;
   a.obCount = 0;

   a.range.valid = false;
   a.reaction.valid = false;

   a.structureValid = false;
   a.liquidityValid = false;
   a.valid = false;
  }

#endif // __QME_ANALYSIS_FACTORCATALOG_MQH__
//+------------------------------------------------------------------+
