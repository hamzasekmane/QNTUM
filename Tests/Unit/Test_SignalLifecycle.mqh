//+------------------------------------------------------------------+
//|                             Tests/Unit/Test_SignalLifecycle       |
//|  The state machine is the contract that keeps the engine honest.      |
//|  Illegal transitions must be refused and counted.                   |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_LIFECYCLE_MQH__
#define __QME_TEST_LIFECYCLE_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

STradingSignal LifecycleSignal(void)
  {
   STradingSignal s;
   QmeSignalClear(s);
   s.id = 1001;
   s.symbol = "EURUSD";
   s.side = QME_SIDE_BUY;
   s.tf = PERIOD_M15;
   s.entryType = QME_ENTRY_MARKET;
   s.state = QME_SIG_DETECTED;
   s.created = TimeCurrent();
   s.updated = s.created;
   s.expires = s.created + 3600;
   s.entry = 1.10000;
   s.stopLoss = 1.09900;
   s.takeProfit1 = 1.10200;
   s.rr = 2.0;
   s.score = 70.0;
   s.confidence = 0.6;
   s.fingerprint = "EURUSD|M15|BUY|test";
   return(s);
  }

int RunLifecycleTests(void)
  {
   g_kit.Begin("Unit/Test_SignalLifecycle");

   //--- the legal chain
   g_kit.Check(CSignalLifecycle::Allowed(QME_SIG_DETECTED, QME_SIG_EVALUATING),
               "DETECTED -> EVALUATING allowed");
   g_kit.Check(CSignalLifecycle::Allowed(QME_SIG_EVALUATING, QME_SIG_APPROVED),
               "EVALUATING -> APPROVED allowed");
   g_kit.Check(CSignalLifecycle::Allowed(QME_SIG_APPROVED, QME_SIG_EXECUTION_PENDING),
               "APPROVED -> EXECUTION_PENDING allowed");
   g_kit.Check(CSignalLifecycle::Allowed(QME_SIG_EXECUTION_PENDING, QME_SIG_EXECUTED),
               "EXECUTION_PENDING -> EXECUTED allowed");
   g_kit.Check(CSignalLifecycle::Allowed(QME_SIG_EXECUTED, QME_SIG_MONITORING),
               "EXECUTED -> MONITORING allowed");
   g_kit.Check(CSignalLifecycle::Allowed(QME_SIG_MONITORING, QME_SIG_CLOSED),
               "MONITORING -> CLOSED allowed");

   //--- the illegal ones
   g_kit.Check(!CSignalLifecycle::Allowed(QME_SIG_DETECTED, QME_SIG_EXECUTED),
               "DETECTED -> EXECUTED refused");
   g_kit.Check(!CSignalLifecycle::Allowed(QME_SIG_CLOSED, QME_SIG_APPROVED),
               "terminal CLOSED cannot be resurrected");
   g_kit.Check(!CSignalLifecycle::Allowed(QME_SIG_REJECTED, QME_SIG_EXECUTED),
               "terminal REJECTED cannot execute");
   g_kit.Check(!CSignalLifecycle::Allowed(QME_SIG_APPROVED, QME_SIG_DETECTED),
               "no backwards transition");

   //--- terminal classification
   g_kit.Check(CSignalTypes::IsTerminal(QME_SIG_CLOSED), "CLOSED is terminal");
   g_kit.Check(CSignalTypes::IsTerminal(QME_SIG_EXPIRED), "EXPIRED is terminal");
   g_kit.Check(!CSignalTypes::IsTerminal(QME_SIG_MONITORING), "MONITORING is live");
   g_kit.Check(CSignalTypes::IsLive(QME_SIG_APPROVED), "APPROVED is live");
   STradingSignal pending;
   QmeSignalClear(pending);
   pending.state = QME_SIG_EXECUTION_PENDING;
   pending.expires = 100;
   g_kit.Check(CSignalExpiry::Check(pending, 200, 0.0, false) == QME_REJ_NONE,
               "unresolved submitted signal cannot expire before reconciliation");

   //--- the mutator refuses what the table refuses
   CSignalLifecycle lc;
   STradingSignal s = LifecycleSignal();
   g_kit.Check(!lc.Transition(s, QME_SIG_EXECUTED, QME_REJ_NONE, "illegal", TimeCurrent()),
               "transition() refuses DETECTED -> EXECUTED");
   g_kit.CheckEqual((long)s.state, (long)QME_SIG_DETECTED, "state unchanged after refusal");
   g_kit.Check(lc.Refused() >= 1, "refusal is counted");

   // A terminal rejection may be reevaluated within the same setup bar, but
   // any live or unresolved fingerprint remains reserved against duplicates.
   CSignalRegistry reg;
   STradingSignal prior = LifecycleSignal();
   ENUM_QME_REJECT addReason = QME_REJ_NONE;
   string addWhy = "";
   g_kit.Check(reg.Add(prior, addReason, addWhy), "first fingerprint record added");
   g_kit.Check(reg.HasLiveFingerprint(prior.fingerprint), "live signal reserves its fingerprint");
   CSignalLifecycle reevaluate;
   reevaluate.Transition(prior, QME_SIG_EVALUATING, QME_REJ_NONE, "test", TimeCurrent());
   reevaluate.Transition(prior, QME_SIG_REJECTED, QME_REJ_LOW_SCORE, "temporary rejection", TimeCurrent());
   reg.Update(prior);
   g_kit.Check(!reg.HasLiveFingerprint(prior.fingerprint), "rejected signal releases fingerprint for reevaluation");
   STradingSignal retry = LifecycleSignal();
   retry.id = 1002;
   g_kit.Check(reg.Add(retry, addReason, addWhy), "same setup fingerprint can be reevaluated after rejection");
   STradingSignal duplicate = LifecycleSignal();
   duplicate.id = 1003;
   g_kit.Check(!reg.Add(duplicate, addReason, addWhy), "live fingerprint still blocks duplicate signal");

   g_kit.Check(lc.Transition(s, QME_SIG_EVALUATING, QME_REJ_NONE, "ok", TimeCurrent()),
               "transition() accepts DETECTED -> EVALUATING");
   g_kit.CheckEqual((long)s.state, (long)QME_SIG_EVALUATING, "state updated");

   return(g_kit.End());
  }

#endif // __QME_TEST_LIFECYCLE_MQH__
//+------------------------------------------------------------------+
