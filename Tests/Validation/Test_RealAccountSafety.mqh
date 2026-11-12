//+------------------------------------------------------------------+
//|                          Tests/Validation/Test_RealAccountSafety  |
//|  THIS IS THE MOST IMPORTANT TEST IN THE PROJECT.                      |
//|                                                                   |
//|  It proves, case by case, that a REAL account cannot be traded        |
//|  unless every independent condition is satisfied, and that an         |
//|  unknown account type is never authorized. Nothing is sent.           |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_REAL_MQH__
#define __QME_TEST_REAL_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec RealSpec(void)
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

SAccountContext RealAccount(const long login)
  {
   SAccountContext a;
   QmeAccountClear(a);
   a.mode = QME_ACC_REAL;
   a.login = login;
   a.server = "Live";
   a.company = "Live";
   a.currency = "USD";
   a.leverage = 100;
   a.balance = 5000.0; a.equity = 5000.0; a.freeMargin = 5000.0;
   a.accountTradeAllowed = true; a.expertTradeAllowed = true;
   a.terminalTradeAllowed = true; a.mqlTradeAllowed = true;
   a.connected = true; a.updated = TimeCurrent(); a.valid = true;
   return(a);
  }

int RunRealAccountSafetyTests(void)
  {
   g_kit.Begin("Validation/Test_RealAccountSafety");

   const SSymbolSpec spec = RealSpec();
   const SAccountContext acc = RealAccount(777001);

   SInputs in;
   QmeInputsDefaults(in);
   in.analysisOnly = false;

   ENUM_QME_REJECT rej = QME_REJ_NONE;
   string note = "";

   //--- 1. REAL trading disabled (the shipped default)
   g_kit.Check(!CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "REAL is refused when enableRealTrading=false");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_DISABLED_BY_CONFIG, "reason is configuration");

   //--- 2. enabled but not armed
   in.enableRealTrading = true;
   g_kit.Check(!CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "REAL is refused when not armed");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_TRADING_NOT_AUTHORIZED, "reason is arming");

   //--- 3. armed but no expected login configured
   in.realTradingArmed = true;
   g_kit.Check(!CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "REAL is refused when no expected login is configured");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_LOGIN_MISMATCH, "reason is login mismatch");

   //--- 4. armed with a login that does not match
   in.expectedRealAccountLogin = 777002;
   g_kit.Check(!CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "REAL is refused on a login mismatch");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_LOGIN_MISMATCH, "mismatch reason is explicit");

   //--- 5. every gate satisfied: this is the only path to a REAL order
   in.expectedRealAccountLogin = 777001;
   g_kit.Check(CTradingPermissions::Authorize(in, acc, spec, QME_SIDE_BUY, rej, note),
               "REAL is authorized only when every gate is satisfied");
   g_kit.CheckEqual((long)rej, (long)QME_REJ_NONE, "no rejection reason on the happy path");

   //--- 6. account permissions still gate the happy path
   SAccountContext noAcct = acc;
   noAcct.accountTradeAllowed = false;
   g_kit.Check(!CTradingPermissions::Authorize(in, noAcct, spec, QME_SIDE_BUY, rej, note),
               "broker account trading disabled blocks REAL");

   SAccountContext noExpertAcct = acc;
   noExpertAcct.expertTradeAllowed = false;
   g_kit.Check(!CTradingPermissions::Authorize(in, noExpertAcct, spec, QME_SIDE_BUY, rej, note),
               "account expert trading disabled blocks REAL");

   //--- 7. unknown / unsupported modes are never authorized
   SAccountContext unknown = acc;
   unknown.mode = QME_ACC_UNKNOWN;
   g_kit.Check(!CTradingPermissions::Authorize(in, unknown, spec, QME_SIDE_BUY, rej, note),
               "unknown account mode blocked even with REAL switches on");

   //--- 8. a DEMO account must not be traded when only REAL is enabled
   SInputs realOnly = in;
   realOnly.enableDemoTrading = false;
   SAccountContext demo = acc;
   demo.mode = QME_ACC_DEMO;
   g_kit.Check(!CTradingPermissions::Authorize(realOnly, demo, spec, QME_SIDE_BUY, rej, note),
               "DEMO account refused when demo trading is off");

   //--- 9. analysisOnly overrides everything, even a fully armed REAL setup
   SInputs sim = in;
   sim.analysisOnly = true;
   g_kit.Check(!CTradingPermissions::Authorize(sim, acc, spec, QME_SIDE_BUY, rej, note),
               "analysisOnly overrides a fully armed REAL configuration");

   //--- 10. the runtime controller must agree with the permission layer
   CConfig cfg;
   string err = "";
   if(cfg.Init(sim, err))
     {
      CRuntimeController ctl;
      ctl.Init(cfg, acc);
      g_kit.Check(!ctl.IsLive(), "controller is not LIVE in analysis mode");
      string why = "";
      g_kit.Check(!ctl.MayTrade(cfg, acc, true, why), "controller refuses to trade");
      g_kit.Check(StringLen(why) > 0, "controller explains the refusal");
     }
   else
      g_kit.Skip("configuration init failed: " + err);

   // A previously LIVE controller must re-check revoked permissions, and a
   // bare Resume() must not restore trading without fresh authorization.
   SInputs authorized;
   QmeInputsDefaults(authorized);
   authorized.analysisOnly = false;
   authorized.enableRealTrading = true;
   authorized.realTradingArmed = true;
   authorized.expectedRealAccountLogin = 777001;
   CConfig liveCfg;
   string liveErr = "";
   if(liveCfg.Init(authorized, liveErr))
     {
      CRuntimeController liveCtl;
      liveCtl.Init(liveCfg, acc);
      string whyLive = "";
      g_kit.Check(liveCtl.MayTrade(liveCfg, acc, true, whyLive), "authorized LIVE state passes fresh permission check");
      SAccountContext revoked = acc;
      revoked.terminalTradeAllowed = false;
      g_kit.Check(!liveCtl.MayTrade(liveCfg, revoked, true, whyLive), "revoked terminal permission blocks next entry");
      g_kit.Check(!liveCtl.IsLive(), "permission revocation pauses runtime");
      liveCtl.Resume("operator requested resume");
      g_kit.Check(!liveCtl.IsLive(), "bare resume cannot restore LIVE without reauthorization");
     }
   else
      g_kit.Check(false, "live authorization test configuration: " + liveErr);

   return(g_kit.End());
  }

#endif // __QME_TEST_REAL_MQH__
//+------------------------------------------------------------------+
