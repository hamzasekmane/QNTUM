//+------------------------------------------------------------------+
//|                                    Tests/Unit/Test_Structure      |
//|  Structure state handling; market-dependent parts skip cleanly.       |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_STRUCTURE_MQH__
#define __QME_TEST_STRUCTURE_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunStructureTests(void)
  {
   g_kit.Begin("Unit/Test_Structure");

   //--- fabricated state: MSS confirmation flag
   SStructureState st;
   QmeStructureReset(st);
   g_kit.Check(!CMssEngine::IsConfirmed(st), "fresh structure has no MSS");

   st.mssConfirmed = true;
   st.mssSide = QME_SIDE_BUY;
   g_kit.Check(CMssEngine::IsConfirmed(st), "MSS flag honoured");
   g_kit.CheckEqual((long)st.mssSide, (long)QME_SIDE_BUY, "MSS side preserved");

   //--- bearish confirmation is honoured the same way
   SStructureState stDown;
   QmeStructureReset(stDown);
   stDown.mssConfirmed = true;
   stDown.mssSide = QME_SIDE_SELL;
   g_kit.Check(CMssEngine::IsConfirmed(stDown), "bearish MSS flag honoured");
   g_kit.CheckEqual((long)stDown.mssSide, (long)QME_SIDE_SELL, "bearish MSS side preserved");

   //--- a side without the flag is not a confirmation
   SStructureState stSideOnly;
   QmeStructureReset(stSideOnly);
   stSideOnly.mssSide = QME_SIDE_BUY;
   g_kit.Check(!CMssEngine::IsConfirmed(stSideOnly), "MSS side alone is not a confirmation");

   //--- a structure event with no break must not claim one
   SStructureEvent ev;
   QmeStructureEventClear(ev);
   g_kit.Check(!ev.valid, "cleared structure event is invalid");

   //--- market-dependent evaluation: skip when the terminal has no data
   CTimeframeContext ctx;
   if(!ctx.Init(_Symbol, PERIOD_M15, 300))
     {
      g_kit.Skip("context init failed (no history in this environment)");
      return(g_kit.End());
     }
   if(!ctx.Refresh())
     {
      g_kit.Skip("context refresh failed (no history in this environment)");
      ctx.Shutdown();
      return(g_kit.End());
     }

   SAssetTuning tuning;
   CAssetClassTuning::Get(QME_ASSET_FX, tuning);
   SStructureState live;
   const bool ok = CStructureEngine::Evaluate(ctx, tuning, 60, live);
   g_kit.Check(ok == live.valid, "Evaluate() return matches state.valid");
   if(ok)
     {
      g_kit.Check(live.swingCount > 0, "live structure found at least one swing");
      g_kit.Check(live.lastSwingHigh >= live.lastSwingLow,
                  "last swing high is not below the last swing low");
     }
   else
      g_kit.Skip("structure not usable on this data (treated as skip, not pass)");

   ctx.Shutdown();
   return(g_kit.End());
  }

#endif // __QME_TEST_STRUCTURE_MQH__
//+------------------------------------------------------------------+
