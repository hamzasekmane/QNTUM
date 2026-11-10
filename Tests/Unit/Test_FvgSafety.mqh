//+------------------------------------------------------------------+
//|                                        Tests/Unit/Test_FvgSafety   |
//|  Regression for the FVG/OrderBlock "array out of range" crash: the     |
//|  detectors write into caller-owned buffers that may be FIXED-size     |
//|  struct members (SMarketAnalysis::fvgs / ::orderBlocks). They must    |
//|  never resize them and never write past the declared capacity, on     |
//|  empty, tiny, or normal history alike.                                |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_FVGSAFETY_MQH__
#define __QME_TEST_FVGSAFETY_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunFvgSafetyTests(void)
  {
   g_kit.Begin("Unit/Test_FvgSafety");

   //--- empty input: a never-initialised series is invalid and empty
   CBarSeries empty;
   SFvgRecord fvgFixed[QME_MAX_FVGS];
   SOrderBlockRecord obFixed[QME_MAX_OBS];
   g_kit.CheckEqual(CFvgEngine::Detect(empty, 0.001, 0.25, 20, QME_MAX_FVGS, fvgFixed), 0,
                    "FVG detect on an uninitialised series returns 0");
   g_kit.CheckEqual(COrderBlockEngine::Detect(empty, 0.001, 0.0005, 1.5, 20, 60,
                                              QME_MAX_OBS, obFixed), 0,
                    "OB detect on an uninitialised series returns 0");

   //--- a zero-capacity request is refused, not crashed
   SFvgRecord none[1];
   g_kit.CheckEqual(CFvgEngine::Detect(empty, 0.001, 0.25, 20, 0, none), 0,
                    "FVG detect with maxOut=0 returns 0");

   //--- real history when the terminal offers it; otherwise skip honestly
   CBarSeries series;
   if(!series.Init(_Symbol, PERIOD_H1, 400) || !series.IsValid())
     {
      g_kit.Skip("no usable closed-bar history for " + _Symbol);
      return(g_kit.End());
     }
   g_kit.Check(series.Count() >= 64, "series carries at least the minimum history");

   //--- THE regression: fixed-size buffers, exactly like SMarketAnalysis
   const int nFvg = CFvgEngine::Detect(series, 0.001, 0.25, 20, QME_MAX_FVGS, fvgFixed);
   g_kit.Check(nFvg >= 0 && nFvg <= QME_MAX_FVGS, "FVG count respects the fixed capacity");
   const int nOb = COrderBlockEngine::Detect(series, 0.001, 0.0005, 1.5, 20, 60,
                                             QME_MAX_OBS, obFixed);
   g_kit.Check(nOb >= 0 && nOb <= QME_MAX_OBS, "OB count respects the fixed capacity");

   //--- a one-slot buffer caps the output instead of overflowing
   SFvgRecord one[1];
   const int nOne = CFvgEngine::Detect(series, 0.001, 0.25, 20, 8, one);
   g_kit.Check(nOne >= 0 && nOne <= 1, "output is capped by the actual buffer size");

   //--- repeated pipeline execution is stable (no state leaks between runs)
   SFvgRecord again[QME_MAX_FVGS];
   const int nAgain = CFvgEngine::Detect(series, 0.001, 0.25, 20, QME_MAX_FVGS, again);
   g_kit.CheckEqual(nAgain, nFvg, "repeated FVG detection is deterministic");

   //--- reported gaps are geometrically sane
   bool sane = true;
   for(int i = 0; i < nFvg; i++)
      if(fvgFixed[i].upper <= fvgFixed[i].lower) sane = false;
   g_kit.Check(sane, "every reported FVG has upper above lower");

   return(g_kit.End());
  }

#endif // __QME_TEST_FVGSAFETY_MQH__
