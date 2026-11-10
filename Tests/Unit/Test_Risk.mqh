//+------------------------------------------------------------------+
//|                                         Tests/Unit/Test_Risk      |
//|  Sizing arithmetic and the account-level guards.                     |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_RISK_MQH__
#define __QME_TEST_RISK_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec RiskSpec(void)
  {
   SSymbolSpec s;
   s.symbol = "EURUSD";
   s.description = "EURUSD";
   s.path = "";
   s.digits = 5;
   s.point = 0.00001;
   s.tickSize = 0.00001;
   s.tickValue = 1.0;          // 1 USD per tick per lot
   s.contractSize = 100000.0;
   s.volMin = 0.01;
   s.volMax = 100.0;
   s.volStep = 0.01;
   s.stopsLevelPoints = 0;
   s.freezeLevelPoints = 0;
   s.tradeMode = SYMBOL_TRADE_MODE_FULL;
   s.execMode = SYMBOL_TRADE_EXECUTION_MARKET;
   s.fillingMask = SYMBOL_FILLING_IOC;
   s.swapLong = 0.0; s.swapShort = 0.0; s.marginInitial = 0.0;
   s.tradeAllowed = true; s.selected = true; s.valid = true;
   return(s);
  }

SAccountContext RiskAccount(const double equity, const ENUM_QME_ACCOUNT_MODE mode)
  {
   SAccountContext a;
   QmeAccountClear(a);
   a.mode = mode;
   a.login = 123456;
   a.server = "Test-Server";
   a.company = "Test";
   a.currency = "USD";
   a.leverage = 100;
   a.balance = equity;
   a.equity = equity;
   a.freeMargin = equity;
   a.accountTradeAllowed = true;
   a.expertTradeAllowed = true;
   a.terminalTradeAllowed = true;
   a.mqlTradeAllowed = true;
   a.connected = true;
   a.updated = TimeCurrent();
   a.valid = true;
   return(a);
  }

int RunRiskTests(void)
  {
   g_kit.Begin("Unit/Test_Risk");
   const SSymbolSpec spec = RiskSpec();

   //--- sizing audit against THIS mock spec (the derivation, not a guess):
   //--- tickValue 1.0 per tickSize 0.00001 => 100000 USD per 1.00 of price
   //--- per lot. A 20-pip stop (0.0020) therefore loses 200 USD per lot, so
   //--- a 100 USD budget buys exactly 0.50 lots. (An earlier revision of
   //--- this test expected 1.00/0.33 lots, which implies a 5 USD pip value
   //--- this specification does not have; the engine was right.)
   const double riskMoney = 100.0;
   const double stopDistance = 20 * 0.0001;
   const double vol = CRiskBudget::VolumeForRisk(spec, riskMoney, stopDistance);
   g_kit.CheckClose(vol, 0.50, 0.005, "1% of 10k with a 20 pip stop is 0.50 lot on this spec");

   //--- rounding is always DOWN to the broker step
   const double odd = CRiskBudget::VolumeForRisk(spec, 33.3, stopDistance);
   g_kit.CheckClose(odd, 0.16, 0.0001, "volume rounds down to the lot step");
   g_kit.Check(CRiskBudget::ActualRiskMoney(spec, odd, stopDistance) <= 33.3 + 1e-9,
               "actual risk never exceeds the budget");

   //--- degenerate inputs never produce a trade
   g_kit.CheckClose(CRiskBudget::VolumeForRisk(spec, 0.0, stopDistance), 0.0, 1e-9,
                    "zero budget -> zero volume");
   g_kit.CheckClose(CRiskBudget::VolumeForRisk(spec, riskMoney, 0.0), 0.0, 1e-9,
                    "zero stop -> zero volume");
   g_kit.CheckClose(CRiskBudget::VolumeForRisk(spec, -5.0, stopDistance), 0.0, 1e-9,
                    "negative budget -> zero volume");
   g_kit.CheckClose(CRiskBudget::VolumeForRisk(spec, 1e9, stopDistance), spec.volMax, 1e-9,
                    "volume is capped by the broker maximum");

   //--- a metals-style specification: tick 0.01 worth 1.0 => 100 per 1.00
   //--- of price per lot; a 2.50 stop loses 250/lot; 100 budget => 0.40
   SSymbolSpec xau = spec;
   xau.symbol = "XAUUSD";
   xau.digits = 2;
   xau.point = 0.01;
   xau.tickSize = 0.01;
   xau.tickValue = 1.0;
   xau.contractSize = 100.0;
   g_kit.CheckClose(CRiskBudget::VolumeForRisk(xau, 100.0, 2.50), 0.40, 1e-9,
                    "metals spec sizes from its own tick value/size");

   //--- when even the broker minimum would exceed the budget: no trade
   SSymbolSpec coarse = spec;
   coarse.volMin = 0.50;
   coarse.volStep = 0.50;
   g_kit.CheckClose(CRiskBudget::VolumeForRisk(coarse, 50.0, stopDistance), 0.0, 1e-9,
                    "minimum volume above budget yields zero, never the minimum");

   //--- a coarse step still rounds DOWN, never up into the budget
   SSymbolSpec stepSpec = spec;
   stepSpec.volStep = 0.25;
   const double stepped = CRiskBudget::VolumeForRisk(stepSpec, 90.0, stopDistance);
   g_kit.CheckClose(stepped, 0.25, 1e-9, "0.45 raw rounds down to the 0.25 step");
   g_kit.Check(CRiskBudget::ActualRiskMoney(stepSpec, stepped, stopDistance) <= 90.0 + 1e-9,
               "stepped volume stays inside the budget");

   //--- risk as a percentage of equity
   g_kit.CheckClose(CRiskBudget::RiskPctOfEquity(100.0, 10000.0), 1.0, 1e-6,
                    "risk pct of equity");
   g_kit.CheckClose(CRiskBudget::RiskPctOfEquity(100.0, 0.0), 0.0, 1e-9,
                    "zero equity never yields a percentage");

   //--- daily loss guard
   SAccountContext acc = RiskAccount(10000.0, QME_ACC_DEMO);
   CAccountState state;
   state.Reset();
   state.Init(acc);
   double pct = 0.0;
   string why = "";
   g_kit.Check(CDailyLossGuard::Check(acc, state, 3.0, pct, why),
               "fresh account passes the daily guard");
   g_kit.CheckClose(pct, 0.0, 1e-9, "fresh daily loss is zero");

   //--- the same guard must refuse once the day's loss exceeds the limit
   acc.equity = 9600.0;                     // -4% intraday
   state.Init(acc);                         // day starts here only if not initialised
   state.Reset();
   SAccountContext start = RiskAccount(10000.0, QME_ACC_DEMO);
   state.Init(start);
   const bool allowed = CDailyLossGuard::Check(acc, state, 3.0, pct, why);
   g_kit.Check(!allowed, "daily loss guard blocks a 4% intraday loss");
   g_kit.Check(pct <= -3.0, "reported daily P/L is at or below -3%");

   return(g_kit.End());
  }

#endif // __QME_TEST_RISK_MQH__
//+------------------------------------------------------------------+
