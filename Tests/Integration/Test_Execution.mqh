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

   g_kit.Check(COrderManager::IsUnresolvedAcceptance(TRADE_RETCODE_PLACED), "placed order requires reconciliation");
   g_kit.Check(COrderManager::IsUnresolvedAcceptance(TRADE_RETCODE_DONE_PARTIAL), "partial fill requires reconciliation");
   g_kit.Check(!COrderManager::IsUnresolvedAcceptance(TRADE_RETCODE_DONE), "done is not classified as partial or placed");
   g_kit.Check(CExecutionGateway::SupportsEntryType(QME_ENTRY_MARKET), "market entry is supported");
   g_kit.Check(!CExecutionGateway::SupportsEntryType(QME_ENTRY_LIMIT), "limit entry is blocked");
   g_kit.Check(!CExecutionGateway::SupportsEntryType(QME_ENTRY_STOP), "stop entry is blocked");

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
   const bool built = CTradeRequestBuilder::Build(req, noStop, spec,
                                                  CBrokerCapabilities::ChooseFilling(spec, ORDER_TYPE_BUY), 20,
                                                  "QME", buildWhy);
   g_kit.Check(!built, "builder refuses a plan without a stop");
   g_kit.Check(StringLen(buildWhy) > 0, "builder explains the refusal");

   //--- a valid plan builds a request with both protections
   STradePlan good = ExecPlan(spec, QME_SIDE_BUY);
   if(!CTradeRequestBuilder::Build(req, good, spec,
                                   CBrokerCapabilities::ChooseFilling(spec, ORDER_TYPE_BUY), 20, "QME", buildWhy))
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

   //--- precedence: with analysisOnly on, even a request that would fail
   //--- several other checks must report the CONFIG reason, not a later one
     {
      MqlTradeRequest bad;
      ZeroMemory(bad);
      bad.symbol = _Symbol;
      bad.volume = -1.0;      // also invalid volume
      bad.sl = 0.0;           // also missing stop
      bad.price = 0.0;        // also missing price
      const SRequestValidation pv = CExecutionValidator::Local(bad, good, spec, cfg);
      g_kit.Check(!pv.ok, "multi-fault request is refused in analysisOnly");
      g_kit.Check(pv.reason == QME_REJ_DISABLED_BY_CONFIG,
                  "config reason outranks simultaneous faults");
     }

   //--- inverted stop is refused locally
   STradePlan inverted = ExecPlan(spec, QME_SIDE_BUY);
   inverted.stopLoss = 1.10100;            // above entry for a buy
   MqlTradeRequest req2;
   string why2 = "";
   g_kit.Check(!CTradeRequestBuilder::Build(req2, inverted, spec,
                                            CBrokerCapabilities::ChooseFilling(spec, ORDER_TYPE_BUY),
                                            20, "QME", why2),
               "builder refuses an inverted buy stop");

   //--- request risk validation rejects invalid inputs before broker calls
   MqlTradeRequest riskReq;
   ZeroMemory(riskReq);
   riskReq.symbol = spec.symbol;
   riskReq.volume = 0.1;
   riskReq.price = 1.10000;
   riskReq.sl = 1.09800;
   riskReq.tp = 1.10010; // RR is far below the configured minimum
   SRequestValidation riskResult = CExecutionValidator::RequestRisk(riskReq, good, 10000.0, cfg);
   g_kit.Check(!riskResult.ok && riskResult.reason == QME_REJ_RR,
               "request quote below minimum RR is blocked");
   riskResult = CExecutionValidator::RequestRisk(riskReq, good, 0.0, cfg);
   g_kit.Check(!riskResult.ok, "request risk requires positive equity");
   riskReq.tp = 1.10400;
   riskReq.symbol = "QME_NONEXISTENT_TEST_SYMBOL";
   riskResult = CExecutionValidator::RequestRisk(riskReq, good, 10000.0, cfg);
   g_kit.Check(!riskResult.ok, "unavailable broker loss calculation fails closed");

   //--- compare against the broker calculation without ever sending an order
   MqlTick riskTick;
   double brokerPnl = 0.0;
   MqlTradeRequest brokerReq;
   ZeroMemory(brokerReq);
   brokerReq.symbol = spec.symbol;
   brokerReq.volume = spec.volMin;
   if(SymbolInfoTick(spec.symbol, riskTick) && riskTick.ask > 0.0 && spec.tickSize > 0.0)
     {
      brokerReq.price = riskTick.ask;
      brokerReq.sl = riskTick.ask - 100.0 * spec.tickSize;
      brokerReq.tp = riskTick.ask + 300.0 * spec.tickSize;
     }
   if(brokerReq.sl > 0.0 && OrderCalcProfit(ORDER_TYPE_BUY, brokerReq.symbol, brokerReq.volume,
                                             brokerReq.price, brokerReq.sl, brokerPnl) && brokerPnl < 0.0)
     {
      const double breakEvenEquity = (-brokerPnl) * 100.0 / cfg.In.riskPerTradePct;
      riskResult = CExecutionValidator::RequestRisk(brokerReq, good, breakEvenEquity * 2.0, cfg);
      g_kit.Check(riskResult.ok, "broker-calculated loss inside budget passes");
      riskResult = CExecutionValidator::RequestRisk(brokerReq, good, breakEvenEquity * 0.5, cfg);
      g_kit.Check(!riskResult.ok && riskResult.reason == QME_REJ_RISK_PER_TRADE,
                  "broker-calculated loss above budget is refused");
     }
   else
      g_kit.Skip("broker profit calculation unavailable for request-risk test");

   //--- idempotency: an intent can be claimed once, not twice
   CIdempotencyGuard guard;
   string idemWhy = "";
   g_kit.Check(guard.CanExecute("fp-1", idemWhy), "fresh intent may execute");
   g_kit.Check(guard.Begin("fp-1", TimeCurrent()), "intent claimed");
   g_kit.Check(!guard.CanExecute("fp-1", idemWhy), "in-flight intent is blocked");
   g_kit.Check(!guard.Begin("fp-1", TimeCurrent()), "in-flight claim cannot be overwritten");
   CIdempotencyGuard unresolved;
   g_kit.Check(unresolved.Deserialize(guard.Serialize()), "in-flight claim can be restored");
   g_kit.Check(!unresolved.CanExecute("fp-1", idemWhy), "restored in-flight intent remains blocked");
   g_kit.Check(!unresolved.Begin("fp-1", TimeCurrent()), "restored claim cannot be overwritten");
   g_kit.Check(!unresolved.Deserialize("idem;1000;0;fp-1\n"), "invalid persisted state rejected");
   g_kit.Check(!unresolved.CanExecute("fp-1", idemWhy), "invalid restore preserves held claim");
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
