//+------------------------------------------------------------------+
//|                                         Execution/OrderManager    |
//|  The only place that submits NEW entry orders with OrderSend().       |
//|  Position protection/close requests are handled by TradeManager.      |
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
   static bool       IsUnresolvedAcceptance(const uint retcode)
                     { return(retcode == TRADE_RETCODE_PLACED || retcode == TRADE_RETCODE_DONE_PARTIAL); }
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

      ResetLastError();
      const ulong t0 = GetMicrosecondCount();
      const bool sent = OrderSend(req, tr);
      const double latencyMs = (double)(GetMicrosecondCount() - t0) / 1000.0;

      res.sent = true;
      res.lastError = GetLastError();
      ApplyResult(tr, res);

      if(!sent && tr.retcode == 0)
        {
         //--- No server answer: conservatively retain the claim. Do not
         //--- assume a local error proves the broker never saw the request.
         res.confirmed = false;
         res.state = QME_EXEC_UNKNOWN_STATE;
         res.reject = QME_REJ_EXECUTION_FAILED;
         res.comment = "OrderSend returned no server answer: " + QmeLastErrorText();
         QmeLogMsg(QME_LOG_ERROR, "Order", res.comment);
         return(false);
        }

      // PLACED or partial fills may leave an active order or residual risk.
      // Keep the intent unresolved and require broker reconciliation.
      if(IsUnresolvedAcceptance(tr.retcode))
        {
         res.confirmed = false;
         res.state = QME_EXEC_UNKNOWN_STATE;
         res.reject = QME_REJ_EXECUTION_FAILED;
         res.time = TimeCurrent();
         res.comment = "placed or partially filled order: operator reconciliation required";
         return(false);
        }
      if(tr.retcode == TRADE_RETCODE_DONE)
        {
         res.confirmed = true;
         res.state = QME_EXEC_CONFIRMED;
         res.reject = QME_REJ_NONE;
         res.time = TimeCurrent();
         res.filledPrice = (tr.price > 0.0) ? tr.price : req.price;

         // An arbitrary same-symbol position is not proof of this fill on
         // hedging accounts. Match the broker's deal position identifier.
         ulong positionId = 0;
         if(tr.deal > 0 && HistoryDealSelect(tr.deal))
            positionId = (ulong)HistoryDealGetInteger(tr.deal, DEAL_POSITION_ID);
         ulong matched = 0;
         int matches = 0;
         for(int i = 0; positionId > 0 && i < PositionsTotal(); i++)
           {
            const ulong tk = PositionGetTicket(i);
            if(tk == 0 || !PositionSelectByTicket(tk)) continue;
            if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != positionId) continue;
            if(PositionGetString(POSITION_SYMBOL) != req.symbol) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC) != req.magic) continue;
            matched = tk;
            matches++;
           }
         if(matches != 1 || !PositionSelectByTicket(matched) ||
            PositionGetDouble(POSITION_SL) <= 0.0)
           {
            res.confirmed = false;
            res.state = QME_EXEC_UNKNOWN_STATE;
            res.reject = QME_REJ_EXECUTION_FAILED;
            res.comment = "filled deal has no uniquely identified protected position; operator reconciliation required";
            return(false);
           }
         res.positionTicket = matched;

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

   //--- unreachable while the loop above always returns; kept so every
   //--- control path has a defined result
   res.state = QME_EXEC_FAILED;
   res.confirmed = false;
   res.time = TimeCurrent();
   res.comment = "order send exited without a result";
   return(false);
  }

#endif // __QME_EXECUTION_ORDERMANAGER_MQH__
//+------------------------------------------------------------------+
