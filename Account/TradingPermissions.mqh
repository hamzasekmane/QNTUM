//+------------------------------------------------------------------+
//|                                     Account/TradingPermissions.mqh|
//|  QuantumMarketEngine — the ONLY place that decides whether the      |
//|  engine is allowed to send an order to this account.                |
//|                                                                   |
//|  DESIGN:                                                          |
//|   * account detection is not authorization;                      |
//|   * every gate is evaluated independently and returns an explicit   |
//|     ENUM_QME_REJECT reason;                                         |
//|   * DEMO and REAL share the same analysis pipeline — only these     |
//|     gates differ;                                                  |
//|   * an UNKNOWN account mode can never be authorized.                |
//|                                                                   |
//|  REAL requires ALL of:                                             |
//|   1. mode == REAL (CONTEST is treated as REAL: it holds real funds) |
//|   2. InpEnableRealTrading == true                                  |
//|   3. InpRealTradingArmed == true                                   |
//|   4. login == InpExpectedRealAccountLogin                           |
//|   5. terminal trade allowed                                        |
//|   6. MQL (expert) trade allowed                                    |
//|   7. account trade allowed and account expert allowed              |
//|   8. symbol tradable + side permitted                              |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_PERMISSIONS_MQH__
#define __QME_ACCOUNT_PERMISSIONS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "AccountModeDetector.mqh"
#include "BrokerCapabilities.mqh"
#include "SymbolSpecifications.mqh"

class CTradingPermissions
  {
public:
   //--- individual terminal/account gates
   static bool       TerminalTradingAllowed(void);   // the "AutoTrading" button
   static bool       MqlTradingAllowed(void);        // "Allow algo trading" for this EA
   static bool       AccountTradeAllowed(void);
   static bool       AccountExpertAllowed(void);

   //--- full authorization for a would-be order
   static bool       Authorize(const SInputs &in, const SAccountContext &acc,
                               const SSymbolSpec &spec, const ENUM_QME_SIDE side,
                               ENUM_QME_REJECT &reject, string &note);

   //--- why is this configuration allowed/blocked (dashboard + logs)
   static string     AuthorizationSummary(const SInputs &in, const SAccountContext &acc);
  };

//------------------------------------------------------------------//
bool CTradingPermissions::TerminalTradingAllowed(void)
  { return((bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)); }

bool CTradingPermissions::MqlTradingAllowed(void)
  { return((bool)MQLInfoInteger(MQL_TRADE_ALLOWED)); }

bool CTradingPermissions::AccountTradeAllowed(void)
  { return((bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)); }

bool CTradingPermissions::AccountExpertAllowed(void)
  { return((bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT)); }

//------------------------------------------------------------------//
bool CTradingPermissions::Authorize(const SInputs &in, const SAccountContext &acc,
                                    const SSymbolSpec &spec, const ENUM_QME_SIDE side,
                                    ENUM_QME_REJECT &reject, string &note)
  {
   reject = QME_REJ_NONE;
   note = "";

   //--- gate 0: simulation mode blocks everything, by design
   if(in.analysisOnly)
     {
      reject = QME_REJ_TRADING_NOT_AUTHORIZED;
      note = "analysisOnly mode: no order will ever be sent";
      return(false);
     }

   //--- gate 1: account mode
   if(acc.mode == QME_ACC_UNKNOWN)
     {
      reject = QME_REJ_ACCOUNT_MODE;
      note = "account mode unknown: trading is never authorized";
      return(false);
     }

   if(acc.mode == QME_ACC_DEMO)
     {
      if(!in.enableDemoTrading)
        {
         reject = QME_REJ_DISABLED_BY_CONFIG;
         note = "InpEnableDemoTrading is false";
         return(false);
        }
     }
   else if(acc.mode == QME_ACC_REAL || acc.mode == QME_ACC_CONTEST)
     {
      //--- contest accounts hold real funds: same gates as REAL
      if(!in.enableRealTrading)
        {
         reject = QME_REJ_DISABLED_BY_CONFIG;
         note = "InpEnableRealTrading is false";
         return(false);
        }
      if(!in.realTradingArmed)
        {
         reject = QME_REJ_TRADING_NOT_AUTHORIZED;
         note = "InpRealTradingArmed is false";
         return(false);
        }
      if(in.expectedRealAccountLogin <= 0)
        {
         reject = QME_REJ_LOGIN_MISMATCH;
         note = "InpExpectedRealAccountLogin is not configured";
         return(false);
        }
      if(acc.login != in.expectedRealAccountLogin)
        {
         reject = QME_REJ_LOGIN_MISMATCH;
         note = "login " + IntegerToString(acc.login) + " != expected " +
                IntegerToString(in.expectedRealAccountLogin);
         return(false);
        }
     }
   else
     {
      reject = QME_REJ_ACCOUNT_MODE;
      note = "unsupported account mode";
      return(false);
     }

   //--- gate 2..5: terminal / account permissions
   if(!acc.terminalTradeAllowed)
     {
      reject = QME_REJ_PERMISSION_TERMINAL;
      note = "terminal AutoTrading is disabled";
      return(false);
     }
   if(!acc.mqlTradeAllowed)
     {
      reject = QME_REJ_PERMISSION_EXPERT;
      note = "algorithmic trading is not allowed for this EA";
      return(false);
     }
   if(!acc.accountTradeAllowed)
     {
      reject = QME_REJ_ACCOUNT_PERMISSION;
      note = "account trading is disabled by the broker";
      return(false);
     }
   if(!acc.expertTradeAllowed)
     {
      reject = QME_REJ_PERMISSION_EXPERT;
      note = "expert trading is disabled for this account";
      return(false);
     }

   //--- gate 6: symbol and side
   if(spec.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
     {
      reject = QME_REJ_PERMISSION_SYMBOL;
      note = "symbol trading disabled by broker";
      return(false);
     }
   string err = "";
   if(!CBrokerCapabilities::SupportsSide(spec, side, err))
     {
      reject = QME_REJ_PERMISSION_SYMBOL;
      note = err;
      return(false);
     }

   //--- gate 7: user directional policy
   if(side == QME_SIDE_BUY && !in.allowBuy)
     {
      reject = QME_REJ_DISABLED_BY_CONFIG;
      note = "InpAllowBuy is false";
      return(false);
     }
   if(side == QME_SIDE_SELL && !in.allowSell)
     {
      reject = QME_REJ_DISABLED_BY_CONFIG;
      note = "InpAllowSell is false";
      return(false);
     }

   note = "authorized for " + QmeAccountModeName(acc.mode);
   return(true);
  }

//------------------------------------------------------------------//
string CTradingPermissions::AuthorizationSummary(const SInputs &in, const SAccountContext &acc)
  {
   string s = "mode=" + QmeAccountModeName(acc.mode);
   s += " terminal=" + QmeBoolStr(acc.terminalTradeAllowed);
   s += " mql=" + QmeBoolStr(acc.mqlTradeAllowed);
   s += " account=" + QmeBoolStr(acc.accountTradeAllowed);
   s += " expert=" + QmeBoolStr(acc.expertTradeAllowed);
   s += " analysisOnly=" + QmeBoolStr(in.analysisOnly);
   s += " demoSwitch=" + QmeBoolStr(in.enableDemoTrading);
   s += " realSwitch=" + QmeBoolStr(in.enableRealTrading);
   s += " armed=" + QmeBoolStr(in.realTradingArmed);
   if(acc.mode == QME_ACC_REAL || acc.mode == QME_ACC_CONTEST)
      s += " loginMatch=" + QmeBoolStr(acc.login == in.expectedRealAccountLogin);
   return(s);
  }

#endif // __QME_ACCOUNT_PERMISSIONS_MQH__
//+------------------------------------------------------------------+
