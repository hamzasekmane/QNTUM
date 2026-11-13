//+------------------------------------------------------------------+
//|                            Tests/Integration/Test_PositionRecovery |
//|  Position tracking and recovery after a restart.                      |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_POSREC_MQH__
#define __QME_TEST_POSREC_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

STrackedPosition FakePosition(const ulong ticket, const ENUM_QME_SIDE side)
  {
   STrackedPosition p;
   p.ticket = ticket;
   p.symbol = "EURUSD";
   p.side = side;
   p.volume = 0.10;
   p.entry = 1.10000;
   p.sl = (side == QME_SIDE_BUY) ? 1.09900 : 1.10100;
   p.tp = (side == QME_SIDE_BUY) ? 1.10200 : 1.09800;
   p.signalId = 42;
   p.opened = TimeCurrent() - 600;
   p.closed = false;
   return(p);
  }

int RunPositionRecoveryTests(void)
  {
   g_kit.Begin("Integration/Test_PositionRecovery");

   CPositionStateStore store;
   g_kit.Check(store.Track(FakePosition(101, QME_SIDE_BUY)), "position tracked");
   g_kit.Check(store.Track(FakePosition(102, QME_SIDE_SELL)), "second position tracked");
   g_kit.CheckEqual(store.Count(), 2, "two positions stored");
   g_kit.CheckEqual(store.OpenCount(), 2, "two positions open");

   g_kit.Check(!store.Track(FakePosition(0, QME_SIDE_BUY)), "ticket 0 is refused");

   STrackedPosition got;
   g_kit.Check(store.Find(101, got), "position 101 found");
   g_kit.CheckEqual((long)got.signalId, 42, "signal id preserved");

   // Blocking NEW entries due to analysis mode must not clear existing state.
   SInputs blockedIn;
   QmeInputsDefaults(blockedIn);
   CConfig blockedCfg;
   string blockedErr = "";
   SAccountContext blockedAcc;
   QmeAccountClear(blockedAcc);
   blockedAcc.mode=QME_ACC_DEMO; blockedAcc.valid=true; blockedAcc.connected=true;
   blockedAcc.equity=10000.0; blockedAcc.balance=10000.0; blockedAcc.freeMargin=10000.0;
   if(blockedCfg.Init(blockedIn,blockedErr))
     {
      CRuntimeController blockedCtl;
      blockedCtl.Init(blockedCfg,blockedAcc);
      string blockedWhy="";
      g_kit.Check(!blockedCtl.MayTrade(blockedCfg,blockedAcc,true,blockedWhy),"analysis mode blocks new entries");
      g_kit.Check(store.Find(101,got) && !got.closed,"existing tracked position remains available while new entries are blocked");
     }
   else g_kit.Check(false,"analysis-mode controller config: "+blockedErr);

   //--- serialise / restore
   const string blob = store.Serialize();
   CPositionStateStore restored;
   g_kit.Check(restored.Deserialize(blob), "positions deserialised");
   g_kit.CheckEqual(restored.Count(), 2, "both positions restored");
   STrackedPosition r1;
   g_kit.Check(restored.Find(101, r1), "restored position found by ticket");
   g_kit.CheckClose(r1.sl, 1.09900, 1e-8, "stop preserved exactly");

   //--- the broker is authoritative: fake tickets must be dropped
   if((bool)TerminalInfoInteger(TERMINAL_CONNECTED) || (bool)MQLInfoInteger(MQL_TESTER))
     {
      const int stale = restored.ReconcileWithBroker(999001);
      g_kit.CheckEqual(stale, 2, "positions absent from the broker are marked closed");
      g_kit.CheckEqual(restored.OpenCount(), 0, "no position remains open");
     }
   else
     {
      g_kit.CheckEqual(restored.ReconcileWithBroker(999001), 0, "disconnection does not mark positions closed");
      g_kit.CheckEqual(restored.OpenCount(), 2, "disconnected positions retained");
     }

   // Closed records may be recycled, but open records must never be evicted.
   CPositionStateStore full;
   bool filled = true;
   for(int i = 0; i < QME_MAX_TRACKED_POSITIONS; i++)
      if(!full.Track(FakePosition((ulong)(10000 + i), QME_SIDE_BUY))) filled = false;
   g_kit.Check(filled, "position store fills to capacity");
   g_kit.Check(!full.Track(FakePosition(20000, QME_SIDE_BUY)), "full open store refuses another record");
   g_kit.Check(full.Close(10000), "closed slot marked");
   g_kit.Check(full.Track(FakePosition(20000, QME_SIDE_SELL)), "closed slot recycled");
   g_kit.Check(full.Find(10001, got) && !got.closed, "open record preserved on reuse");
   g_kit.Check(full.Find(20000, got) && !got.closed, "replacement position tracked");

   //--- an empty blob is not silently accepted
   CPositionStateStore empty;
   g_kit.Check(!empty.Deserialize(""), "empty blob refused");

   // Recovery must validate late sections before mutating any live state.
   SAccountContext savedAccount;
   QmeAccountClear(savedAccount);
   savedAccount.equity=20000.0; savedAccount.balance=20000.0;
   CAccountState savedState;
   savedState.Init(savedAccount);
   CPositionStateStore savedPositions;
   CSignalHistoryStore savedHistory;
   CSignalDeduplicator savedDedup;
   CIdempotencyGuard savedIdem;
   CRuntimeMemory savedMemory;
   const string validState=CStateRecovery::Compose(savedState,savedPositions,savedHistory,
                                                   savedDedup,savedIdem,savedMemory);

   SAccountContext liveAccount;
   QmeAccountClear(liveAccount);
   liveAccount.equity=10000.0; liveAccount.balance=10000.0;
   CAccountState liveState;
   liveState.Init(liveAccount);
   CPositionStateStore livePositions;
   CSignalHistoryStore liveHistory;
   CSignalDeduplicator liveDedup;
   CIdempotencyGuard liveIdem;
   CRuntimeMemory liveMemory;
   SRecoveryReport goodRecovery=CStateRecovery::Apply(validState,liveState,livePositions,
                                                       liveHistory,liveDedup,liveIdem,
                                                       liveMemory,999001);
   g_kit.Check(goodRecovery.loaded,"complete valid recovery applies successfully");
   g_kit.CheckClose(liveState.DayStartEquity(),20000.0,1e-8,"valid recovery restores account baseline");

   CAccountState unchangedState;
   unchangedState.Init(liveAccount);
   CPositionStateStore unchangedPositions;
   g_kit.Check(unchangedPositions.Track(FakePosition(303,QME_SIDE_BUY)),"preexisting recovery target position seeded");
   CSignalHistoryStore unchangedHistory;
   CSignalDeduplicator unchangedDedup;
   CIdempotencyGuard unchangedIdem;
   CRuntimeMemory unchangedMemory;
   string corruptState=validState;
   StringReplace(corruptState,"[IDEM]\n","[IDEM]\nidem;broken\n");
   SRecoveryReport badRecovery=CStateRecovery::Apply(corruptState,unchangedState,
                                                      unchangedPositions,unchangedHistory,
                                                      unchangedDedup,unchangedIdem,
                                                      unchangedMemory,999001);
   g_kit.Check(!badRecovery.loaded,"malformed late intent section blocks recovery");
   g_kit.CheckClose(unchangedState.DayStartEquity(),10000.0,1e-8,"late failure leaves account baseline unchanged");
   g_kit.CheckEqual(unchangedPositions.Count(),1,"late failure leaves tracked positions unchanged");

   return(g_kit.End());
  }

#endif // __QME_TEST_POSREC_MQH__
//+------------------------------------------------------------------+
