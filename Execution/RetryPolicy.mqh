//+------------------------------------------------------------------+
//!                                        Execution/RetryPolicy     |
//|  Decides whether a failed order may be retried.                     |
//|                                                                   |
//|  SAFETY FIRST:                                                     |
//|   * only a small set of TRANSIENT broker answers may be retried;      |
//|   * TIMEOUT / CONNECTION / generic ERROR are NEVER retried blindly      |
//|     because the order may have reached the server — the gateway must    |
//|     reconcile the position first;                                      |
//|   * retries are capped and delayed.                                     |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_RETRYPOLICY_MQH__
#define __QME_EXECUTION_RETRYPOLICY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"

class CRetryPolicy
  {
public:
   static bool       ShouldRetry(const uint retcode, const int attempt, const int maxRetries);
   static bool       RequiresReconciliation(const uint retcode);
   static int        DelayMs(const uint retcode, const int attempt, const int baseMs = 250);
  };

//------------------------------------------------------------------//
bool CRetryPolicy::ShouldRetry(const uint retcode, const int attempt, const int maxRetries)
  {
   if(maxRetries <= 0) return(false);
   if(attempt >= maxRetries) return(false);
   const ENUM_QME_RETRY_CLASS c = QmeClassifyRetcode(retcode);
   return(c == QME_RETRY_TRANSIENT);
  }

//------------------------------------------------------------------//
bool CRetryPolicy::RequiresReconciliation(const uint retcode)
  {
   if(QmeRetcodeIsSuccess(retcode)) return(false);
   return(QmeClassifyRetcode(retcode) == QME_RETRY_NEVER_IDEMPOTENT);
  }

//------------------------------------------------------------------//
int CRetryPolicy::DelayMs(const uint retcode, const int attempt, const int baseMs)
  {
   int base = (baseMs > 0) ? baseMs : 250;
   const ENUM_QME_RETRY_CLASS c = QmeClassifyRetcode(retcode);
   if(c == QME_RETRY_TRANSIENT && retcode == TRADE_RETCODE_TOO_MANY_REQUESTS)
      base = (base > 1000) ? base : 1000;
   const int mult = (attempt <= 1) ? 1 : (attempt == 2 ? 2 : 3);
   return(base * mult);
  }

#endif // __QME_EXECUTION_RETRYPOLICY_MQH__
//+------------------------------------------------------------------+
