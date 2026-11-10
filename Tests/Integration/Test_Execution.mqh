//+------------------------------------------------------------------+
//|                                  Tests/Integration/Test_Execution |
//|  The execution pipeline up to (but NOT including) OrderSend.          |
//|  Nothing here can place an order: no test may ever trade.             |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_EXECUTION_MQH__
#define __QME_TEST_EXECUTION_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

SSymbolSpec ExecSpec(void)
  {
   SSymbolSpec s;
   s.symbol = _Symbol;
   s.description = _Symbol;
   s.path = "";
   s.digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   s.point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   s.tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   s.tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   s.contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   s.volMin = 0.01; s.volMax = 100.0; s.volStep = 0.01;
   s.stopsLevelPoints = 0; s.freezeLevelPoints = 0;
   s.tradeMode = SYMBOL_TRADE_MODE_FULL;
   s.execMode = SYMBOL_TRADE_EXECUTION_MARKET;
   s.fillingMask = SYMBOL_FILLING_IOC;
   s.swapLong = 0.0; s.swapShort = 0.0; s.marginInitial = 0.0;
   s.tradeAllowed = true; s.selected = true;
   s.valid = (s.point > 0.0 && s.tickSize > 0.0);
   return(s);
  }

STradePlan ExecPlan(const SSymbolSpec &spec, const ENUM_QME_SIDE side)
  {
   STradePlan p;
   QmePlanClear(p);
   p.signalId = 77;
   p.symbol = spec.symbol;
   p.side = side;
   p.entryType = QME_ENTRY_MARKET;
   p.entry = 1.10000;
   p.stopLoss = (side == QME_SIDE_BUY) ? 1.09800 : 1.10200;
   p.takeProfit = (side == QME_SIDE_BUY) ? 1.10400 : 1.09600;
   p.volume = 0.10;
   p.riskMoney = 20.0;
   p.rr = 2.0;
   p.magic = 999001;
   p.fingerprint = "test-fingerprint-1";
   p.created = TimeCurrent();
   return(p);
  }

int RunExecutionTests(void)
  {
   g_kit.Begin("Integration/Test_Execution");

   const SSymbolSpec spec = ExecSpec();
   if(!spec.valid)
     {
      g_kit.Skip("symbol specification unavailable");
      return(g_kit.End());
     }

   SInputs in;
   QmeInputsDefaults(in);
   in.analysisOnly = true;      // guarantees nothing can be sent
   in.logLevel = QME_LOG_WARN;
   string err = "";
   CConfig cfg;
   cfg.Init(in, err);

   //--- local validation refuses a plan without a stop
   STradePlan noStop = ExecPlan(spec, QME_SIDE_BUY);
   noStop.stopLoss = 0.0;
   MqlTradeRequest req;
   string buildWhy = "";
   const bool built = CTradeRequestBuilder::Build(req, noStop, spec, spec.fillingMask, 20,
                                                  "QME", buildWhy);
   g_kit.Check(!built, "builder refuses a plan without a stop");
   g_kit.Check(StringLen(buildWhy) > 0, "builder explains the refusal");

   //--- a valid plan builds a request with both protections
   STradePlan good = ExecPlan(spec, QME_SIDE_BUY);
   if(!CTradeRequestBuilder::Build(req, good, spec, spec.fillingMask, 20, "QME", buildWhy))
     {
      g_kit.Skip("no live tick to build a market request: " + buildWhy);
     }
   else
     {
      g_kit.Check(req.sl > 0.0 && req.tp > 0.0, "request carries SL and TP");
      g_kit.Check(req.type == ORDER_TYPE_BUY, "buy plan builds a buy order");
      g_kit.Check(req.magic == good.magic, "magic is propagated");

      const SRequestValidation v = CExecutionValidator::Local(req, good, spec, cfg);
      g_kit.Check(!v.ok, "analysisOnly config blocks execution validation");
      g_kit.Check(v.reason == QME_REJ_DISABLED_BY_CONFIG, "analysisOnly yields the config reason");
     }

   //--- inverted stop is refused locally
   STradePlan inverted = ExecPlan(spec, QME_SIDE_BUY);
   inverted.stopLoss = 1.10100;            // above entry for a buy
   MqlTradeRequest req2;
   string why2 = "";
   g_kit.Check(!CTradeRequestBuilder::Build(req2, inverted, spec, spec.fillingMask, 20, "QME", why2),
               "builder refuses an inverted buy stop");

   //--- idempotency: an intent can be claimed once, not twice
   CIdempotencyGuard guard;
   string idemWhy = "";
   g_kit.Check(guard.CanExecute("fp-1", idemWhy), "fresh intent may execute");
   g_kit.Check(guard.Begin("fp-1", TimeCurrent()), "intent claimed");
   g_kit.Check(!guard.CanExecute("fp-1", idemWhy), "in-flight intent is blocked");
   guard.Complete("fp-1", true, TimeCurrent());
   g_kit.Check(!guard.CanExecute("fp-1", idemWhy), "executed intent is blocked");
   g_kit.CheckEqual(guard.InFlightCount(), 0, "no intent left in flight");

   //--- a failed attempt may be retried by intent, not automatically
   g_kit.Check(guard.Begin("fp-2", TimeCurrent()), "second intent claimed");
   guard.Complete("fp-2", false, TimeCurrent());
   g_kit.Check(guard.CanExecute("fp-2", idemWhy), "failed intent may be re-evaluated");

   //--- idempotency survives a restart
   const string blob = guard.Serialize();
   CIdempotencyGuard restored;
   restored.Deserialize(blob);
   g_kit.Check(!restored.CanExecute("fp-1", idemWhy), "executed intent stays blocked after reload");
   g_kit.CheckEqual(restored.Count(), guard.Count(), "all intents restored");

   return(g_kit.End());
  }

#endif // __QME_TEST_EXECUTION_MQH__
//+------------------------------------------------------------------+
