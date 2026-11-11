//+------------------------------------------------------------------+
//|                                   Execution/ExecutionValidator    |
//|  Local validation + the broker's own OrderCheck.                     |
//|                                                                   |
//|  OrderCheck does NOT send an order: it asks the server whether the    |
//|  request would be accepted. Only when both local validation and       |
//|  OrderCheck pass may the gateway send.                                |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_VALIDATOR_MQH__
#define __QME_EXECUTION_VALIDATOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Account/BrokerCapabilities.mqh"

struct SRequestValidation
  {
   bool              ok;
   uint              retcode;
   int               lastError;
   ENUM_QME_REJECT   reason;
   string            comment;
  };

class CExecutionValidator
  {
public:
   static SRequestValidation Local(const MqlTradeRequest &req, const STradePlan &plan,
                                   const SSymbolSpec &spec, const CConfig &cfg);
   static SRequestValidation RequestRisk(const MqlTradeRequest &req, const STradePlan &plan,
                                         const double equity, const CConfig &cfg);
   static SRequestValidation OrderCheckServer(const MqlTradeRequest &req);
   static SRequestValidation Full(const MqlTradeRequest &req, const STradePlan &plan,
                                  const SSymbolSpec &spec, const CConfig &cfg);
  };

//------------------------------------------------------------------//
SRequestValidation CExecutionValidator::Local(const MqlTradeRequest &req, const STradePlan &plan,
                                              const SSymbolSpec &spec, const CConfig &cfg)
  {
   SRequestValidation v;
   v.ok = false;
   v.retcode = 0;
   v.lastError = 0;
   v.reason = QME_REJ_NONE;
   v.comment = "";

   //--- analysis-only is a HARD config block: it outranks every market or
   //--- geometry refusal, so the reported reason always names the real
   //--- restriction even when the request would also fail other checks
   if(cfg.In.analysisOnly)
     { v.reason = QME_REJ_DISABLED_BY_CONFIG; v.comment = "analysisOnly"; return(v); }

   if(StringLen(req.symbol) == 0) { v.reason = QME_REJ_INTERNAL; v.comment = "no symbol"; return(v); }
   if(req.volume <= 0.0) { v.reason = QME_REJ_VOLUME_INVALID; v.comment = "volume <= 0"; return(v); }
   if(!CSymbolSpecifications::VolumeInRange(spec, req.volume))
     {
      v.reason = QME_REJ_VOLUME_INVALID;
      v.comment = "volume " + QmeFmt(req.volume, 3) + " outside broker limits";
      return(v);
     }
   if(req.price <= 0.0) { v.reason = QME_REJ_INTERNAL; v.comment = "no price"; return(v); }

   //--- protective stops must be present and correctly placed
   if(req.sl <= 0.0) { v.reason = QME_REJ_SL_INVALID; v.comment = "request has no stop loss"; return(v); }
   if(req.tp <= 0.0) { v.reason = QME_REJ_TP_INVALID; v.comment = "request has no take profit"; return(v); }

   if(req.type == ORDER_TYPE_BUY || req.type == ORDER_TYPE_BUY_LIMIT ||
      req.type == ORDER_TYPE_BUY_STOP)
     {
      if(req.sl >= req.price) { v.reason = QME_REJ_SL_INVALID; v.comment = "buy stop above price"; return(v); }
      if(req.tp <= req.price) { v.reason = QME_REJ_TP_INVALID; v.comment = "buy target below price"; return(v); }
     }
   else
     {
      if(req.sl <= req.price) { v.reason = QME_REJ_SL_INVALID; v.comment = "sell stop below price"; return(v); }
      if(req.tp >= req.price) { v.reason = QME_REJ_TP_INVALID; v.comment = "sell target above price"; return(v); }
     }

   //--- broker stop distance (symbol stops level + freeze level are respected)
   const double minDist = MathMax(CSymbolSpecifications::MinStopDistance(spec), 0.0);
   if(minDist > 0.0)
     {
      if(MathAbs(req.price - req.sl) < minDist - QME_PRICE_EPS)
        {
         v.reason = QME_REJ_SL_INVALID;
         v.comment = "stop closer than the broker's stops level";
         return(v);
        }
      if(MathAbs(req.tp - req.price) < minDist - QME_PRICE_EPS)
        {
         v.reason = QME_REJ_TP_INVALID;
         v.comment = "target closer than the broker's stops level";
         return(v);
        }
     }

   //--- filling mode must be one the symbol reports
   if(req.action == TRADE_ACTION_DEAL)
     {
      const bool fok = ((spec.fillingMask & SYMBOL_FILLING_FOK) != 0);
      const bool ioc = ((spec.fillingMask & SYMBOL_FILLING_IOC) != 0);
      if(spec.fillingMask != 0)
        {
         if(req.type_filling == ORDER_FILLING_FOK && !fok)
           { v.reason = QME_REJ_BROKER_REJECTED; v.comment = "FOK not supported"; return(v); }
         if(req.type_filling == ORDER_FILLING_IOC && !ioc)
           { v.reason = QME_REJ_BROKER_REJECTED; v.comment = "IOC not supported"; return(v); }
        }
     }

   v.ok = true;
   return(v);
  }

//------------------------------------------------------------------//
SRequestValidation CExecutionValidator::RequestRisk(const MqlTradeRequest &req, const STradePlan &plan,
                                                    const double equity, const CConfig &cfg)
  {
   SRequestValidation v;
   v.ok = false; v.retcode = 0; v.lastError = 0; v.reason = QME_REJ_RISK_PER_TRADE;
   v.comment = "request risk unavailable";
   if(equity <= 0.0 || !QmeIsFinite(equity) || req.volume <= 0.0 ||
      req.price <= 0.0 || req.sl <= 0.0 || req.tp <= 0.0) return(v);
   if(plan.side != QME_SIDE_BUY && plan.side != QME_SIDE_SELL) return(v);
   if(!QmeStopIsValid(plan.side, req.price, req.sl) ||
      !QmeTargetIsValid(plan.side, req.price, req.tp)) return(v);

   const double rr = QmeComputeRR(plan.side, req.price, req.sl, req.tp);
   if(!QmeIsFinite(rr) || rr < cfg.In.minRR)
     {
      v.reason = QME_REJ_RR;
      v.comment = "request price no longer meets minimum reward:risk";
      return(v);
     }

   const ENUM_ORDER_TYPE direction = plan.side == QME_SIDE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double pnl = 0.0;
   if(!OrderCalcProfit(direction, req.symbol, req.volume, req.price, req.sl, pnl) ||
      !QmeIsFinite(pnl) || pnl >= 0.0)
     {
      v.comment = "broker could not calculate request stop loss in account currency";
      return(v);
     }
   const double budget = equity * cfg.In.riskPerTradePct / 100.0;
   if(!QmeIsFinite(budget) || budget <= 0.0 || -pnl > budget + 1e-8)
     {
      v.comment = "request stop loss exceeds current equity risk budget";
      return(v);
     }
   v.ok = true;
   v.reason = QME_REJ_NONE;
   v.comment = "request risk validated before send; costs and slippage not included";
   return(v);
  }

//------------------------------------------------------------------//
SRequestValidation CExecutionValidator::OrderCheckServer(const MqlTradeRequest &req)
  {
   SRequestValidation v;
   v.ok = false;
   v.retcode = 0;
   v.lastError = 0;
   v.reason = QME_REJ_NONE;
   v.comment = "";

   MqlTradeCheckResult check;
   ZeroMemory(check);
   if(!OrderCheck(req, check))
     {
      v.lastError = GetLastError();
      v.reason = QME_REJ_EXECUTION_FAILED;
      v.comment = "OrderCheck call failed (" + QmeLastErrorText() + ")";
      return(v);
     }

   v.retcode = check.retcode;
   v.comment = check.comment;
   if(!QmeRetcodeIsSuccess(check.retcode) && check.retcode != 0)
     {
      v.reason = QmeRejectFromRetcode(check.retcode);
      return(v);
     }
   v.ok = true;
   return(v);
  }

//------------------------------------------------------------------//
SRequestValidation CExecutionValidator::Full(const MqlTradeRequest &req, const STradePlan &plan,
                                             const SSymbolSpec &spec, const CConfig &cfg)
  {
   SRequestValidation v = Local(req, plan, spec, cfg);
   if(!v.ok) return(v);

   v = OrderCheckServer(req);
   return(v);
  }

#endif // __QME_EXECUTION_VALIDATOR_MQH__
//+------------------------------------------------------------------+
