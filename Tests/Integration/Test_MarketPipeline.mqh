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

   g_kit.Check(CTickProcessor::IsTickTimeFresh(1000, 1300, 300), "tick at age limit is fresh");
   g_kit.Check(!CTickProcessor::IsTickTimeFresh(999, 1300, 300), "old tick rejected");
   g_kit.Check(!CTickProcessor::IsTickTimeFresh(1301, 1300, 300), "future tick rejected");
   g_kit.Check(!CTickProcessor::IsTickTimeFresh(0, 1300, 300), "missing tick time rejected");
   g_kit.Check(!CTickProcessor::IsTickTimeFresh(1000, 0, 300), "missing server time rejected");

   // Canonical quote regressions: deliberately no SYMBOL_SPREAD input is
   // provided; bid, ask, spread and both timestamps come from this MqlTick.
   MqlTick quoteTick;
   ZeroMemory(quoteTick);
   quoteTick.bid = 1.10000;
   quoteTick.ask = 1.10020;
   quoteTick.time = 1300;
   quoteTick.time_msc = 1300000;
   SCanonicalQuote canonical;
   const long rawSpreadDiagnostic = 0; // broker property may be zero while a valid tick has spread
   const bool canonicalOk = QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001,
                                                    1300, 300, canonical);
   g_kit.Check(canonicalOk && rawSpreadDiagnostic == 0 && canonical.valid && canonical.symbol == "EURUSD" &&
               canonical.bid == quoteTick.bid && canonical.ask == quoteTick.ask &&
               MathAbs(canonical.spreadPoints - 20.0) < 0.000001 &&
               canonical.time == quoteTick.time && canonical.timeMsc == quoteTick.time_msc,
               "positive tick spread produces one canonical quote independent of raw SYMBOL_SPREAD");

   quoteTick.ask = quoteTick.bid;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001, 1300, 300, canonical),
               "zero-spread tick fails closed");
   quoteTick.ask = 1.10020;
   quoteTick.time = 0;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001, 1300, 300, canonical),
               "missing tick fails closed");
   quoteTick.time = 999;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001, 1300, 300, canonical),
               "stale tick fails closed at more than 300 seconds");
   quoteTick.time = 1301;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001, 1300, 300, canonical),
               "future tick fails closed");
   quoteTick.time = 1300;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.0, 1300, 300, canonical),
               "invalid zero point fails closed");
   quoteTick.bid = -1.0;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001, 1300, 300, canonical),
               "invalid nonpositive bid fails closed");
   quoteTick.bid = 1.10000;
   quoteTick.ask = 1.09990;
   g_kit.Check(!QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001, 1300, 300, canonical),
               "ask below bid fails closed");
   quoteTick.ask = 1.10020;
   SCanonicalQuote firstSymbolQuote;
   const bool firstSymbolOk = QmeBuildCanonicalQuote("EURUSD", quoteTick, 0.00001,
                                                      1300, 300, firstSymbolQuote);
   MqlTick secondSymbolTick;
   ZeroMemory(secondSymbolTick);
   secondSymbolTick.bid = 1.25000;
   secondSymbolTick.ask = 1.25100;
   secondSymbolTick.time = 1300;
   secondSymbolTick.time_msc = 1300000;
   SCanonicalQuote secondSymbolQuote;
   const bool secondSymbolOk = QmeBuildCanonicalQuote("GBPUSD", secondSymbolTick, 0.00010,
                                                       1300, 300, secondSymbolQuote);
   g_kit.Check(firstSymbolOk && secondSymbolOk && firstSymbolQuote.symbol == "EURUSD" &&
               secondSymbolQuote.symbol == "GBPUSD" && firstSymbolQuote.bid != secondSymbolQuote.bid &&
               MathAbs(firstSymbolQuote.spreadPoints - 20.0) < 0.000001 &&
               MathAbs(secondSymbolQuote.spreadPoints - 10.0) < 0.000001,
               "multi-symbol quotes preserve each symbol identity, prices and point size");

   // Deterministic broker-session fixtures for the reported M15 interval.
   // Weekly times used here are deliberately explicit; runtime uses each
   // broker's SymbolInfoSessionQuote schedule rather than these test values.
   const int m15=900;
   const datetime fxOlder=StringToTime("2026.11.06 23:45");
   const datetime fxNewer=StringToTime("2026.11.09 00:00");
   const datetime xauNewer=StringToTime("2026.11.09 01:00");
   bool fxOpenBar=false;
   for(datetime bt=fxOlder+m15;bt<fxNewer;bt+=m15)
     {
      MqlDateTime bd; TimeToStruct(bt,bd);
      SQuoteSessionWindow w[]; ArrayResize(w,0);
      // Friday quote close at 23:45; no weekend quote windows in fixture.
      if(bd.day_of_week==5) { ArrayResize(w,1); w[0].startSecond=0; w[0].endSecond=85500; }
      if(QmeBarOverlapsQuoteWindows(bt,m15,bd.day_of_week,w,ArraySize(w))) fxOpenBar=true;
     }
   g_kit.Check(!fxOpenBar,"reported FX Friday-Monday 173700s interval is closed in explicit weekend schedule");
   bool xauOpenBar=false;
   for(datetime bt=fxOlder+m15;bt<xauNewer;bt+=m15)
     {
      MqlDateTime bd; TimeToStruct(bt,bd);
      SQuoteSessionWindow w[]; ArrayResize(w,0);
      // Gold Sunday/Monday opening is 01:00 in this explicit broker fixture.
      if(bd.day_of_week==5) { ArrayResize(w,1); w[0].startSecond=0; w[0].endSecond=85500; }
      if(bd.day_of_week==1) { ArrayResize(w,1); w[0].startSecond=3600; w[0].endSecond=86400; }
      if(QmeBarOverlapsQuoteWindows(bt,m15,bd.day_of_week,w,ArraySize(w))) xauOpenBar=true;
     }
   g_kit.Check(!xauOpenBar,"reported gold gap is closed until its configured Monday 01:00 quote open");
   SQuoteSessionWindow weekday[]; ArrayResize(weekday,1);
   weekday[0].startSecond=0; weekday[0].endSecond=86400;
   const datetime weekdayMissing=StringToTime("2026.11.10 10:15");
   g_kit.Check(QmeBarOverlapsQuoteWindows(weekdayMissing,m15,2,weekday,1),
               "missing M15 interval during open quote session is detected");
   const datetime goodFridayMissing=StringToTime("2026.04.03 00:00");
   g_kit.Check(QmeBarOverlapsQuoteWindows(goodFridayMissing,86400,5,weekday,1),
               "weekly Friday schedule considers exact Good Friday D1 interval open; do not whitelist without holiday evidence");
   g_kit.Check(QmeGapWithinQualityWindow(PERIOD_D1,60),
               "recent D1 gap remains subject to strict quote-session validation");
   g_kit.Check(!QmeGapWithinQualityWindow(PERIOD_D1,61),
               "historical D1 gap outside recent validation window cannot permanently block current data");
   g_kit.Check(QmeGapWithinQualityWindow(PERIOD_M15,400),
               "intraday gap validation remains strict across loaded history");
   SQuoteSessionWindow unavailable[]; ArrayResize(unavailable,0);
   g_kit.Check(!QmeBarOverlapsQuoteWindows(weekdayMissing,m15,2,unavailable,0),
               "empty session data cannot certify a bar as scheduled or safe");

   // Failed refreshes must never retain a previous valid snapshot/analysis.
   CSymbolRuntime invalidation;
   invalidation.symbol = "test";
   invalidation.snapshot.dataValid = true;
   invalidation.tfReady[4] = true;
   invalidation.analysis[4].valid = true;
   invalidation.InvalidateAnalysis();
   g_kit.Check(!invalidation.snapshot.dataValid && !invalidation.tfReady[4] &&
               !invalidation.analysis[4].valid, "invalidation clears stale snapshot and analysis");

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
   g_kit.Check(rt.snapshot.time > 0, "snapshot carries a scan timestamp");
   CTickProcessor *runtimeTicks = data.Ticks(rt.symbol);
   SCanonicalQuote runtimeQuote;
   QmeCanonicalQuoteClear(runtimeQuote);
   const bool runtimeQuoteValid = (runtimeTicks != NULL &&
                                   runtimeTicks.CanonicalQuote(runtimeQuote, TimeTradeServer(), 300));
   if(runtimeQuoteValid)
      g_kit.Check(rt.snapshot.symbol == runtimeQuote.symbol &&
                  rt.snapshot.bid == runtimeQuote.bid && rt.snapshot.ask == runtimeQuote.ask &&
                  rt.snapshot.spreadPoints == runtimeQuote.spreadPoints &&
                  rt.snapshot.tickTime == runtimeQuote.time &&
                  rt.snapshot.tickTimeMsc == runtimeQuote.timeMsc,
                  "snapshot bid, ask, spread and tick timestamp match one canonical tick");
   else
      g_kit.Check(!rt.snapshot.dataValid && rt.snapshot.bid == 0.0 && rt.snapshot.ask == 0.0 &&
                  rt.snapshot.spreadPoints == 0.0 && rt.snapshot.tickTime == 0,
                  "missing or stale tick cannot leave quote values in a valid snapshot");

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
