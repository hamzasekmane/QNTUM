//+------------------------------------------------------------------+
//|                                   Execution/TransactionHandler    |
//|  Turns OnTradeTransaction events into engine-visible facts.          |
//|                                                                   |
//|  Only transactions carrying our magic are accepted. Every accepted    |
//|  event is logged with its deal/order/position identity so an         |
//|  unexpected execution can always be traced.                           |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_TRANSACTION_MQH__
#define __QME_EXECUTION_TRANSACTION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

class CTransactionHandler
  {
private:
   ulong             m_magic;
   long              m_deals;
   long              m_orders;
   long              m_ignored;
   ulong             m_lastDeal;
   ulong             m_lastOrder;
   datetime          m_lastTime;

   bool              DealIsOurs(const ulong deal, const ulong order);

public:
                     CTransactionHandler(void) { Init(0); }
   void              Init(const ulong magic);
   void              Reset(void);

   bool              Handle(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                            const MqlTradeResult &result, SExecutionResult &out);

   long              Deals(void) { return(m_deals); }
   long              Orders(void) { return(m_orders); }
   long              Ignored(void) { return(m_ignored); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
void CTransactionHandler::Init(const ulong magic)
  {
   m_magic = magic;
   Reset();
  }

void CTransactionHandler::Reset(void)
  {
   m_deals = 0; m_orders = 0; m_ignored = 0;
   m_lastDeal = 0; m_lastOrder = 0; m_lastTime = 0;
  }

//------------------------------------------------------------------//
bool CTransactionHandler::DealIsOurs(const ulong deal, const ulong order)
  {
   if(m_magic == 0) return(true);

   if(deal > 0 && HistoryDealSelect(deal))
      return((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) == m_magic);

   if(order > 0 && HistoryOrderSelect(order))
      return((ulong)HistoryOrderGetInteger(order, ORDER_MAGIC) == m_magic);

   //--- cannot attribute it: do not claim it
   return(false);
  }

//------------------------------------------------------------------//
bool CTransactionHandler::Handle(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                                 const MqlTradeResult &result, SExecutionResult &out)
  {
   QmeExecClear(out);

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(!DealIsOurs(trans.deal, trans.order))
        {
         m_ignored++;
         return(false);
        }
      m_deals++;
      m_lastDeal = trans.deal;
      m_lastTime = trans.time;

      double volume = 0.0, price = 0.0;
      long entry = 0;
      if(HistoryDealSelect(trans.deal))
        {
         volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
        }

      out.dealTicket = trans.deal;
      out.orderTicket = trans.order;
      out.positionTicket = trans.position;
      out.filledVolume = volume;
      out.filledPrice = price;
      out.confirmed = true;
      out.state = QME_EXEC_CONFIRMED;
      out.time = trans.time;
      out.comment = "deal " + IntegerToString((long)trans.deal) +
                    " entry=" + IntegerToString((int)entry) +
                    " vol=" + DoubleToString(volume, 2);

      QmeLogMsg(QME_LOG_INFO, "Trade", "deal " + IntegerToString((long)trans.deal) +
                " on symbol " + IntegerToString((long)trans.symbol) + ": " + out.comment);
      return(true);
     }

   if(trans.type == TRADE_TRANSACTION_ORDER_ADD || trans.type == TRADE_TRANSACTION_ORDER_UPDATE)
     {
      if(request.magic != 0 && m_magic != 0 && request.magic != m_magic)
        {
         m_ignored++;
         return(false);
        }
      m_orders++;
      m_lastOrder = trans.order;
      m_lastTime = trans.time;
      QmeLogMsg(QME_LOG_INFO, "Trade", "order " + IntegerToString((long)trans.order) +
                " state " + IntegerToString((int)trans.order_state));
      out.orderTicket = trans.order;
      out.time = trans.time;
      out.comment = "order event";
      return(true);
     }

   if(trans.type == TRADE_TRANSACTION_ORDER_DELETE)
     {
      if(request.magic != 0 && m_magic != 0 && request.magic != m_magic)
        {
         m_ignored++;
         return(false);
        }
      QmeLogMsg(QME_LOG_WARN, "Trade", "order " + IntegerToString((long)trans.order) +
                " was deleted (result retcode " + IntegerToString((int)result.retcode) + ")");
      out.orderTicket = trans.order;
      out.time = trans.time;
      out.comment = "order deleted";
      return(true);
     }

   m_ignored++;
   return(false);
  }

//------------------------------------------------------------------//
string CTransactionHandler::Describe(void)
  {
   return("transactions deals=" + IntegerToString((int)m_deals) +
          " orders=" + IntegerToString((int)m_orders) +
          " ignored=" + IntegerToString((int)m_ignored));
  }

#endif // __QME_EXECUTION_TRANSACTION_MQH__
//+------------------------------------------------------------------+
