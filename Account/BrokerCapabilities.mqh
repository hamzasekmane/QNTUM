//+------------------------------------------------------------------+
//|                                        Account/BrokerCapabilities |
//|  QuantumMarketEngine — what the broker/terminal actually allows.   |
//|                                                                   |
//|  Interface:                                                       |
//|    ENUM_ORDER_TYPE_FILLING ChooseFilling(spec, orderType)          |
//|    bool IsSessionOpen(spec)                                       |
//|    bool SupportsSide(spec, side)                                  |
//|  Nothing here assumes a broker default: unsupported combinations   |
//|  are reported as unsupported and the trade is rejected.            |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_BROKERCAPS_MQH__
#define __QME_ACCOUNT_BROKERCAPS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "SymbolSpecifications.mqh"

class CBrokerCapabilities
  {
public:
   //--- pick a filling mode the symbol actually reports.
   //--- Returns WRONG_VALUE (=-1) when nothing usable is offered.
   static int        ChooseFilling(const SSymbolSpec &spec, const ENUM_ORDER_TYPE type);

   //--- can this symbol be bought / sold at all?
   static bool       SupportsSide(const SSymbolSpec &spec, const ENUM_QME_SIDE side, string &err);

   //--- is the symbol inside a trading session right now (server time)?
   static bool       IsSessionOpen(const string symbol, const datetime serverTime, string &err);

   //--- execution quality classification from the broker mode
   static bool       IsMarketExecution(const SSymbolSpec &spec);
   static bool       IsInstantExecution(const SSymbolSpec &spec);
   static bool       IsExchangeExecution(const SSymbolSpec &spec);

   //--- textual description for the dashboard
   static string     DescribeExecution(const SSymbolSpec &spec);
   static string     DescribeFilling(const int fillingMask);
  };

//------------------------------------------------------------------//
//| Filling policy:                                                     |
//|  - market orders prefer IOC, then FOK; if neither is reported use   |
//|    RETURN only when the broker has no FOK/IOC flag at all (some     |
//|    exchanges report 0).                                             |
//|  - pending orders use RETURN when available, else the first          |
//|    supported mode.                                                  |
//+------------------------------------------------------------------//
int CBrokerCapabilities::ChooseFilling(const SSymbolSpec &spec, const ENUM_ORDER_TYPE type)
  {
   const bool fok = ((spec.fillingMask & SYMBOL_FILLING_FOK) != 0);
   const bool ioc = ((spec.fillingMask & SYMBOL_FILLING_IOC) != 0);
   const bool anyReported = (spec.fillingMask != 0);

   if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
     {
      if(ioc) return((int)ORDER_FILLING_IOC);
      if(fok) return((int)ORDER_FILLING_FOK);
      if(!anyReported) return((int)ORDER_FILLING_RETURN); // exchange-style
      return(WRONG_VALUE);
     }

   //--- pending orders
   if(anyReported && !fok && !ioc) return((int)ORDER_FILLING_RETURN);
   if(fok) return((int)ORDER_FILLING_FOK);
   if(ioc) return((int)ORDER_FILLING_IOC);
   return((int)ORDER_FILLING_RETURN);
  }

//------------------------------------------------------------------//
bool CBrokerCapabilities::SupportsSide(const SSymbolSpec &spec, const ENUM_QME_SIDE side, string &err)
  {
   err = "";
   if(side == QME_SIDE_NONE)
     {
      err = "no side";
      return(false);
     }
   if(side == QME_SIDE_BUY &&
      (spec.tradeMode == SYMBOL_TRADE_MODE_SHORTONLY || spec.tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY))
     {
      err = "broker allows no long positions on " + spec.symbol;
      return(false);
     }
   if(side == QME_SIDE_SELL &&
      (spec.tradeMode == SYMBOL_TRADE_MODE_LONGONLY || spec.tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY))
     {
      err = "broker allows no short positions on " + spec.symbol;
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CBrokerCapabilities::IsSessionOpen(const string symbol, const datetime serverTime, string &err)
  {
   err = "";
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   const int day = dt.day_of_week;   // 0 = Sunday

   //--- SymbolInfoSessionTrade(symbol, day, index, from, to) returns false when
   //--- the day has no session at all. We iterate the sessions of today.
   datetime fromDt = 0, toDt = 0;   // reported as seconds from 00:00 of the day
   bool anySession = false;
   bool insideSession = false;
   const long secondsOfDay = (long)dt.hour * 3600 + dt.min * 60 + dt.sec;

   for(uint idx = 0; idx < 8; idx++)
     {
      if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)day, idx, fromDt, toDt))
         break;                       // no more sessions for this weekday
      anySession = true;
      const long from = (long)fromDt;
      const long to   = (long)toDt;
      if(secondsOfDay >= from && secondsOfDay < to)
        {
         insideSession = true;
         break;
        }
     }

   if(!anySession)
     {
      err = "no trading session today for " + symbol;
      return(false);
     }
   if(!insideSession)
     {
      err = "outside trading session for " + symbol;
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CBrokerCapabilities::IsMarketExecution(const SSymbolSpec &spec)
  { return(spec.execMode == SYMBOL_TRADE_EXECUTION_MARKET); }

bool CBrokerCapabilities::IsInstantExecution(const SSymbolSpec &spec)
  { return(spec.execMode == SYMBOL_TRADE_EXECUTION_INSTANT); }

bool CBrokerCapabilities::IsExchangeExecution(const SSymbolSpec &spec)
  { return(spec.execMode == SYMBOL_TRADE_EXECUTION_EXCHANGE); }

//------------------------------------------------------------------//
string CBrokerCapabilities::DescribeExecution(const SSymbolSpec &spec)
  {
   switch(spec.execMode)
     {
      case SYMBOL_TRADE_EXECUTION_REQUEST: return("REQUEST");
      case SYMBOL_TRADE_EXECUTION_INSTANT: return("INSTANT");
      case SYMBOL_TRADE_EXECUTION_MARKET:  return("MARKET");
      case SYMBOL_TRADE_EXECUTION_EXCHANGE:return("EXCHANGE");
     }
   return("UNKNOWN");
  }

string CBrokerCapabilities::DescribeFilling(const int fillingMask)
  {
   string s = "";
   if((fillingMask & SYMBOL_FILLING_FOK) != 0) s += "FOK ";
   if((fillingMask & SYMBOL_FILLING_IOC) != 0) s += "IOC ";
   if(fillingMask == 0) s = "NONE_REPORTED";
   return(s);
  }

#endif // __QME_ACCOUNT_BROKERCAPS_MQH__
//+------------------------------------------------------------------+
