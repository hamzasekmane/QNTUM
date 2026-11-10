//+------------------------------------------------------------------+
//|                            Tests/Regression/Test_PreviousSignals  |
//|  The replay audit must catch approvals that break the rules.          |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_PREVIOUS_MQH__
#define __QME_TEST_PREVIOUS_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SReplayFrame Frame(const long cycle, const bool approved, const ENUM_QME_REJECT reason,
                   const double rr, const double score, const double riskPct,
                   const string fp)
  {
   SReplayFrame f;
   QmeReplayFrameClear(f);
   f.cycle = cycle;
   f.time = TimeCurrent();
   f.symbol = "EURUSD";
   f.side = QME_SIDE_BUY;
   f.approved = approved;
   f.reason = reason;
   f.rr = rr;
   f.score = score;
   f.riskPct = riskPct;
   f.fingerprint = fp;
   return(f);
  }

int RunPreviousSignalTests(void)
  {
   g_kit.Begin("Regression/Test_PreviousSignals");

   SInputs in;
   QmeInputsDefaults(in);
   string err = "";
   CConfig cfg;
   cfg.Init(in, err);

   //--- a clean history must audit clean
   CReplayEngine clean;
   clean.Init(64);
   clean.Record(Frame(1, true, QME_REJ_NONE, cfg.In.minRR + 0.5, 75.0, 0.5, "fp-a"));
   clean.Record(Frame(2, false, QME_REJ_SPREAD, 0.0, 70.0, 0.0, "fp-b"));
   clean.Record(Frame(3, false, QME_REJ_LOW_SCORE, 0.0, 20.0, 0.0, "fp-c"));
   SReplayStats ok = clean.Audit(cfg);
   g_kit.CheckEqual(ok.frames, 3, "three frames audited");
   g_kit.CheckEqual(ok.approvals, 1, "one approval counted");
   g_kit.CheckEqual(ok.refusals, 2, "two refusals counted");
   g_kit.CheckEqual(ok.violations, 0, "clean history has no violations");

   //--- an approval with a refusal reason is a violation
   CReplayEngine bad1;
   bad1.Init(64);
   bad1.Record(Frame(1, true, QME_REJ_SPREAD, 2.0, 80.0, 0.5, "fp-x"));
   g_kit.Check(bad1.Audit(cfg).violations >= 1, "approval with a reason is flagged");

   //--- an approval below minRR is a violation
   CReplayEngine bad2;
   bad2.Init(64);
   bad2.Record(Frame(1, true, QME_REJ_NONE, cfg.In.minRR - 0.1, 80.0, 0.5, "fp-y"));
   g_kit.Check(bad2.Audit(cfg).violations >= 1, "approval below minRR is flagged");

   //--- the same fingerprint approved twice is a violation
   CReplayEngine bad3;
   bad3.Init(64);
   bad3.Record(Frame(1, true, QME_REJ_NONE, 2.0, 80.0, 0.5, "fp-z"));
   bad3.Record(Frame(2, true, QME_REJ_NONE, 2.0, 80.0, 0.5, "fp-z"));
   const SReplayStats dup = bad3.Audit(cfg);
   g_kit.Check(dup.duplicateApprovals >= 1, "duplicate approval detected");
   g_kit.Check(dup.violations >= 1, "duplicate approval is a violation");

   //--- a refusal without a reason is a violation
   CReplayEngine bad4;
   bad4.Init(64);
   bad4.Record(Frame(1, false, QME_REJ_NONE, 0.0, 50.0, 0.0, "fp-w"));
   g_kit.Check(bad4.Audit(cfg).violations >= 1, "silent refusal is flagged");

   //--- replay survives a restart
   const string blob = clean.Serialize();
   CReplayEngine restored;
   g_kit.Check(restored.Deserialize(blob), "replay frames restored");
   g_kit.CheckEqual(restored.Count(), 3, "all frames restored");
   g_kit.CheckEqual(restored.Audit(cfg).violations, 0, "restored history still audits clean");

   return(g_kit.End());
  }

#endif // __QME_TEST_PREVIOUS_MQH__
//+------------------------------------------------------------------+
