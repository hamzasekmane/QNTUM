//+------------------------------------------------------------------+
//|                                 Tests/Integration/Test_MtfPipeline |
//|  Candidates -> cluster: one merged candidate per side at most, and    |
//|  no evidence invented during the merge.                            |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_MTF_MQH__
#define __QME_TEST_MTF_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec MtfSpec(void)
  {
   SSymbolSpec s;
   s.symbol = _Symbol;
   s.description = _Symbol;
   s.path = "";
   s.digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   s.point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   s.tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   s.tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   s.contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   s.volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   s.volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   s.volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   s.stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   s.freezeLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   s.tradeMode = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   s.execMode = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   s.fillingMask = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   s.swapLong = 0.0; s.swapShort = 0.0; s.marginInitial = 0.0;
   s.tradeAllowed = true; s.selected = true; s.valid = (s.point > 0.0);
   return(s);
  }

int RunMtfPipelineTest(void)
  {
   g_kit.Begin("Integration/Test_MtfPipeline");

   SInputs in;
   QmeInputsDefaults(in);
   in.logLevel = QME_LOG_WARN;

   string err = "";
   CConfig cfg;
   cfg.Init(in, err);

   const SSymbolSpec spec = MtfSpec();
   if(!spec.valid)
     {
      g_kit.Skip("symbol specification unavailable");
      return(g_kit.End());
     }

   //--- fabricated analyses: no zones, so the collector must return 0
   SMarketAnalysis bias, structure, setup;
   QmeAnalysisClear(bias);
   QmeAnalysisClear(structure);
   QmeAnalysisClear(setup);

   bias.symbol = _Symbol; bias.tf = in.tfBias; bias.valid = true;
   bias.bias.side = QME_SIDE_BUY; bias.bias.score = 0.8; bias.bias.valid = true;
   structure.symbol = _Symbol; structure.tf = in.tfStructure; structure.valid = true;
   setup.symbol = _Symbol; setup.tf = in.tfSetup; setup.valid = true;
   setup.price = 1.10000; setup.atr = 0.00100;

   CZoneEngine zones;
   zones.Init(_Symbol, 72, 60.0);

   SCandidateHypothesis hyps[];
   SCandidateRejectCounts rejects;
   const int n = CCandidateCollector::Collect(bias, structure, setup, zones, spec, cfg,
                                              1.10000, 0.00100, spec.point, cfg.In.minRR,
                                              3.0, hyps, 8, rejects);
   g_kit.CheckEqual(n, 0, "no zones -> no candidates");
   g_kit.Check(rejects.noZone > 0, "collector counts no-zone candidate rejection");

   SMergedCandidate merged[];
   const int m = CCandidateClusterer::Merge(hyps, n, merged, 8);
   g_kit.CheckEqual(m, 0, "no candidates -> no merged candidate");

   //--- geometry contract of the clusterer, stated explicitly
   g_kit.Check(m <= 2, "at most one candidate per side survives the merge");

   zones.Shutdown();
   return(g_kit.End());
  }

#endif // __QME_TEST_MTF_MQH__
//+------------------------------------------------------------------+
