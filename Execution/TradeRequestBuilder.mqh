//+------------------------------------------------------------------+
//|                            Execution/TradeRequestBuilder          |
//|  Builds a broker-legal MqlTradeRequest from a trade plan.            |
//|                                                                   |
//|  The builder NEVER changes the economics of a plan: it only           |
//|  translates it. Stop and target must already be valid; if the broker  |
//|  would reject the geometry, the request is refused here instead of     |
//|  being "fixed" silently.                                            |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_REQUESTBUILDER_MQH__
#define __QME_EXECUTION_REQUESTBUILDER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Account/BrokerCapabilities.mqh"

class CTradeRequestBuilder
  {
public:
   static bool       Build(MqlTradeRequest &req, const STradePlan &plan,
                           const SSymbolSpec &spec, const int fillingMode,
                           const int deviationPoints, const string comment,
                           string &why);
  };

//------------------------------------------------------------------//
bool CTradeRequestBuilder::Build(MqlTradeRequest &req, const STradePlan &plan,
                                 const SSymbolSpec &spec, const int fillingMode,
                                 const int deviationPoints, const string comment,
                                 string &why)
  {
   why = "";
   ZeroMemory(req);

   if(plan.volume <= 0.0) { why = "volume is zero"; return(false); }
   if(!QmeStopIsValid(plan.side, plan.entry, plan.stopLoss))
     { why = "stop invalid for this side"; return(false); }
   if(!QmeTargetIsValid(plan.side, plan.entry, plan.takeProfit))
     { why = "target invalid for this side"; return(false); }

   req.symbol = plan.symbol;
   req.volume = plan.volume;
   req.sl = CSymbolSpecifications::NormalizePrice(spec, plan.stopLoss);
   req.tp = CSymbolSpecifications::NormalizePrice(spec, plan.takeProfit);
   req.deviation = (uint)MathMax(deviationPoints, 0);
   req.magic = plan.magic;
   req.comment = comment;
   req.type_filling = (ENUM_ORDER_TYPE_FILLING)fillingMode;
   req.type_time = ORDER_TIME_GTC;

   if(plan.entryType == QME_ENTRY_MARKET)
     {
      MqlTick tick;
      if(!SymbolInfoTick(plan.symbol, tick))
        { why = "no live tick for " + plan.symbol; return(false); }
      if(tick.ask <= 0.0 || tick.bid <= 0.0 || tick.ask < tick.bid)
        { why = "invalid quotes for " + plan.symbol; return(false); }

      req.action = TRADE_ACTION_DEAL;
      if(plan.side == QME_SIDE_BUY)
        {
         req.type = ORDER_TYPE_BUY;
         req.price = tick.ask;
        }
      else
        {
         req.type = ORDER_TYPE_SELL;
         req.price = tick.bid;
        }
     }
   else
     {
      //--- pending entry: refuse if the limit price is already through the market
      MqlTick tick;
      if(!SymbolInfoTick(plan.symbol, tick))
        { why = "no live tick for " + plan.symbol; return(false); }

      if(plan.side == QME_SIDE_BUY)
        {
         if(plan.entry >= tick.ask)
           {
            why = "buy limit " + DoubleToString(plan.entry, spec.digits) +
                  " is not below the ask " + DoubleToString(tick.ask, spec.digits);
            return(false);
           }
         req.type = (plan.entryType == QME_ENTRY_LIMIT) ? ORDER_TYPE_BUY_LIMIT
                                                        : ORDER_TYPE_BUY_STOP;
        }
      else
        {
         if(plan.entry <= tick.bid)
           {
            why = "sell limit " + DoubleToString(plan.entry, spec.digits) +
                  " is not above the bid " + DoubleToString(tick.bid, spec.digits);
            return(false);
           }
         req.type = (plan.entryType == QME_ENTRY_LIMIT) ? ORDER_TYPE_SELL_LIMIT
                                                        : ORDER_TYPE_SELL_STOP;
        }
      req.action = TRADE_ACTION_PENDING;
      req.price = CSymbolSpecifications::NormalizePrice(spec, plan.entry);
     }

   return(true);
  }

#endif // __QME_EXECUTION_REQUESTBUILDER_MQH__
//+------------------------------------------------------------------+
