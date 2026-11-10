//+------------------------------------------------------------------+
//|                                         Tests/Unit/Test_Expiry     |
//|  Strategy/SignalExpiry: when a pending idea stops being executable.   |
//|  Pure data: no terminal, no market, no broker.                        |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_EXPIRY_MQH__
#define __QME_TEST_EXPIRY_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

void QmeTestSignal(STradingSignal &s, const ENUM_QME_SIDE side, const datetime now)
  {
   QmeSignalClear(s);
   s.id = 1001;
   s.symbol = "EURUSD";
   s.side = side;
   s.tf = PERIOD_H1;
   s.state = QME_SIG_APPROVED;
   s.created = now - 600;
   s.updated = now - 600;
   s.expires = now + 3600;
   s.entry = 1.10000;
   s.stopLoss = (side == QME_SIDE_BUY) ? 1.09500 : 1.10500;
   s.takeProfit1 = (side == QME_SIDE_BUY) ? 1.11000 : 1.09000;
   s.fingerprint = "fp-expiry";
  }

int RunExpiryTests(void)
  {
   g_kit.Begin("Unit/Test_Expiry");
   const datetime now = D'2024.03.05 12:00';

   //--- a healthy, live idea is not expired
   STradingSignal healthy;
   QmeTestSignal(healthy, QME_SIDE_BUY, now);
   g_kit.Check(CSignalExpiry::Check(healthy, now, 1.10100, true) == QME_REJ_NONE,
               "a live idea with an active zone is still executable");

   //--- time is the first reason to give up
   STradingSignal late;
   QmeTestSignal(late, QME_SIDE_BUY, now);
   late.expires = now - 1;
   g_kit.Check(CSignalExpiry::Check(late, now, 1.10100, true) == QME_REJ_EXPIRED,
               "a signal past its expiry is EXPIRED");
   g_kit.Check(CSignalExpiry::Check(late, now, 1.10100, false) == QME_REJ_EXPIRED,
               "expiry wins over a dead zone");

   //--- an idea with no live zone behind it is dead even before expiry
   STradingSignal orphan;
   QmeTestSignal(orphan, QME_SIDE_BUY, now);
   g_kit.Check(CSignalExpiry::Check(orphan, now, 1.10100, false) == QME_REJ_INVALIDATED,
               "a signal whose zone died is INVALIDATED");

   //--- price already through the stop: the trade cannot be entered well
   STradingSignal early;
   QmeTestSignal(early, QME_SIDE_BUY, now);
   g_kit.Check(CSignalExpiry::Check(early, now, 1.09500, true) == QME_REJ_INVALIDATED,
               "a long whose price reached its stop is invalidated");

   STradingSignal shortEarly;
   QmeTestSignal(shortEarly, QME_SIDE_SELL, now);
   g_kit.Check(CSignalExpiry::Check(shortEarly, now, 1.10500, true) == QME_REJ_INVALIDATED,
               "a short whose price reached its stop is invalidated");

   STradingSignal shortFine;
   QmeTestSignal(shortFine, QME_SIDE_SELL, now);
   g_kit.Check(CSignalExpiry::Check(shortFine, now, 1.10400, true) == QME_REJ_NONE,
               "a short above its stop is still executable");

   //--- zero price means "unknown": no price-based veto
   STradingSignal noPrice;
   QmeTestSignal(noPrice, QME_SIDE_BUY, now);
   noPrice.stopLoss = 1.09500;
   g_kit.Check(CSignalExpiry::Check(noPrice, now, 0.0, true) == QME_REJ_NONE,
               "without a price the price check is skipped");

   //--- terminal signals never expire
   STradingSignal executed;
   QmeTestSignal(executed, QME_SIDE_BUY, now);
   executed.state = QME_SIG_EXECUTED;
   executed.expires = now - 1;
   g_kit.Check(CSignalExpiry::Check(executed, now, 1.09000, false) == QME_REJ_NONE,
               "an executed signal is never expired");

   //--- Process: only pre-execution states are touched
   CSignalRegistry registry;
   CSignalLifecycle lifecycle;
   CZoneEngine zones;
   zones.Init("EURUSD", 72, 25.0);

   STradingSignal expired;
   QmeTestSignal(expired, QME_SIDE_BUY, now);
   expired.id = 1;
   expired.expires = now - 60;
   expired.fingerprint = "fp-1";
   STradingSignal live;
   QmeTestSignal(live, QME_SIDE_BUY, now);
   live.id = 2;
   live.fingerprint = "fp-2";
   STradingSignal done;
   QmeTestSignal(done, QME_SIDE_BUY, now);
   done.id = 3;
   done.state = QME_SIG_EXECUTED;
   done.expires = now - 60;
   done.fingerprint = "fp-3";

   ENUM_QME_REJECT why = QME_REJ_NONE;
   string note = "";
   g_kit.Check(registry.Add(expired, why, note), "expired signal registers");
   g_kit.Check(registry.Add(live, why, note), "live signal registers");
   g_kit.Check(registry.Add(done, why, note), "executed signal registers");
   g_kit.CheckEqual(registry.Count(), 3, "three signals in the registry");

   const int changed = CSignalExpiry::Process(registry, lifecycle, zones, now, 1.10100);
   g_kit.CheckEqual(changed, 2, "only the two pending signals were expired");

   STradingSignal after;
   g_kit.Check(registry.Get(1, after) && after.state == QME_SIG_EXPIRED,
               "the expired pending signal became EXPIRED");
   g_kit.Check(registry.Get(2, after) && after.state == QME_SIG_INVALIDATED,
               "the pending signal without a zone became INVALIDATED");
   g_kit.Check(registry.Get(3, after) && after.state == QME_SIG_EXECUTED,
               "the executed signal was left alone");

   //--- a second pass finds nothing new to do
   g_kit.CheckEqual(CSignalExpiry::Process(registry, lifecycle, zones, now, 1.10100), 0,
                    "expiry is idempotent");

   return(g_kit.End());
  }

#endif // __QME_TEST_EXPIRY_MQH__
