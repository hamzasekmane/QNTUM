//+------------------------------------------------------------------+
//|                              Tests/Integration/Test_MarketPipeline |
//|  Market data -> scanner -> analysis. Requires terminal history;      |
//|  when history is missing the test SKIPS (it never passes silently).   |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_MARKET_MQH__
#define __QME_TEST_MARKET_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunMarketPipelineTest(void)
  {
   g_kit.Begin("Integration/Test_MarketPipeline");

   SInputs in;
   QmeInputsDefaults(in);
   in.symbolList = _Symbol;
   in.barsContext = 300;
   in.logLevel = QME_LOG_WARN;

   string err = "";
   CConfig cfg;
   if(!cfg.Init(in, err))
     {
      g_kit.Check(false, "configuration initialises: " + err);
      return(g_kit.End());
     }
   g_kit.Check(true, "configuration initialises");

   CMarketData data;
   if(!data.Init(in, err))
     {
      g_kit.Skip("market data init failed: " + err);
      return(g_kit.End());
     }

   CScanner scanner;
   if(!scanner.Init(&data, &cfg, in, err))
     {
      g_kit.Skip("scanner init failed: " + err);
      data.Shutdown();
      return(g_kit.End());
     }

   string note = "";
   const bool scanned = scanner.Scan(true, note);
   if(!scanned)
     {
      g_kit.Skip("scan produced no analysable symbol: " + note);
      scanner.Shutdown();
      data.Shutdown();
      return(g_kit.End());
     }
   g_kit.Check(true, "scan completed: " + note);

   CSymbolRuntime *rt = scanner.At(0);
   if(rt == NULL)
     {
      g_kit.Check(false, "scanner exposes symbol runtime 0");
      scanner.Shutdown();
      data.Shutdown();
      return(g_kit.End());
     }

   g_kit.Check(StringLen(rt.symbol) > 0, "runtime has a symbol");
   g_kit.Check(rt.snapshot.time > 0, "snapshot carries a timestamp");

   int readySlots = 0;
   for(int i = 0; i < QME_TF_SLOTS; i++)
      if(rt.tfReady[i]) readySlots++;
   g_kit.Check(readySlots > 0, "at least one timeframe is ready");
   g_kit.Check(readySlots <= QME_TF_SLOTS, "timeframe slots are bounded");

   //--- the analysis must be internally coherent
   if(rt.tfReady[4])
     {
      const SMarketAnalysis a = rt.analysis[4];
      g_kit.Check(a.price > 0.0, "analysis price is positive");
      g_kit.Check(a.atr > 0.0, "analysis ATR is positive");
      g_kit.Check(a.tf == rt.ctx[4].Timeframe(), "analysis timeframe matches its context");
      g_kit.Check(a.valid == (a.structureValid && a.liquidityValid && a.trend.valid && a.bias.valid),
                  "valid flag equals the conjunction of its parts");
     }
   else
      g_kit.Skip("entry timeframe not ready in this environment");

   scanner.Shutdown();
   data.Shutdown();
   return(g_kit.End());
  }

#endif // __QME_TEST_MARKET_MQH__
//+------------------------------------------------------------------+
