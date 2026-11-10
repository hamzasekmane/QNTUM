//+------------------------------------------------------------------+
//|                                 Tests/Validation/Test_DemoTrading  |
//|  DEMO authorization: works only when every switch is on, and the        |
//|  permission gates are satisfied. Nothing here sends an order.          |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_DEMO_MQH__
#define __QME_TEST_DEMO_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec DemoSpec(void)
  {
   SSymbolSpec s;
   s.symbol = "EURUSD";
   s.description = "EURUSD";
   s.path = "";
   s.digits = 5;
   s.point = 0.00001;
   s.tickSize = 0.00001;
   s.tickValue = 1.0;
   s.contractSize = 100000.0;
   s.volMin = 0.01; s.volMax = 100.0; s.volStep = 0.01;
   s.stopsLevelPoints = 0; s.freezeLevelPoints = 0;
   s.tradeMode = SYMBOL_TRADE_MODE_FULL;
   s.execMode = SYMBOL_TRADE_EXECUTION_MARKET;
   s.fillingMask = SYMBOL_FILLING_IOC;
   s.swapLong = 0.0; s.swapShort = 0.0; s.marginInitial = 0.0;
   s.tradeAllowed = true; s.selected = true; s.valid = true;
   return(s);
  }

SAccountContext DemoAccount(void)
  {
   SAccountContext a;
   QmeAccountClear(a);
   a.mode = QME_ACC_DEMO;
   a.login = 555001;
   a.server = "Demo";
   a.company = "Demo";
   a.currency = "USD";
   a.leverage = 500;
   a.balance = 10000.0; a.equity = 10000.0; a.freeMargin = 10000.0;
   a.accountTradeAllowed = true; a.expertTradeAllowed = true;
   a.terminalTradeAllowed = true; a.mqlTradeAllowed = true;
   a.connected = true; a.updated = TimeCurrent(); a.valid = true;
   return(a);
  }

int RunDemoTradingTests(void)
  {
   g_kit.Begin("Validation/Test_DemoTrading");

   SInputs in;
   QmeInputsDefaults(in);
   const SSymbolSpec spec = DemoSpec();
   const SAccountContext acc = DemoAccount();

   //--- 1. the shipped default must not trade
   ENUM_QME_REJECT rej = QME_REJ_NONE;
   string note = "";
   g_kit.Check(!CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "default configuration is not authorized");
   g_kit.Check(rej == QME_REJ_TRADING_NOT_AUTHORIZED, "analysisOnly is the first refusal");

   //--- 2. analysisOnly=false but demo trading still off
   in.analysisOnly = false;
   g_kit.Check(!CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "demo trading disabled by config");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_DISABLED_BY_CONFIG, "reason is configuration");

   //--- 3. demo trading enabled
   in.enableDemoTrading = true;
   g_kit.Check(CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "DEMO authorized once enabled");

   //--- 4. terminal permission missing -> refused
   SAccountContext noTerminal = acc;
   noTerminal.terminalTradeAllowed = false;
   g_kit.Check(!CTradingPermissions::Authorize(in, noTerminal, spec, QME_SIDE_BUY, rej, note),
               "terminal AutoTrading off blocks the trade");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_PERMISSION_TERMINAL, "reason is terminal permission");

   //--- 5. expert permission missing -> refused
   SAccountContext noExpert = acc;
   noExpert.mqlTradeAllowed = false;
   g_kit.Check(!CTradingPermissions::Authorize(in, noExpert, spec, QME_SIDE_BUY, rej, note),
               "EA algo trading off blocks the trade");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_PERMISSION_EXPERT, "reason is expert permission");

   //--- 6. directional policy
   SInputs noBuy = in;
   noBuy.allowBuy = false;
   g_kit.Check(!CTradingPermissions::Authorize(noBuy, acc, spec, QME_SIDE_BUY, rej, note),
               "allowBuy=false blocks longs");
   g_kit.Check(CTradingPermissions::Authorize(noBuy, acc, spec, QME_SIDE_SELL, rej, note),
               "allowBuy=false does not block shorts");

   //--- 7. an unknown account mode is never authorized, whatever the switches say
   SAccountContext unknown = acc;
   unknown.mode = QME_ACC_UNKNOWN;
   g_kit.Check(!CTradingPermissions::Authorize(in, unknown, spec, QME_SIDE_BUY, rej, note),
               "unknown account mode is never authorized");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_ACCOUNT_MODE, "reason is account mode");

   return(g_kit.End());
  }

#endif // __QME_TEST_DEMO_MQH__
//+------------------------------------------------------------------+
