//+------------------------------------------------------------------+
//|                                         Execution/TradeManager    |
//|  Protection maintenance for open positions.                          |
//|                                                                   |
//|  HARD RULE: a protective stop may only be TIGHTENED. Any request      |
//|  that would move a stop away from price (or remove it) is refused     |
//|  here, and the refusal is logged. Closing is allowed only for a full  |
//|  or explicit partial close, never as a way to "reset" a loss.         |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_TRADEMANAGER_MQH__
#define __QME_EXECUTION_TRADEMANAGER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Core/Logger.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Account/BrokerCapabilities.mqh"
#include "PositionReconciler.mqh"

class CTradeManager
  {
public:
   static bool       ModifyProtection(const ulong ticket, const double newSL, const double newTP,
                                      const SSymbolSpec &spec, string &why);
   static bool       TightenStop(const ulong ticket, const double candidateSL,
                                 const SSymbolSpec &spec, string &why);
   static bool       ClosePosition(const ulong ticket, const double volume,
                                   const SSymbolSpec &spec, const int deviationPoints,
                                   string &why);
  };

//------------------------------------------------------------------//
bool CTradeManager::ModifyProtection(const ulong ticket, const double newSL, const double newTP,
                                     const SSymbolSpec &spec, string &why)
  {
   why = "";
   if(!PositionSelectByTicket(ticket))
     {
      why = "position " + IntegerToString((long)ticket) + " not found";
      return(false);
     }

   const string symbol = PositionGetString(POSITION_SYMBOL);
   const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const double curSL = PositionGetDouble(POSITION_SL);
   const double curTP = PositionGetDouble(POSITION_TP);

   if(newSL <= 0.0)
     {
      why = "refusing to remove the stop loss";
      QmeLogMsg(QME_LOG_ERROR, "TradeManager", why + " (position " +
                IntegerToString((long)ticket) + ")");
      return(false);
     }

   //--- never widen
   if(curSL > 0.0)
     {
      if(isBuy && newSL < curSL - QME_PRICE_EPS)
        {
         why = "refusing to widen a buy stop from " + DoubleToString(curSL, spec.digits) +
               " to " + DoubleToString(newSL, spec.digits);
         QmeLogMsg(QME_LOG_ERROR, "TradeManager", why);
         return(false);
        }
      if(!isBuy && newSL > curSL + QME_PRICE_EPS)
        {
         why = "refusing to widen a sell stop from " + DoubleToString(curSL, spec.digits) +
               " to " + DoubleToString(newSL, spec.digits);
         QmeLogMsg(QME_LOG_ERROR, "TradeManager", why);
         return(false);
        }
     }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
     {
      why = "no tick for " + symbol;
      return(false);
     }

   const double minDist = MathMax(CSymbolSpecifications::MinStopDistance(spec), 0.0);
   if(isBuy)
     {
      if(newSL >= tick.bid)
        { why = "buy stop must stay below the bid"; return(false); }
      if(minDist > 0.0 && (tick.bid - newSL) < minDist)
        { why = "buy stop inside the broker stops level"; return(false); }
     }
   else
     {
      if(newSL <= tick.ask)
        { why = "sell stop must stay above the ask"; return(false); }
      if(minDist > 0.0 && (newSL - tick.ask) < minDist)
        { why = "sell stop inside the broker stops level"; return(false); }
     }

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_SLTP;
   req.symbol = symbol;
   req.position = ticket;
   req.sl = CSymbolSpecifications::NormalizePrice(spec, newSL);
   req.tp = (newTP > 0.0) ? CSymbolSpecifications::NormalizePrice(spec, newTP) : curTP;
   req.magic = (ulong)PositionGetInteger(POSITION_MAGIC);

   if(!OrderSend(req, res))
     {
      why = "SLTP modify failed: " + QmeLastErrorText() + " / " + QmeRetcodeText(res.retcode);
      QmeLogMsg(QME_LOG_WARN, "TradeManager", why);
      return(false);
     }
   if(!QmeRetcodeIsSuccess(res.retcode) && res.retcode != 0)
     {
      why = "SLTP modify rejected: " + QmeRetcodeText(res.retcode) + " " + res.comment;
      QmeLogMsg(QME_LOG_WARN, "TradeManager", why);
      return(false);
     }

   QmeLogMsg(QME_LOG_INFO, "TradeManager", "position " + IntegerToString((long)ticket) +
             " stop moved to " + DoubleToString(newSL, spec.digits));
   return(true);
  }

//------------------------------------------------------------------//
bool CTradeManager::TightenStop(const ulong ticket, const double candidateSL,
                                const SSymbolSpec &spec, string &why)
  {
   why = "";
   if(!PositionSelectByTicket(ticket))
     {
      why = "position not found";
      return(false);
     }
   const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const double curSL = PositionGetDouble(POSITION_SL);
   const double curTP = PositionGetDouble(POSITION_TP);

   //--- only move if it actually tightens risk
   if(curSL > 0.0)
     {
      if(isBuy && candidateSL <= curSL + QME_PRICE_EPS) return(false);
      if(!isBuy && candidateSL >= curSL - QME_PRICE_EPS) return(false);
     }
   return(ModifyProtection(ticket, candidateSL, curTP, spec, why));
  }

//------------------------------------------------------------------//
bool CTradeManager::ClosePosition(const ulong ticket, const double volume,
                                  const SSymbolSpec &spec, const int deviationPoints,
                                  string &why)
  {
   why = "";
   if(!PositionSelectByTicket(ticket))
     {
      why = "position not found";
      return(false);
     }

   const string symbol = PositionGetString(POSITION_SYMBOL);
   const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const double total = PositionGetDouble(POSITION_VOLUME);
   const double vol = (volume <= 0.0) ? total : MathMin(volume, total);
   if(vol <= 0.0)
     {
      why = "close volume is zero";
      return(false);
     }
   if(!CSymbolSpecifications::VolumeInRange(spec, vol))
     {
      why = "close volume " + DoubleToString(vol, 2) + " is not broker-legal";
      return(false);
     }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
     {
      why = "no tick for " + symbol;
      return(false);
     }

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = symbol;
   req.position = ticket;
   req.volume = vol;
   req.deviation = (uint)MathMax(deviationPoints, 0);
   const int closeFill = CBrokerCapabilities::ChooseFilling(spec,
                             isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   req.type_filling = (closeFill >= 0) ? (ENUM_ORDER_TYPE_FILLING)closeFill
                                       : ORDER_FILLING_RETURN;
   req.magic = (ulong)PositionGetInteger(POSITION_MAGIC);
   req.comment = QME_ORDER_COMMENT;
   if(isBuy)
     {
      req.type = ORDER_TYPE_SELL;
      req.price = tick.bid;
     }
   else
     {
      req.type = ORDER_TYPE_BUY;
      req.price = tick.ask;
     }

   if(!OrderSend(req, res) || (!QmeRetcodeIsSuccess(res.retcode) && res.retcode != 0))
     {
      why = "close failed: " + QmeRetcodeText(res.retcode) + " " + res.comment;
      QmeLogMsg(QME_LOG_WARN, "TradeManager", why);
      return(false);
     }

   QmeLogMsg(QME_LOG_INFO, "TradeManager", "closed " + DoubleToString(vol, 2) +
             " of position " + IntegerToString((long)ticket));
   return(true);
  }

#endif // __QME_EXECUTION_TRADEMANAGER_MQH__
//+------------------------------------------------------------------+
