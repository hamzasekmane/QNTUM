//+------------------------------------------------------------------+
//|                            Tests/Regression/Test_ExecutionFailures |
//|  Broker answers -> policy. A timeout must never be retried blindly.    |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_EXECFAIL_MQH__
#define __QME_TEST_EXECFAIL_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunExecutionFailureTests(void)
  {
   g_kit.Begin("Regression/Test_ExecutionFailures");

   //--- transient answers are safe to retry
   g_kit.Check(CRetryPolicy::ShouldRetry(TRADE_RETCODE_REQUOTE, 1, 2),
               "requote may be retried");
   g_kit.Check(CRetryPolicy::ShouldRetry(TRADE_RETCODE_PRICE_CHANGED, 1, 2),
               "price changed may be retried");
   g_kit.Check(CRetryPolicy::ShouldRetry(TRADE_RETCODE_PRICE_OFF, 1, 2),
               "price off may be retried");

   //--- but the retry budget is finite
   g_kit.Check(!CRetryPolicy::ShouldRetry(TRADE_RETCODE_REQUOTE, 2, 2),
               "retry budget is respected");
   g_kit.Check(!CRetryPolicy::ShouldRetry(TRADE_RETCODE_REQUOTE, 1, 0),
               "zero retries means no retry");

   //--- permanent rejections are never retried
   g_kit.Check(!CRetryPolicy::ShouldRetry(TRADE_RETCODE_INVALID_STOPS, 1, 5),
               "invalid stops are not retried");
   g_kit.Check(!CRetryPolicy::ShouldRetry(TRADE_RETCODE_NO_MONEY, 1, 5),
               "no money is not retried");

   //--- ambiguous answers must be reconciled, not retried
   g_kit.Check(CRetryPolicy::RequiresReconciliation(TRADE_RETCODE_TIMEOUT),
               "timeout requires reconciliation");
   g_kit.Check(CRetryPolicy::RequiresReconciliation(TRADE_RETCODE_CONNECTION),
               "connection loss requires reconciliation");
   g_kit.Check(!CRetryPolicy::RequiresReconciliation(TRADE_RETCODE_DONE),
               "a completed order needs no reconciliation");
   g_kit.Check(!CRetryPolicy::ShouldRetry(TRADE_RETCODE_TIMEOUT, 1, 5),
               "timeout is never auto-retried");

   //--- delays grow but stay bounded
   const int d1 = CRetryPolicy::DelayMs(TRADE_RETCODE_REQUOTE, 1);
   const int d3 = CRetryPolicy::DelayMs(TRADE_RETCODE_REQUOTE, 3);
   g_kit.Check(d3 > d1, "later retries wait longer");
   g_kit.Check(d1 >= 100 && d3 <= 5000, "delays stay in a sane range");

   //--- classification helpers agree with the policy
   g_kit.CheckEqual((long)QmeClassifyRetcode(TRADE_RETCODE_DONE), (long)QME_RETRY_NO,
                    "success is not a retry class");
   g_kit.Check(!QmeRetcodeIsSuccess(TRADE_RETCODE_NO_MONEY),
               "rejection is not success");
   g_kit.Check(QmeRetcodeIsSuccess(TRADE_RETCODE_DONE), "DONE is success");
   g_kit.Check(QmeRetcodeIsSuccess(TRADE_RETCODE_PLACED), "PLACED is success");

   //--- retcodes map to meaningful rejection reasons
   g_kit.Check(QmeRejectFromRetcode(TRADE_RETCODE_INVALID_STOPS) == QME_REJ_SL_INVALID ||
               QmeRejectFromRetcode(TRADE_RETCODE_INVALID_STOPS) == QME_REJ_BROKER_REJECTED,
               "invalid stops map to a stop-related reason");
   g_kit.Check(QmeRejectFromRetcode(TRADE_RETCODE_NO_MONEY) == QME_REJ_MARGIN,
               "no money maps to margin");

   return(g_kit.End());
  }

#endif // __QME_TEST_EXECFAIL_MQH__
//+------------------------------------------------------------------+
