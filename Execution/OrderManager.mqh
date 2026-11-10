//+------------------------------------------------------------------+
//|                                         Execution/OrderManager    |
//|  The only place that calls OrderSend().                              |
//|                                                                   |
//|  Responsibilities:                                                |
//|   * send the request and measure the round trip;                     |
//|   * translate MqlTradeResult into SExecutionResult;                  |
//|   * retry ONLY transient answers, with backoff;                      |
//|   * after an ambiguous answer (timeout/disconnect) mark              |
//|     QME_EXEC_UNKNOWN_STATE and stop: reconciliation decides.          |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_ORDERMANAGER_MQH__
#define __QME_EXECUTION_ORDERMANAGER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Core/Logger.mqh"
#include "RetryPolicy.mqh"
#include "PositionReconciler.mqh"

class COrderManager
  {
private:
   static void       ApplyResult(const MqlTradeResult &r, SExecutionResult &res);

public:
   static bool       Send(MqlTradeRequest &req, const CConfig &cfg, SExecutionResult &res);
  };

//------------------------------------------------------------------//
void COrderManager::ApplyResult(const MqlTradeResult &r, SExecutionResult &res)
  {
   res.retcode = r.retcode;
   res.orderTicket = r.order;
   res.dealTicket = r.deal;
   res.filledVolume = r.volume;
   res.filledPrice = r.price;
   res.comment = r.comment;
  }

//------------------------------------------------------------------//
bool COrderManager::Send(MqlTradeRequest &req, const CConfig &cfg, SExecutionResult &res)
  {
   res.attempts = 0;
   const int maxRetries = MathMax(cfg.In.maxRetries, 0);

   while(true)
     {
      res.attempts++;

      MqlTradeResult tr;
      ZeroMemory(tr);

      const ulong t0 = GetMicrosecondCount();
      const bool sent = OrderSend(req, tr);
      const double latencyMs = (double)(GetMicrosecondCount() - t0) / 1000.0;

      res.sent = true;
      res.lastError = GetLastError();
      ApplyResult(tr, res);

      if(!sent && tr.retcode == 0)
        {
         //--- the terminal refused locally: no server answer
         res.confirmed = false;
         res.state = QME_EXEC_FAILED;
         res.reject = QmeRejectFromRetcode((uint)res.lastError);
         res.comment = "OrderSend failed locally: " + QmeLastErrorText();
         QmeLogMsg(QME_LOG_ERROR, "Order", res.comment);
         return(false);
        }

      if(QmeRetcodeIsSuccess(tr.retcode))
        {
         res.confirmed = true;
         res.state = QME_EXEC_CONFIRMED;
         res.reject = QME_REJ_NONE;
         res.time = TimeCurrent();
         res.filledPrice = (tr.price > 0.0) ? tr.price : req.price;

         //--- resolve the resulting position when the broker reports one
         if(tr.order > 0 && req.action == TRADE_ACTION_DEAL)
           {
            ulong tk = 0;
            double vol = 0.0, open = 0.0, sl = 0.0, tp = 0.0;
            if(CPositionReconciler::FindPosition(req.symbol, req.magic, tk, vol, open, sl, tp))
              {
               res.positionTicket = tk;
               if(open > 0.0) res.filledPrice = open;
               if(vol > 0.0) res.filledVolume = vol;
               if(sl <= 0.0)
                 {
                  //--- a filled position without a stop is a critical failure
                  QmeLogMsg(QME_LOG_ERROR, "Order", "confirmed position " +
                            IntegerToString((long)tk) + " has no stop loss");
                 }
              }
           }

         QmeLogMsg(QME_LOG_INFO, "Order", req.symbol + " filled/placed, retcode " +
                   IntegerToString((int)tr.retcode) + " latency " +
                   QmeFmt(latencyMs, 0) + "ms");
         return(true);
        }

      //--- failed at the server
      res.reject = QmeRejectFromRetcode(tr.retcode);

      if(CRetryPolicy::RequiresReconciliation(tr.retcode))
        {
         res.state = QME_EXEC_UNKNOWN_STATE;
         res.confirmed = false;
         res.time = TimeCurrent();
         res.comment = QmeRetcodeText(tr.retcode) + " - outcome unknown, reconcile before retrying";
         QmeLogMsg(QME_LOG_ERROR, "Order", res.comment);
         return(false);
        }

      if(CRetryPolicy::ShouldRetry(tr.retcode, res.attempts, maxRetries))
        {
         const int delay = CRetryPolicy::DelayMs(tr.retcode, res.attempts, cfg.In.retryDelayMs);
         QmeLogMsg(QME_LOG_WARN, "Order", req.symbol + " retcode " +
                   IntegerToString((int)tr.retcode) + " retrying in " +
                   IntegerToString(delay) + "ms");
         Sleep(delay);
         continue;
        }

      res.state = QME_EXEC_FAILED;
      res.confirmed = false;
      res.time = TimeCurrent();
      if(StringLen(res.comment) == 0)
         res.comment = QmeRetcodeText(tr.retcode);
      QmeLogMsg(QME_LOG_WARN, "Order", req.symbol + " rejected: " + res.comment);
      return(false);
     }
  }

#endif // __QME_EXECUTION_ORDERMANAGER_MQH__
//+------------------------------------------------------------------+
