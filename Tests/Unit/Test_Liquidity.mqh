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

   //--- sweep detection on fabricated bars is not attempted: report a skip
   g_kit.Skip("sweep detection requires live bars (covered by integration tests)");

   return(g_kit.End());
  }

#endif // __QME_TEST_LIQUIDITY_MQH__
//+------------------------------------------------------------------+
