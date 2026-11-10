//+------------------------------------------------------------------+
//|                                        Tests/Unit/Test_Entry      |
//|  CEntryRig geometry: stops and targets on the correct side, RR      |
//|  honest, and invalid zones refused instead of guessed.              |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_ENTRY_MQH__
#define __QME_TEST_ENTRY_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec MakeSpec(const string symbol, const double point, const double tickValue,
                     const double tickSize)
  {
   SSymbolSpec s;
   s.symbol = symbol;
   s.description = symbol;
   s.path = "";
   s.digits = 5;
   s.point = point;
   s.tickSize = tickSize;
   s.tickValue = tickValue;
   s.contractSize = 100000.0;
   s.volMin = 0.01;
   s.volMax = 100.0;
   s.volStep = 0.01;
   s.stopsLevelPoints = 0;
   s.freezeLevelPoints = 0;
   s.tradeMode = SYMBOL_TRADE_MODE_FULL;
   s.execMode = SYMBOL_TRADE_EXECUTION_MARKET;
   s.fillingMask = SYMBOL_FILLING_IOC;
   s.swapLong = 0.0;
   s.swapShort = 0.0;
   s.marginInitial = 0.0;
   s.tradeAllowed = true;
   s.selected = true;
   s.valid = true;
   return(s);
  }

STradingZone MakeZone(const ENUM_QME_SIDE side, const double lower, const double upper)
  {
   const datetime now = TimeCurrent();
   STradingZone z;
   z.id = CZoneIdentity::Make("EURUSD", PERIOD_M15, side, QME_ZONE_SRC_ORDER_BLOCK,
                              lower, upper, 0.00001);
   z.symbol = "EURUSD";
   z.tf = PERIOD_M15;
   z.side = side;
   z.source = QME_ZONE_SRC_ORDER_BLOCK;
   z.lower = lower;
   z.upper = upper;
   z.created = now - 1800;
   z.lastTouched = now - 300;
   z.expires = now + 86400;
   z.touches = 1;
   z.strength = 0.8;
   z.confidence = 0.7;
   z.state = QME_ZSTAT_FRESH;
   z.invalidateLevel = (side == QME_SIDE_BUY) ? lower - 0.0010 : upper + 0.0010;
   z.factorMask = 0;
   z.merged = false;
   z.parentId = 0;
   return(z);
  }

int RunEntryTests(void)
  {
   g_kit.Begin("Unit/Test_Entry");
   const SSymbolSpec spec = MakeSpec("EURUSD", 0.00001, 1.0, 0.00001);

   //--- BUY from a demand zone
   const STradingZone demand = MakeZone(QME_SIDE_BUY, 1.10000, 1.10100);
   const SEntrySpec buy = CEntryRig::FromZone(demand, QME_SIDE_BUY, 1.10050, 0.00100,
                                              0.00001, spec, 2.0, 3.0, 0.25);
   g_kit.Check(buy.valid, "buy rig is valid for a clean demand zone");
   g_kit.Check(buy.stop < buy.entry, "buy stop is below the entry");
   g_kit.Check(buy.target1 > buy.entry, "buy target is above the entry");
   g_kit.Check(buy.rr >= 1.5, "buy rr respects the request");
   g_kit.Check(buy.stopDistance > 0.0, "buy stop distance is positive");

   //--- SELL from a supply zone
   const STradingZone supply = MakeZone(QME_SIDE_SELL, 1.10200, 1.10300);
   const SEntrySpec sell = CEntryRig::FromZone(supply, QME_SIDE_SELL, 1.10250, 0.00100,
                                               0.00001, spec, 2.0, 3.0, 0.25);
   g_kit.Check(sell.valid, "sell rig is valid for a clean supply zone");
   g_kit.Check(sell.stop > sell.entry, "sell stop is above the entry");
   g_kit.Check(sell.target1 < sell.entry, "sell target is below the entry");

   //--- an inverted zone must be refused, not repaired
   STradingZone broken = demand;
   broken.upper = 1.09900;
   broken.lower = 1.10100;
   const SEntrySpec bad = CEntryRig::FromZone(broken, QME_SIDE_BUY, 1.10050, 0.00100,
                                              0.00001, spec, 2.0, 3.0, 0.25);
   g_kit.Check(!bad.valid, "inverted zone is refused");
   g_kit.Check(bad.reason != QME_REJ_NONE, "refusal carries a reason");

   //--- a zero ATR must not produce a stop
   const SEntrySpec noAtr = CEntryRig::FromZone(demand, QME_SIDE_BUY, 1.10050, 0.0,
                                                0.00001, spec, 2.0, 3.0, 0.25);
   g_kit.Check(!noAtr.valid, "zero ATR is refused");

   //--- stops helpers agree with the geometry
   g_kit.Check(QmeStopIsValid(QME_SIDE_BUY, 1.10050, 1.10000), "QmeStopIsValid accepts a buy stop below");
   g_kit.Check(!QmeStopIsValid(QME_SIDE_BUY, 1.10050, 1.10100), "QmeStopIsValid rejects a buy stop above");
   g_kit.Check(QmeTargetIsValid(QME_SIDE_SELL, 1.10250, 1.10150), "QmeTargetIsValid accepts a sell target below");

   return(g_kit.End());
  }

#endif // __QME_TEST_ENTRY_MQH__
//+------------------------------------------------------------------+
