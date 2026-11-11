//+------------------------------------------------------------------+
//|                                    Tests/Unit/Test_Liquidity      |
//|  Liquidity map lookups are pure and are tested exactly.               |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_LIQUIDITY_MQH__
#define __QME_TEST_LIQUIDITY_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunLiquidityTests(void)
  {
   g_kit.Begin("Unit/Test_Liquidity");

   SLiquidityMap map;
   QmeLiquidityReset(map);
   g_kit.CheckEqual(map.count, 0, "fresh liquidity map is empty");
   g_kit.Check(!map.valid, "fresh liquidity map is not valid");

   //--- fabricate three levels around the price
   SLiquidityLevel l1, l2, l3;
   l1.price = 1.1050; l1.side = QME_SIDE_BUY;  l1.strength = 0.8; l1.touches = 2;
   l1.observed = true; l1.source = QME_ZONE_SRC_LIQUIDITY; l1.birthTime = TimeCurrent();
   l2.price = 1.1100; l2.side = QME_SIDE_BUY;  l2.strength = 0.6; l2.touches = 1;
   l2.observed = true; l2.source = QME_ZONE_SRC_PDH_PDL; l2.birthTime = TimeCurrent();
   l3.price = 1.0950; l3.side = QME_SIDE_SELL; l3.strength = 0.7; l3.touches = 3;
   l3.observed = true; l3.source = QME_ZONE_SRC_LIQUIDITY; l3.birthTime = TimeCurrent();

   map.levels[0] = l1; map.levels[1] = l2; map.levels[2] = l3;
   map.count = 3;
   map.valid = true;

   SLiquidityLevel above, below;
   g_kit.Check(CLiquidityMapBuilder::NearestAbove(map, 1.1000, above), "finds the nearest level above");
   g_kit.CheckClose(above.price, 1.1050, 1e-8, "nearest above is the closest one");

   g_kit.Check(CLiquidityMapBuilder::NearestBelow(map, 1.1000, below), "finds the nearest level below");
   g_kit.CheckClose(below.price, 1.0950, 1e-8, "nearest below is the closest one");

   //--- no level beyond the range must return false, not a fake price
   SLiquidityLevel none;
   g_kit.Check(!CLiquidityMapBuilder::NearestAbove(map, 1.2000, none), "no level above the range");

   // Closed-bar classifier: oldest-to-newest, with one later close to confirm.
   SLiquidityBar bars[];
   ArrayResize(bars, 3);
   bars[0].high=9.8;  bars[0].low=9.0;  bars[0].close=9.5;
   bars[1].high=10.6; bars[1].low=9.7;  bars[1].close=9.9; // raid above 10, closes back inside
   bars[2].high=9.9;  bars[2].low=8.8;  bars[2].close=8.9; // later CHoCH below 9.2
   SLiquidityOutcome outcome = CLiquidityOutcome::Classify(bars, 3, 10.0,
                                      QME_SIDE_BUY, 9.2, 1, 0.05);
   g_kit.CheckEqual(outcome.classification, QME_LIQUIDITY_SWEEP,
                    "wick raid plus rejection and later CHoCH classifies sweep");
   g_kit.CheckEqual(outcome.sweepBar, 1, "reports the liquidity raid bar");

   bars[1].close=10.3; bars[1].high=10.4;
   bars[2].close=10.25; bars[2].high=10.5;
   outcome = CLiquidityOutcome::Classify(bars, 3, 10.0, QME_SIDE_BUY,
                                          9.2, 1, 0.05);
   g_kit.CheckEqual(outcome.classification, QME_LIQUIDITY_BREAKOUT,
                    "close outside plus later hold classifies breakout");

   bars[2].close=9.95;
   outcome = CLiquidityOutcome::Classify(bars, 3, 10.0, QME_SIDE_BUY,
                                          9.2, 1, 0.05);
   g_kit.CheckEqual(outcome.classification, QME_LIQUIDITY_WAIT,
                    "failed breakout hold is not mislabeled as sweep");

   // Mirror case: raid below equal lows, then close above opposite structure.
   bars[0].high=10.5; bars[0].low=9.7; bars[0].close=10.2;
   bars[1].high=10.2; bars[1].low=9.4; bars[1].close=10.1;
   bars[2].high=10.4; bars[2].low=9.8; bars[2].close=10.3;
   outcome = CLiquidityOutcome::Classify(bars, 3, 9.6, QME_SIDE_SELL,
                                          10.25, 1, 0.05);
   g_kit.CheckEqual(outcome.classification, QME_LIQUIDITY_SWEEP,
                    "sell-side raid plus bullish structure close confirms reversal");

   // Rejection alone is deliberately not a confirmed trade signal.
   bars[2].close=10.0;
   outcome = CLiquidityOutcome::Classify(bars, 3, 9.6, QME_SIDE_SELL,
                                          10.25, 1, 0.05);
   g_kit.CheckEqual(outcome.classification, QME_LIQUIDITY_WAIT,
                    "rejection without CHoCH remains WAIT");

   return(g_kit.End());
  }

#endif // __QME_TEST_LIQUIDITY_MQH__
//+------------------------------------------------------------------+
