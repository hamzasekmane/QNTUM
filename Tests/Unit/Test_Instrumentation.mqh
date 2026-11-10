//+------------------------------------------------------------------+
//|                                    Tests/Unit/Test_Instrumentation |
//|  Core/Funnel, Core/Profiler, Core/EventBus, Core/EventDispatcher,     |
//|  Core/EventLedger. These observe the engine; none may change it.       |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_INSTRUMENTATION_MQH__
#define __QME_TEST_INSTRUMENTATION_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

//--- a sink that only counts, so the dispatcher can be checked in isolation
class CTestSink : public IQmeEventSink
  {
public:
   int               count;
   ENUM_QME_EVENT    lastType;
   string            lastText;
                     CTestSink(void) { count = 0; lastType = QME_EVT_NONE; lastText = ""; }
   virtual void      OnQmeEvent(const SQmeEvent &e)
     {
      count++;
      lastType = e.type;
      lastText = e.text;
     }
  };

int RunInstrumentationTests(void)
  {
   g_kit.Begin("Unit/Test_Instrumentation");

   //--- funnel: stages are created once and keep their index
   CFunnel funnel;
   funnel.Reset();
   const int sScan = funnel.Stage("scan");
   const int sSym  = funnel.Stage("symbol");
   g_kit.Check(sScan >= 0 && sSym >= 0, "funnel stages are created");
   g_kit.CheckEqual(funnel.Stage("scan"), sScan, "an existing stage keeps its index");
   g_kit.CheckEqual(funnel.Count(), 2, "two stages exist");

   funnel.Enter(sScan);
   funnel.Pass(sScan, 3);
   g_kit.CheckEqual(funnel.In(sScan), 1, "entered once");
   g_kit.CheckEqual(funnel.Out(sScan), 3, "three passed");

   funnel.Drop(sSym, "no_data", 2);
   funnel.Drop(sSym, "no_data", 1);
   funnel.Drop(sSym, "spread");
   g_kit.CheckEqual(funnel.RejectCategories(), 2, "two distinct drop reasons");
   string reason = "";
   long count = 0;
   g_kit.Check(funnel.RejectAt(0, reason, count) && reason == "no_data" && count == 3,
               "the drop reasons accumulate");
   g_kit.Check(StringLen(funnel.Summary()) > 0, "the summary is not empty");

   //--- out-of-range stages are ignored, never crash
   funnel.Pass(-1);
   funnel.Pass(99);
   funnel.Enter(-5);
   g_kit.CheckEqual(funnel.In(-1), 0, "an invalid index reads as zero");

   //--- profiler: disabled by default, measures when enabled
   CProfiler prof;
   const int pIdx = prof.Section("work");
   prof.Begin(pIdx);
   prof.End(pIdx);
   g_kit.CheckEqual(prof.Calls(pIdx), 0, "a disabled profiler records nothing");
   g_kit.Check(!prof.Enabled(), "the profiler starts disabled");

   prof.Init(true);
   prof.Reset();
   const int pRun = prof.Section("work");
   prof.Begin(pRun);
   prof.End(pRun);
   prof.Begin(pRun);
   prof.End(pRun);
   g_kit.CheckEqual(prof.Calls(pRun), 2, "two calls are counted");
   g_kit.Check(prof.AvgMs(pRun) >= 0.0, "the average is a real number");
   g_kit.Check(StringLen(prof.Report()) > 0, "the report is not empty");
   prof.End(pRun);
   g_kit.CheckEqual(prof.Calls(pRun), 2, "a stray End() does not invent a call");

   //--- bus: FIFO, counted by type, empty when drained
   CEventBus bus;
   bus.Reset();
   g_kit.Check(bus.IsEmpty(), "a new bus is empty");
   bus.Publish(QME_EVT_SCAN_START, "EURUSD", 1, 0.0, "first");
   bus.Publish(QME_EVT_SCAN_END, "EURUSD", 2, 5.0, "second");
   g_kit.CheckEqual(bus.Count(), 2, "two events are queued");
   g_kit.CheckEqual(bus.Published(QME_EVT_SCAN_START), 1, "one scan-start was published");

   SQmeEvent ev;
   g_kit.Check(bus.Pop(ev) && ev.type == QME_EVT_SCAN_START && ev.text == "first",
               "the bus is first in, first out");
   g_kit.Check(bus.Pop(ev) && ev.type == QME_EVT_SCAN_END, "the second event follows");
   g_kit.Check(!bus.Pop(ev), "an empty bus refuses to pop");

   //--- dispatcher: fan-out to a registered sink
   CTestSink sink;
   CEventDispatcher dispatch;
   g_kit.Check(dispatch.AddSink(GetPointer(sink), "test"), "a sink registers");
   g_kit.Check(!dispatch.AddSink(GetPointer(sink), "test"), "a duplicate name is refused");
   g_kit.Check(!dispatch.AddSink(NULL, "null"), "a null sink is refused");
   g_kit.Check(dispatch.SubscribeAll("test"), "the sink subscribes to everything");
   g_kit.CheckEqual(dispatch.SinkCount(), 1, "one sink is registered");

   bus.Publish(QME_EVT_ERROR, "EURUSD", 3, 0.0, "boom", QME_LOG_ERROR);
   bus.Publish(QME_EVT_TIMER, "EURUSD", 4, 0.0, "tick");
   g_kit.CheckEqual(dispatch.Dispatch(bus), 2, "both events were drained");
   g_kit.CheckEqual(sink.count, 2, "the sink received both events");
   g_kit.Check(sink.lastType == QME_EVT_TIMER && sink.lastText == "tick",
               "the sink saw the newest event last");
   g_kit.CheckEqual((int)dispatch.Delivered(), 2, "delivery is counted");
   g_kit.Check(bus.IsEmpty(), "the bus is empty after dispatch");

   //--- a filtered sink receives only what it asked for
   CTestSink picky;
   CEventDispatcher filtered;
   filtered.AddSink(GetPointer(picky), "picky");
   filtered.Subscribe("picky", QME_EVT_SHUTDOWN);
   bus.Publish(QME_EVT_TIMER, "EURUSD", 5, 0.0, "ignored");
   bus.Publish(QME_EVT_SHUTDOWN, "EURUSD", 6, 0.0, "bye");
   g_kit.CheckEqual(filtered.Dispatch(bus), 2, "the dispatcher still drains everything");
   g_kit.CheckEqual(picky.count, 1, "the filtered sink saw only its event");
   g_kit.Check(picky.lastType == QME_EVT_SHUTDOWN, "the filtered sink saw the shutdown");

   //--- ledger as a sink: monotonic ids and readable export
   CEventLedger ledger;
   ledger.Init(16, false);
   CEventDispatcher toLedger;
   g_kit.Check(toLedger.AddSink(GetPointer(ledger), "ledger"), "the ledger registers as a sink");
   toLedger.SubscribeAll("ledger");

   const ulong before = ledger.LastId();
   bus.Publish(QME_EVT_SIGNAL_DETECTED, "EURUSD", 42, 0.0, "signal seen");
   toLedger.Dispatch(bus);
   g_kit.Check(ledger.LastId() > before, "the ledger id advances");
   g_kit.Check(ledger.Count() >= 1, "the ledger holds the event");
   g_kit.Check(StringLen(ledger.Export(5)) > 0, "the ledger can export");

   //--- the ledger keeps recording through its own API too
   const int beforeCount = ledger.Count();
   ledger.Record(QME_EVT_SIGNAL_REJECTED, "EURUSD", 43, "rejected", QME_REJ_LOW_SCORE);
   g_kit.CheckEqual(ledger.Count(), beforeCount + 1, "a direct record is stored");

   return(g_kit.End());
  }

#endif // __QME_TEST_INSTRUMENTATION_MQH__
