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

   return(g_kit.End());
  }

#endif // __QME_TEST_POSREC_MQH__
//+------------------------------------------------------------------+
