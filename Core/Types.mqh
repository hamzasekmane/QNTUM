//+------------------------------------------------------------------+
//|                                                      Types.mqh   |
//|  QuantumMarketEngine — canonical data contract.                   |
//|                                                                   |
//|  RULES enforced by this file:                                     |
//|   * fixed-capacity structs only (no dynamic arrays inside a        |
//|     record, so records can be copied and stored safely);           |
//|   * no `string` inside any struct used in a FIXED array (MQL5      |
//|     cannot manage such arrays reliably);                          |
//|   * every "record" has a Reset() equivalent free function so no    |
//|     uninitialised field can reach a decision.                      |
//|  OWNERSHIP: passive value types. No struct owns resources.         |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_TYPES_MQH__
#define __QME_CORE_TYPES_MQH__

#include "Constants.mqh"
#include "Enums.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Candle                                                           |
//+------------------------------------------------------------------+
struct SCandle
  {
   datetime          time;
   double            open;
   double            high;
   double            low;
   double            close;
   long              tickVolume;
   long              realVolume;
   int               spread;      // points, as reported by the server
   bool              valid;
  };

void QmeCandleClear(SCandle &c)
  {
   c.time = 0; c.open = 0; c.high = 0; c.low = 0; c.close = 0;
   c.tickVolume = 0; c.realVolume = 0; c.spread = 0; c.valid = false;
  }

double QmeCandleRange(const SCandle &c)      { return(MathMax(0.0, c.high - c.low)); }
double QmeCandleBody(const SCandle &c)       { return(MathAbs(c.close - c.open)); }
double QmeCandleUpperWick(const SCandle &c)  { return(MathMax(0.0, c.high - MathMax(c.open, c.close))); }
double QmeCandleLowerWick(const SCandle &c)  { return(MathMax(0.0, MathMin(c.open, c.close) - c.low)); }
bool   QmeCandleIsBull(const SCandle &c)      { return(c.close > c.open); }
bool   QmeCandleIsBear(const SCandle &c)      { return(c.close < c.open); }

//--- body as a fraction of total range (0..1)
double QmeCandleBodyRatio(const SCandle &c)
  {
   const double r = QmeCandleRange(c);
   if(r < QME_EPSILON) return(0.0);
   return(QmeCandleBody(c) / r);
  }

//--- close position inside the bar range: 0 = at low, 1 = at high
double QmeCandleClosePos(const SCandle &c)
  {
   const double r = QmeCandleRange(c);
   if(r < QME_EPSILON) return(0.5);
   return(QmeClamp((c.close - c.low) / r, 0.0, 1.0));
  }

//+------------------------------------------------------------------+
//| Score breakdown                                                  |
//+------------------------------------------------------------------+
struct SFactorScore
  {
   ENUM_QME_FACTOR   factor;
   double            raw;          // 0..1 normalised evidence
   double            weight;       // effective weight after dedup
   double            contribution; // weight * raw
   bool              available;    // false = factor had no data
  };

struct SFactorBreakdown
  {
   SFactorScore      items[QME_F_COUNT];
   double            sum;          // raw weighted sum
   double            maxSum;       // sum of applied weights (for normalisation)
   double            penalty;      // explicit deductions (conflicts, stale data)
   double            score;        // final 0..100
   int               applied;      // number of usable factors
   int               familiesUsed; // dedup bookkeeping
  };

void QmeBreakdownReset(SFactorBreakdown &b)
  {
   for(int i = 0; i < QME_F_COUNT; i++)
     {
      b.items[i].factor       = (ENUM_QME_FACTOR)i;
      b.items[i].raw          = 0.0;
      b.items[i].weight       = 0.0;
      b.items[i].contribution = 0.0;
      b.items[i].available    = false;
     }
   b.sum = 0.0;
   b.maxSum = 0.0;
   b.penalty = 0.0;
   b.score = 0.0;
   b.applied = 0;
   b.familiesUsed = 0;
  }

//--- final normalisation: weighted evidence -> 0..100 with penalty applied
double QmeBreakdownFinalise(SFactorBreakdown &b)
  {
   double total = 0.0;
   if(b.maxSum > QME_EPSILON)
      total = 100.0 * b.sum / b.maxSum;
   total -= b.penalty;
   b.score = QmeClamp(total, 0.0, QME_SCORE_MAX);
   return(b.score);
  }

//+------------------------------------------------------------------+
//| Market structure                                                 |
//+------------------------------------------------------------------+
struct SStructurePoint
  {
   datetime          time;
   double            price;
   bool              isHigh;     // true = swing high, false = swing low
   int               barIndex;   // index in the closed-bar series (0 = newest)
   double            strength;   // 0..1 relative prominence
  };

struct SStructureState
  {
   SStructurePoint   swings[QME_MAX_SWINGS];
   int               swingCount;
   double            lastSwingHigh;
   double            lastSwingLow;
   datetime          lastSwingHighTime;
   datetime          lastSwingLowTime;
   bool              higherHigh;
   bool              higherLow;
   bool              lowerHigh;
   bool              lowerLow;
   ENUM_QME_TREND    trend;
   ENUM_QME_STRUCT_EVENT lastEvent;
   datetime          lastEventTime;
   double            lastBrokenLevel;
   bool              mssConfirmed;
   ENUM_QME_SIDE     mssSide;
   bool              valid;
  };

void QmeStructureReset(SStructureState &s)
  {
   s.swingCount = 0;
   s.lastSwingHigh = 0.0;
   s.lastSwingLow = 0.0;
   s.lastSwingHighTime = 0;
   s.lastSwingLowTime = 0;
   s.higherHigh = false;
   s.higherLow = false;
   s.lowerHigh = false;
   s.lowerLow = false;
   s.trend = QME_TREND_UNKNOWN;
   s.lastEvent = QME_STRUCT_NONE;
   s.lastEventTime = 0;
   s.lastBrokenLevel = 0.0;
   s.mssConfirmed = false;
   s.mssSide = QME_SIDE_NONE;
   s.valid = false;
  }

//+------------------------------------------------------------------+
//| Liquidity                                                        |
//+------------------------------------------------------------------+
struct SLiquidityLevel
  {
   double            price;
   ENUM_QME_SIDE     side;       // BUY = buy-side liquidity above price, SELL = below
   bool              observed;   // true: measured from bars; false: inferred/derived
   double            strength;   // 0..1
   int               touches;
   datetime          birthTime;
   ENUM_QME_ZONE_SOURCE source;
  };

struct SLiquidityMap
  {
   SLiquidityLevel   levels[QME_MAX_LIQUIDITY_LEVELS];
   int               count;
   double            equalHighTolerance;   // price distance treated as "equal"
   double            rangeHigh;
   double            rangeLow;
   double            pdh;
   double            pdl;
   double            pwh;
   double            pwl;
   double            sessionHigh;
   double            sessionLow;
   bool              valid;
  };

void QmeLiquidityReset(SLiquidityMap &m)
  {
   m.count = 0;
   m.equalHighTolerance = 0.0;
   m.rangeHigh = 0.0;
   m.rangeLow = 0.0;
   m.pdh = 0.0; m.pdl = 0.0; m.pwh = 0.0; m.pwl = 0.0;
   m.sessionHigh = 0.0; m.sessionLow = 0.0;
   m.valid = false;
  }

//+------------------------------------------------------------------+
//| Volume profile                                                   |
//+------------------------------------------------------------------+
struct SVolumeNode
  {
   double            priceLow;
   double            priceHigh;
   double            mid;
   long              volume;
   double            share;      // fraction of total volume
   bool              highNode;
   bool              lowNode;
  };

struct SVolumeProfile
  {
   SVolumeNode       nodes[64];
   int               nodeCount;
   double            poc;
   double            valueAreaHigh;
   double            valueAreaLow;
   double            totalVolume;
   bool              valid;
  };

//+------------------------------------------------------------------+
//| Trading zone (single canonical definition, used by Zones/*)      |
//+------------------------------------------------------------------+
struct STradingZone
  {
   ulong                  id;             // deterministic identity (ZoneIdentity)
   string                 symbol;
   ENUM_TIMEFRAMES        tf;
   ENUM_QME_SIDE          side;           // BUY = demand, SELL = supply
   ENUM_QME_ZONE_SOURCE   source;
   double                 upper;
   double                 lower;
   datetime               created;
   datetime               lastTouched;
   datetime               expires;
   int                    touches;
   double                 strength;       // 0..1 structural quality
   double                 confidence;     // 0..1 corroboration
   ENUM_QME_ZONE_STATE    state;
   double                 invalidateLevel; // price that kills the zone
   uint                   factorMask;      // supporting factor bits
   bool                   merged;
   ulong                  parentId;        // 0 if not merged
  };

void QmeZoneClear(STradingZone &z)
  {
   z.id = 0;
   z.symbol = "";
   z.tf = PERIOD_CURRENT;
   z.side = QME_SIDE_NONE;
   z.source = QME_ZONE_SRC_NONE;
   z.upper = 0.0;
   z.lower = 0.0;
   z.created = 0;
   z.lastTouched = 0;
   z.expires = 0;
   z.touches = 0;
   z.strength = 0.0;
   z.confidence = 0.0;
   z.state = QME_ZSTAT_FRESH;
   z.invalidateLevel = 0.0;
   z.factorMask = 0;
   z.merged = false;
   z.parentId = 0;
  }

double QmeZoneHeight(const STradingZone &z)  { return(MathAbs(z.upper - z.lower)); }
double QmeZoneMid(const STradingZone &z)     { return(0.5 * (z.upper + z.lower)); }

bool QmeZoneContains(const STradingZone &z, const double price)
  {
   const double lo = MathMin(z.upper, z.lower);
   const double hi = MathMax(z.upper, z.lower);
   return(price >= lo - QME_PRICE_EPS && price <= hi + QME_PRICE_EPS);
  }

//--- a zone can only be used while it is neither invalidated nor expired
bool QmeZoneIsActive(const STradingZone &z, const datetime now)
  {
   if(z.state == QME_ZSTAT_INVALIDATED || z.state == QME_ZSTAT_EXPIRED) return(false);
   if(z.expires > 0 && now > z.expires) return(false);
   if(z.upper <= 0.0 || z.lower <= 0.0) return(false);
   if(QmeZoneMid(z) < z.invalidateLevel - QME_PRICE_EPS && z.side == QME_SIDE_BUY) return(false);
   if(QmeZoneMid(z) > z.invalidateLevel + QME_PRICE_EPS && z.side == QME_SIDE_SELL && z.invalidateLevel > 0.0) return(false);
   return(true);
  }

//--- do two zones overlap by at least `overlapPct` of the smaller one?
bool QmeZonesOverlap(const STradingZone &a, const STradingZone &b, const double overlapPct)
  {
   const double aLo = MathMin(a.upper, a.lower), aHi = MathMax(a.upper, a.lower);
   const double bLo = MathMin(b.upper, b.lower), bHi = MathMax(b.upper, b.lower);
   const double inter = MathMax(0.0, MathMin(aHi, bHi) - MathMax(aLo, bLo));
   const double small = MathMin(aHi - aLo, bHi - bLo);
   if(small < QME_PRICE_EPS) return(false);
   return(100.0 * inter / small >= overlapPct);
  }

//+------------------------------------------------------------------+
//| Price-action facts                                               |
//+------------------------------------------------------------------+
struct SFvgRecord
  {
   datetime          time;
   ENUM_QME_SIDE     side;        // BUY = bullish FVG (gap below price)
   double            upper;
   double            lower;
   bool              filled;
   double            fillRatio;
  };

struct SOrderBlockRecord
  {
   datetime          time;
   ENUM_QME_SIDE     side;
   double            upper;
   double            lower;
   bool              mitigated;
   double            displacement;   // 0..1 strength of the impulse out of the block
  };

struct SCandleFacts
  {
   ENUM_QME_CANDLE_PATTERN pattern;
   double            bodyRatio;
   double            upperWickRatio;
   double            lowerWickRatio;
   double            closePos;
   bool              displacement;   // body >> average range
   double            displacementScore;
   bool              valid;
  };

void QmeCandleFactsClear(SCandleFacts &f)
  {
   f.pattern = QME_CANDLE_NONE;
   f.bodyRatio = 0.0;
   f.upperWickRatio = 0.0;
   f.lowerWickRatio = 0.0;
   f.closePos = 0.5;
   f.displacement = false;
   f.displacementScore = 0.0;
   f.valid = false;
  }

//+------------------------------------------------------------------+
//| Premium / discount context                                       |
//+------------------------------------------------------------------+
struct SRangeContext
  {
   double            rangeHigh;
   double            rangeLow;
   double            equilibrium;
   double            position;    // 0 = range low, 1 = range high
   bool              premium;     // position > 0.5
   bool              discount;
   bool              valid;
  };

//+------------------------------------------------------------------+
//| Symbol specification (canonical copy of broker constraints)      |
//+------------------------------------------------------------------+
struct SSymbolSpec
  {
   string            symbol;
   string            description;
   string            path;
   int               digits;
   double            point;
   double            tickSize;
   double            tickValue;
   double            contractSize;
   double            volMin;
   double            volMax;
   double            volStep;
   int               stopsLevelPoints;
   int               freezeLevelPoints;
   int               tradeMode;        // SYMBOL_TRADE_MODE_*
   int               execMode;         // SYMBOL_TRADE_EXECUTION_*
   int               fillingMask;      // SYMBOL_FILLING_* bit mask
   double            swapLong;
   double            swapShort;
   double            marginInitial;
   bool              tradeAllowed;
   bool              selected;
   bool              valid;
  };

void QmeSymbolSpecClear(SSymbolSpec &s)
  {
   s.symbol = ""; s.description = ""; s.path = "";
   s.digits = 0; s.point = 0.0; s.tickSize = 0.0; s.tickValue = 0.0; s.contractSize = 0.0;
   s.volMin = 0.0; s.volMax = 0.0; s.volStep = 0.0;
   s.stopsLevelPoints = 0; s.freezeLevelPoints = 0;
   s.tradeMode = 0; s.execMode = 0; s.fillingMask = 0;
   s.swapLong = 0.0; s.swapShort = 0.0; s.marginInitial = 0.0;
   s.tradeAllowed = false; s.selected = false; s.valid = false;
  }

//--- value of one price unit per 1.0 lot in account currency
double QmeValuePerPriceUnit(const SSymbolSpec &s)
  {
   if(s.tickSize <= 0.0 || s.tickValue <= 0.0) return(0.0);
   return(s.tickValue / s.tickSize);
  }

//+------------------------------------------------------------------+
//| Account                                                          |
//+------------------------------------------------------------------+
struct SAccountContext
  {
   ENUM_QME_ACCOUNT_MODE mode;
   long              login;
   string            server;
   string            company;
   string            currency;
   int               leverage;
   double            balance;
   double            equity;
   double            margin;
   double            freeMargin;
   double            marginLevel;
   double            credit;
   double            profit;
   bool              accountTradeAllowed;
   bool              expertTradeAllowed;
   bool              terminalTradeAllowed;
   bool              mqlTradeAllowed;
   bool              connected;
   datetime          updated;
   bool              valid;
  };

void QmeAccountClear(SAccountContext &a)
  {
   a.mode = QME_ACC_UNKNOWN;
   a.login = 0;
   a.server = ""; a.company = ""; a.currency = "";
   a.leverage = 0;
   a.balance = 0.0; a.equity = 0.0; a.margin = 0.0;
   a.freeMargin = 0.0; a.marginLevel = 0.0; a.credit = 0.0; a.profit = 0.0;
   a.accountTradeAllowed = false;
   a.expertTradeAllowed = false;
   a.terminalTradeAllowed = false;
   a.mqlTradeAllowed = false;
   a.connected = false;
   a.updated = 0;
   a.valid = false;
  }

//+------------------------------------------------------------------+
//| Data quality                                                     |
//+------------------------------------------------------------------+
struct SDataQuality
  {
   bool              ok;
   bool              stale;
   bool              missingBars;
   bool              inconsistentBars;
   bool              spreadAbnormal;
   int               closedBars;
   double            barAgeSeconds;
   double            avgSpread;
   double            curSpread;
   int               flags;
   string            note;
  };

void QmeDataQualityClear(SDataQuality &q)
  {
   q.ok = false; q.stale = false; q.missingBars = false; q.inconsistentBars = false;
   q.spreadAbnormal = false; q.closedBars = 0; q.barAgeSeconds = 0.0;
   q.avgSpread = 0.0; q.curSpread = 0.0; q.flags = 0; q.note = "";
  }

//+------------------------------------------------------------------+
//| Trade candidate (pre-risk, pre-execution intent)                 |
//+------------------------------------------------------------------+
struct STradeCandidate
  {
   string               symbol;
   ENUM_QME_SIDE        side;
   ENUM_TIMEFRAMES      tf;
   ulong                zoneId;
   ENUM_QME_ZONE_SOURCE source;
   double               zoneUpper;
   double               zoneLower;
   double               entry;
   double               stopLoss;
   double               takeProfit;
   double               rr;
   double               score;
   double               confidence;
   SFactorBreakdown     breakdown;
   datetime             created;
   bool                 valid;
  };

void QmeCandidateClear(STradeCandidate &c)
  {
   c.symbol = "";
   c.side = QME_SIDE_NONE;
   c.tf = PERIOD_CURRENT;
   c.zoneId = 0;
   c.source = QME_ZONE_SRC_NONE;
   c.zoneUpper = 0.0; c.zoneLower = 0.0;
   c.entry = 0.0; c.stopLoss = 0.0; c.takeProfit = 0.0;
   c.rr = 0.0; c.score = 0.0; c.confidence = 0.0;
   QmeBreakdownReset(c.breakdown);
   c.created = 0;
   c.valid = false;
  }

//+------------------------------------------------------------------+
//| Trading signal (full lifecycle record)                           |
//+------------------------------------------------------------------+
struct STradingSignal
  {
   ulong                 id;
   string                symbol;
   ENUM_QME_SIDE         side;
   ENUM_TIMEFRAMES       tf;
   ENUM_QME_ENTRY_TYPE   entryType;
   ENUM_QME_SIGNAL_STATE state;
   ENUM_QME_REJECT       reject;
   datetime              created;
   datetime              updated;
   datetime              expires;
   datetime              barTime;        // closed bar the signal was derived from
   double                entry;
   double                stopLoss;
   double                takeProfit1;
   double                takeProfit2;
   double                rr;
   double                riskReward;
   double                score;
   double                confidence;
   double                volume;
   double                riskMoney;
   ulong                 zoneId;
   ENUM_QME_ZONE_SOURCE  source;
   uint                  factorMask;
   SFactorBreakdown      breakdown;
   string                fingerprint;
   string                rejectNote;
   ulong                 positionTicket;
   ulong                 orderTicket;
   ulong                 dealTicket;
   ENUM_QME_EXEC_STATE   execState;
   int                   attempts;
   int                   mode;            // snapshot of account mode at approval
  };

void QmeSignalClear(STradingSignal &s)
  {
   s.id = 0;
   s.symbol = "";
   s.side = QME_SIDE_NONE;
   s.tf = PERIOD_CURRENT;
   s.entryType = QME_ENTRY_MARKET;
   s.state = QME_SIG_NONE;
   s.reject = QME_REJ_NONE;
   s.created = 0; s.updated = 0; s.expires = 0; s.barTime = 0;
   s.entry = 0.0; s.stopLoss = 0.0; s.takeProfit1 = 0.0; s.takeProfit2 = 0.0;
   s.rr = 0.0; s.riskReward = 0.0; s.score = 0.0; s.confidence = 0.0;
   s.volume = 0.0; s.riskMoney = 0.0;
   s.zoneId = 0;
   s.source = QME_ZONE_SRC_NONE;
   s.factorMask = 0;
   QmeBreakdownReset(s.breakdown);
   s.fingerprint = "";
   s.rejectNote = "";
   s.positionTicket = 0; s.orderTicket = 0; s.dealTicket = 0;
   s.execState = QME_EXEC_NONE;
   s.attempts = 0;
   s.mode = (int)QME_ACC_UNKNOWN;
  }

//+------------------------------------------------------------------+
//| Trade plan (sized, risk-validated execution intent)              |
//+------------------------------------------------------------------+
struct STradePlan
  {
   ulong                 signalId;
   string                symbol;
   ENUM_QME_SIDE         side;
   ENUM_QME_ENTRY_TYPE   entryType;
   double                entry;
   double                stopLoss;
   double                takeProfit;
   double                volume;
   double                riskMoney;
   double                rr;
   double                score;
   ulong                 magic;
   ENUM_QME_ACCOUNT_MODE accountMode;
   bool                  authorized;
   bool                  riskPassed;
   ENUM_QME_REJECT       reject;
   string                fingerprint;
   datetime              created;
  };

void QmePlanClear(STradePlan &p)
  {
   p.signalId = 0; p.symbol = "";
   p.side = QME_SIDE_NONE;
   p.entryType = QME_ENTRY_MARKET;
   p.entry = 0.0; p.stopLoss = 0.0; p.takeProfit = 0.0;
   p.volume = 0.0; p.riskMoney = 0.0; p.rr = 0.0; p.score = 0.0;
   p.magic = 0;
   p.accountMode = QME_ACC_UNKNOWN;
   p.authorized = false;
   p.riskPassed = false;
   p.reject = QME_REJ_NONE;
   p.fingerprint = "";
   p.created = 0;
  }

//+------------------------------------------------------------------+
//| Risk assessment                                                  |
//+------------------------------------------------------------------+
struct SRiskAssessment
  {
   bool              passed;
   ENUM_QME_REJECT   reason;
   double            riskMoney;
   double            riskPct;
   double            volume;
   double            rr;
   double            stopDistance;
   double            slPoints;
   double            spreadCost;
   double            marginRequired;
   double            marginFreeAfter;
   double            exposureSymbolPct;
   double            exposurePortfolioPct;
   double            dailyLossPct;
   double            drawdownPct;
   int               positionsOpen;
   int               consecutiveLosses;
   int               checksRun;
   int               checksFailed;
   double            detail;       // numeric value of the failing check
   string            note;
  };

void QmeRiskClear(SRiskAssessment &r)
  {
   r.passed = false;
   r.reason = QME_REJ_NONE;
   r.riskMoney = 0.0; r.riskPct = 0.0; r.volume = 0.0; r.rr = 0.0;
   r.stopDistance = 0.0; r.slPoints = 0.0; r.spreadCost = 0.0;
   r.marginRequired = 0.0; r.marginFreeAfter = 0.0;
   r.exposureSymbolPct = 0.0; r.exposurePortfolioPct = 0.0;
   r.dailyLossPct = 0.0; r.drawdownPct = 0.0;
   r.positionsOpen = 0; r.consecutiveLosses = 0;
   r.checksRun = 0; r.checksFailed = 0;
   r.detail = 0.0;
   r.note = "";
  }

//+------------------------------------------------------------------+
//| Execution result                                                 |
//+------------------------------------------------------------------+
struct SExecutionResult
  {
   bool              requestBuilt;
   bool              sent;
   bool              confirmed;      // broker-confirmed position/order exists
   uint              retcode;
   uint              orderCheckRetcode;
   ulong             orderTicket;
   ulong             dealTicket;
   ulong             positionTicket;
   double            requestedVolume;
   double            filledVolume;
   double            requestedPrice;
   double            filledPrice;
   datetime          time;
   int               attempts;
   int               lastError;
   ENUM_QME_EXEC_STATE state;
   ENUM_QME_REJECT   reject;
   string            comment;
  };

void QmeExecClear(SExecutionResult &e)
  {
   e.requestBuilt = false; e.sent = false; e.confirmed = false;
   e.retcode = 0; e.orderCheckRetcode = 0;
   e.orderTicket = 0; e.dealTicket = 0; e.positionTicket = 0;
   e.requestedVolume = 0.0; e.filledVolume = 0.0;
   e.requestedPrice = 0.0; e.filledPrice = 0.0;
   e.time = 0; e.attempts = 0; e.lastError = 0;
   e.state = QME_EXEC_NONE;
   e.reject = QME_REJ_NONE;
   e.comment = "";
  }

//+------------------------------------------------------------------+
//| Position context                                                 |
//+------------------------------------------------------------------+
struct SPositionContext
  {
   ulong                 ticket;
   string                symbol;
   ENUM_QME_SIDE         side;
   double                volume;
   double                openPrice;
   double                stopLoss;
   double                takeProfit;
   double                profit;
   double                swap;
   datetime              openTime;
   ulong                 magic;
   ulong                 signalId;
   ENUM_QME_SIGNAL_STATE state;
   bool                  hasProtection;   // SL and TP both present
   bool                  foundInBroker;
  };

void QmePositionClear(SPositionContext &p)
  {
   p.ticket = 0; p.symbol = "";
   p.side = QME_SIDE_NONE;
   p.volume = 0.0; p.openPrice = 0.0; p.stopLoss = 0.0; p.takeProfit = 0.0;
   p.profit = 0.0; p.swap = 0.0;
   p.openTime = 0; p.magic = 0; p.signalId = 0;
   p.state = QME_SIG_NONE;
   p.hasProtection = false;
   p.foundInBroker = false;
  }

//+------------------------------------------------------------------+
//| Market snapshot (per symbol, per scan)                           |
//+------------------------------------------------------------------+
struct SMarketSnapshot
  {
   string            symbol;
   datetime          time;
   ENUM_TIMEFRAMES   entryTf;
   double            bid;
   double            ask;
   double            spreadPoints;
   double            atr;
   double            atrAvg;
   double            rsi;
   double            emaFast;
   double            emaSlow;
   double            emaTrend;
   ENUM_QME_REGIME   regime;
   ENUM_QME_TREND    trend;
   ENUM_QME_VOLATILITY volatility;
   ENUM_QME_SESSION  session;
   ENUM_QME_SIDE     bias;
   double            biasScore;
   double            momentum;
   bool              structureValid;
   bool              liquidityValid;
   bool              dataValid;
   int               zoneCount;
   int               candidates;
   SDataQuality      quality;
  };

void QmeSnapshotClear(SMarketSnapshot &s)
  {
   s.symbol = "";
   s.time = 0;
   s.entryTf = PERIOD_CURRENT;
   s.bid = 0.0; s.ask = 0.0; s.spreadPoints = 0.0;
   s.atr = 0.0; s.atrAvg = 0.0; s.rsi = 0.0;
   s.emaFast = 0.0; s.emaSlow = 0.0; s.emaTrend = 0.0;
   s.regime = QME_REGIME_UNKNOWN;
   s.trend = QME_TREND_UNKNOWN;
   s.volatility = QME_VOL_UNKNOWN;
   s.session = QME_SESSION_UNKNOWN;
   s.bias = QME_SIDE_NONE;
   s.biasScore = 0.0;
   s.momentum = 0.0;
   s.structureValid = false;
   s.liquidityValid = false;
   s.dataValid = false;
   s.zoneCount = 0;
   s.candidates = 0;
   QmeDataQualityClear(s.quality);
  }

//+------------------------------------------------------------------+
//| Break-even / validity helpers used by multiple modules           |
//+------------------------------------------------------------------+
//--- reward:risk for a long/short plan; 0 when ill-defined
double QmeComputeRR(const ENUM_QME_SIDE side, const double entry,
                    const double sl, const double tp)
  {
   if(side == QME_SIDE_NONE) return(0.0);
   const double risk = MathAbs(entry - sl);
   if(risk < QME_PRICE_EPS) return(0.0);
   double reward = (side == QME_SIDE_BUY) ? (tp - entry) : (entry - tp);
   if(reward <= 0.0) return(0.0);
   return(reward / risk);
  }

//--- is the stop on the correct side of entry and non-zero?
bool QmeStopIsValid(const ENUM_QME_SIDE side, const double entry, const double sl)
  {
   if(side == QME_SIDE_NONE || !QmeIsFinite(entry) || !QmeIsFinite(sl)) return(false);
   if(entry <= 0.0 || sl <= 0.0) return(false);
   if(side == QME_SIDE_BUY)  return(sl < entry - QME_PRICE_EPS);
   return(sl > entry + QME_PRICE_EPS);
  }

bool QmeTargetIsValid(const ENUM_QME_SIDE side, const double entry, const double tp)
  {
   if(side == QME_SIDE_NONE || !QmeIsFinite(entry) || !QmeIsFinite(tp)) return(false);
   if(entry <= 0.0 || tp <= 0.0) return(false);
   if(side == QME_SIDE_BUY)  return(tp > entry + QME_PRICE_EPS);
   return(tp < entry - QME_PRICE_EPS);
  }

#endif // __QME_CORE_TYPES_MQH__
//+------------------------------------------------------------------+
