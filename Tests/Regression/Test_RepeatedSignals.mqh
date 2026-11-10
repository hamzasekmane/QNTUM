//+------------------------------------------------------------------+
//|                             Tests/Regression/Test_RepeatedSignals  |
//|  A fingerprint may not re-fire inside the cooldown, and must not      |
//|  re-fire after a restart either.                                   |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_REPEATED_MQH__
#define __QME_TEST_REPEATED_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunRepeatedSignalTests(void)
  {
   g_kit.Begin("Regression/Test_RepeatedSignals");

   SInputs in;
   QmeInputsDefaults(in);
   string err = "";
   CConfig cfg;
   cfg.Init(in, err);

   CSignalDeduplicator dedup;
   const datetime now = TimeCurrent();
   const string fp = "EURUSD|M15|BUY|zone7|bar123";

   g_kit.Check(!dedup.IsDuplicate(fp, 900, now), "unknown fingerprint is not a duplicate");
   g_kit.Check(dedup.Register(fp, 1, now), "first signal registered");
   g_kit.Check(dedup.IsDuplicate(fp, 900, now + 60), "same fingerprint blocked inside the cooldown");

   const string other = "EURUSD|M15|SELL|zone8|bar123";
   g_kit.Check(!dedup.IsDuplicate(other, 900, now + 61), "a different fingerprint is independent");

   g_kit.Check(!dedup.IsDuplicate(fp, 900, now + 901), "fingerprint may fire after the cooldown");

   //--- restart: the cooldown must survive
   const string blob = dedup.Serialize();
   CSignalDeduplicator restored;
   g_kit.Check(restored.Deserialize(blob), "deduplicator state restored");
   g_kit.Check(restored.Count() >= 2, "both fingerprints restored");
   g_kit.Check(restored.IsDuplicate(fp, 900, now + 1000),
               "a restored fingerprint is still blocked inside its window");

   //--- empty fingerprints are never registered
   g_kit.Check(!dedup.Register("", 6, now), "empty fingerprint refused");

   return(g_kit.End());
  }

#endif // __QME_TEST_REPEATED_MQH__
//+------------------------------------------------------------------+
