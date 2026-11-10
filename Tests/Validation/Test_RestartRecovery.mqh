//+------------------------------------------------------------------+
//|                           Tests/Validation/Test_RestartRecovery   |
//|  Full checkpoint round trip: compose -> store -> restore.             |
//|  A corrupted or foreign document must be ignored, never half-applied.  |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_RESTART_MQH__
#define __QME_TEST_RESTART_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunRestartRecoveryTests(void)
  {
   g_kit.Begin("Validation/Test_RestartRecovery");

   //--- source state
   CAccountState state;
   SAccountContext acc;
   QmeAccountClear(acc);
   acc.mode = QME_ACC_DEMO;
   acc.login = 4242;
   acc.equity = 10000.0;
   acc.balance = 10000.0;
   acc.valid = true;
   state.Reset();
   state.Init(acc);

   CPositionStateStore positions;
   STrackedPosition p;
   p.ticket = 9001;
   p.symbol = "EURUSD";
   p.side = QME_SIDE_BUY;
   p.volume = 0.20;
   p.entry = 1.10000;
   p.sl = 1.09800;
   p.tp = 1.10400;
   p.signalId = 11;
   p.opened = TimeCurrent() - 1200;
   p.closed = false;
   positions.Track(p);

   CSignalHistoryStore history;
   SSignalRecord rec;
   rec.id = 11;
   rec.symbol = "EURUSD";
   rec.side = QME_SIDE_BUY;
   rec.finalState = QME_SIG_EXECUTED;
   rec.reason = QME_REJ_NONE;
   rec.score = 72.0;
   rec.rr = 2.0;
   rec.opened = TimeCurrent() - 1200;
   rec.closed = 0;
   rec.fingerprint = "fp-recovery";
   history.Add(rec);

   CSignalDeduplicator dedup;
   dedup.Register("fp-recovery", 11, TimeCurrent());

   CIdempotencyGuard idem;
   idem.Begin("fp-recovery", TimeCurrent());
   idem.Complete("fp-recovery", true, TimeCurrent());

   CRuntimeMemory memory;
   memory.Set("cycles", 123);
   memory.Inc("recoveries");

   //--- compose
   const string blob = CStateRecovery::Compose(state, positions, history, dedup, idem, memory);
   g_kit.Check(StringLen(blob) > 0, "state document composed");
   g_kit.Check(StringFind(blob, "QME|STATE|") == 0, "document starts with a version header");
   g_kit.Check(StringFind(blob, "[ACCT]") > 0, "account section present");
   g_kit.Check(StringFind(blob, "[POS]") > 0, "positions section present");
   g_kit.Check(StringFind(blob, "[SIG]") > 0, "signals section present");

   //--- restore into fresh objects
   CAccountState state2;
   state2.Reset();
   CPositionStateStore positions2;
   CSignalHistoryStore history2;
   CSignalDeduplicator dedup2;
   CIdempotencyGuard idem2;
   CRuntimeMemory memory2;

   SRecoveryReport rep = CStateRecovery::Apply(blob, state2, positions2, history2,
                                               dedup2, idem2, memory2, 999);
   g_kit.Check(rep.loaded, "document loaded");
   g_kit.Check(rep.versionOk, "version accepted");
   g_kit.Check(rep.accountRestored, "account state restored");
   g_kit.CheckEqual(rep.positionsStale, 1, "phantom position detected against the broker");
   g_kit.CheckEqual(history2.Count(), 1, "signal history restored");
   g_kit.CheckEqual(dedup2.Count(), 1, "fingerprint restored");
   g_kit.Check(!dedup2.IsDuplicate("fp-recovery", 900, TimeCurrent()),
               "restored fingerprint respects its cooldown window");
   g_kit.CheckEqual((long)memory2.Get("cycles"), 123, "runtime counter restored");
   g_kit.CheckClose(memory2.Get("recoveries"), 1.0, 1e-9, "incremented counter restored");
   string idemWhy = "";
   g_kit.Check(!idem2.CanExecute("fp-recovery", idemWhy), "executed intent stays blocked");

   //--- a foreign document is ignored entirely
   CAccountState state3;
   state3.Reset();
   CPositionStateStore positions3;
   CSignalHistoryStore history3;
   CSignalDeduplicator dedup3;
   CIdempotencyGuard idem3;
   CRuntimeMemory memory3;
   const SRecoveryReport foreign = CStateRecovery::Apply("NOT|A|QME|FILE", state3, positions3,
                                                         history3, dedup3, idem3, memory3, 999);
   g_kit.Check(!foreign.loaded, "foreign document ignored");
   g_kit.CheckEqual(positions3.Count(), 0, "nothing applied from a foreign document");

   //--- a bad version is ignored, not migrated silently
   const string badVersion = "QME|STATE|999|" + IntegerToString((long)TimeCurrent()) + "\n[ACCT]\nstate;1\n";
   const SRecoveryReport versioned = CStateRecovery::Apply(badVersion, state3, positions3,
                                                           history3, dedup3, idem3, memory3, 999);
   g_kit.Check(!versioned.loaded, "unknown state version ignored");
   g_kit.Check(!versioned.versionOk, "version mismatch reported");

   return(g_kit.End());
  }

#endif // __QME_TEST_RESTART_MQH__
//+------------------------------------------------------------------+
