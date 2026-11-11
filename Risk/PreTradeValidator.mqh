//+------------------------------------------------------------------+
//|                                    Risk/PreTradeValidator         |
//|  The complete pre-trade checklist. Every trade must pass it.          |
//|                                                                   |
//|  Order of checks (first failure wins, and is reported):               |
//|   1  configuration allows trading at all                             |
//|   2  plan is internally valid (volume, stop, target, RR)              |
//|   3  account mode is known and trading is authorized                  |
//|   4  terminal / expert / account permissions                          |
//|   5  symbol is tradable in this direction                             |
//|   6  broker session is open                                          |
//|   7  configured session is allowed                                    |
//|   8  news blackout                                                    |
//|   9  spread                                                            |
//|  10  risk per trade within budget                                     |
//|  11  daily loss guard                                                 |
//|  12  drawdown guard                                                   |
//|  13  consecutive loss guard                                           |
//|  14  concurrent positions / per-symbol duplicates                     |
//|  15  symbol + portfolio exposure                                      |
//|  16  correlation cluster                                              |
//|  17  margin                                                           |
//|  Every check increments checksRun; the assessment records the exact    |
//|  failing reason and the numeric value that failed.                     |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_PRETRADE_MQH__
#define __QME_RISK_PRETRADE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountState.mqh"
#include "../Account/SymbolSpecifications.mqh"
#include "../Account/BrokerCapabilities.mqh"
#include "../Account/MarginManager.mqh"
#include "../Account/TradingPermissions.mqh"
#include "RiskBudget.mqh"
#include "DailyLossGuard.mqh"
#include "DrawdownGuard.mqh"
#include "ConsecutiveLossGuard.mqh"
#include "ExposureManager.mqh"
#include "CorrelationRisk.mqh"
#include "PortfolioRisk.mqh"
#include "SpreadSessionGuard.mqh"
#include "NewsFilter.mqh"

class CPreTradeValidator
  {
public:
   static bool       Validate(STradePlan &plan, const SSymbolSpec &spec,
                              const SAccountContext &acc, CAccountState &state,
                              CPortfolioSnapshot &pf, const CConfig &cfg,
                              const ENUM_QME_SESSION session, const bool sessionAllowed,
                              const double atr, const double spreadPoints,
                              SRiskAssessment &out);
  private:
   static bool       Fail(SRiskAssessment &out, const ENUM_QME_REJECT reason,
                          const string note, const double detail);
  };

//------------------------------------------------------------------//
bool CPreTradeValidator::Fail(SRiskAssessment &out, const ENUM_QME_REJECT reason,
                              const string note, const double detail)
  {
   out.reason = reason;
   out.note = note;
   out.detail = detail;
   out.checksFailed++;
   out.passed = false;
   return(false);
  }

//------------------------------------------------------------------//
bool CPreTradeValidator::Validate(STradePlan &plan, const SSymbolSpec &spec,
                                  const SAccountContext &acc, CAccountState &state,
                                  CPortfolioSnapshot &pf, const CConfig &cfg,
                                  const ENUM_QME_SESSION session, const bool sessionAllowed,
                                  const double atr, const double spreadPoints,
                                  SRiskAssessment &out)
  {
   QmeRiskClear(out);
   out.checksRun = 0;
   out.checksFailed = 0;
   out.passed = false;
   out.reason = QME_REJ_NONE;

   //--- 1 configuration
   out.checksRun++;
   if(cfg.In.analysisOnly)
      return(Fail(out, QME_REJ_DISABLED_BY_CONFIG, "analysisOnly mode never trades", 0.0));

   //--- 2 plan validity (validated here so the risk layer has no strategy
   //--- dependency; the same rules are enforced by the plan builder)
   out.checksRun++;
   if(plan.signalId == 0 || StringLen(plan.symbol) == 0 || plan.side == QME_SIDE_NONE)
      return(Fail(out, QME_REJ_INTERNAL, "plan is missing identity", 0.0));
   if(plan.volume <= 0.0 || !CSymbolSpecifications::VolumeInRange(spec, plan.volume))
      return(Fail(out, QME_REJ_VOLUME_INVALID,
                  "volume " + QmeFmt(plan.volume, 3) + " is not valid for " + spec.symbol,
                  plan.volume));
   if(!QmeStopIsValid(plan.side, plan.entry, plan.stopLoss))
      return(Fail(out, QME_REJ_SL_INVALID, "protective stop is missing or invalid", 0.0));
   if(!QmeTargetIsValid(plan.side, plan.entry, plan.takeProfit))
      return(Fail(out, QME_REJ_TP_INVALID, "take profit is missing or invalid", 0.0));
   plan.rr = QmeComputeRR(plan.side, plan.entry, plan.stopLoss, plan.takeProfit);
   if(plan.rr < cfg.In.minRR)
      return(Fail(out, QME_REJ_RR, "rr " + QmeFmt(plan.rr, 2) + " < " +
                  QmeFmt(cfg.In.minRR, 2), plan.rr));

   out.volume = plan.volume;
   out.riskMoney = plan.riskMoney;
   out.rr = plan.rr;
   out.stopDistance = MathAbs(plan.entry - plan.stopLoss);
   out.slPoints = (spec.point > 0.0) ? out.stopDistance / spec.point : 0.0;
   out.spreadCost = spreadPoints * spec.point * plan.volume * QmeValuePerPriceUnit(spec);
   out.riskPct = CRiskBudget::RiskPctOfEquity(plan.riskMoney, acc.equity);

   //--- 3 account mode
   out.checksRun++;
   if(acc.mode == QME_ACC_UNKNOWN)
      return(Fail(out, QME_REJ_ACCOUNT_MODE, "account mode unknown", 0.0));
   if(!acc.valid)
      return(Fail(out, QME_REJ_ACCOUNT_PERMISSION, "account snapshot invalid", 0.0));

   //--- 4 permissions
   out.checksRun++;
   ENUM_QME_REJECT permReject = QME_REJ_NONE;
   string permNote = "";
   if(!CTradingPermissions::Authorize(cfg.In, acc, spec, plan.side, permReject, permNote))
      return(Fail(out, permReject, permNote, 0.0));

   //--- 5 symbol tradable
   out.checksRun++;
   string symWhy = "";
   if(!CSymbolSpecifications::IsTradable(spec, symWhy))
      return(Fail(out, QME_REJ_NOT_TRADABLE, symWhy, 0.0));

   //--- 6 broker session
   out.checksRun++;
   bool brokerOpen = true;
   string sessWhy = "";
   brokerOpen = CBrokerCapabilities::IsSessionOpen(spec.symbol, TimeTradeServer(), sessWhy);

   //--- 7/8 configured session + news
   ENUM_QME_REJECT sessReject = QME_REJ_NONE;
   string sessNote = "";
   out.checksRun++;
   if(!CSpreadSessionGuard::CheckSession(session, sessionAllowed, brokerOpen,
                                         cfg, sessReject, sessNote))
      return(Fail(out, sessReject, sessNote, 0.0));

   out.checksRun++;
   string newsWhy = "";
   if(CNewsFilter::Blocked(cfg, TimeGMT(), newsWhy))
      return(Fail(out, QME_REJ_NEWS_WINDOW, newsWhy, 0.0));

   //--- 9 spread
   out.checksRun++;
   ENUM_QME_REJECT spReject = QME_REJ_NONE;
   string spWhy = "";
   if(!CSpreadSessionGuard::CheckSpread(spreadPoints, atr, spec.point,
                                        cfg.In.maxSpreadPoints, cfg.In.maxSpreadAtrRatio,
                                        spReject, spWhy))
      return(Fail(out, spReject, spWhy, spreadPoints));

   //--- 10 risk per trade
   out.checksRun++;
   if(plan.riskMoney <= 0.0)
      return(Fail(out, QME_REJ_RISK_PER_TRADE, "risk amount is zero", 0.0));
   if(out.riskPct > cfg.In.riskPerTradePct + 1e-9)
      return(Fail(out, QME_REJ_RISK_PER_TRADE,
                  "risk " + QmeFmt(out.riskPct, 3) + "% > " +
                  QmeFmt(cfg.In.riskPerTradePct, 3) + "%", out.riskPct));

   //--- 11 daily loss
   out.checksRun++;
   double dailyPct = 0.0;
   string dailyWhy = "";
   if(!CDailyLossGuard::Check(acc, state, cfg.In.maxDailyLossPct, dailyPct, dailyWhy))
      return(Fail(out, QME_REJ_DAILY_LOSS, dailyWhy, dailyPct));
   out.dailyLossPct = dailyPct;

   //--- 12 drawdown
   out.checksRun++;
   double ddPct = 0.0;
   string ddWhy = "";
   if(!CDrawdownGuard::Check(acc, state, cfg.In.maxDrawdownPct, ddPct, ddWhy))
      return(Fail(out, QME_REJ_DRAWDOWN, ddWhy, ddPct));
   out.drawdownPct = ddPct;

   //--- 13 consecutive losses
   out.checksRun++;
   int streak = 0;
   string streakWhy = "";
   if(!CConsecutiveLossGuard::Check(state, cfg.In.maxConsecutiveLosses, streak, streakWhy))
      return(Fail(out, QME_REJ_CONSECUTIVE_LOSSES, streakWhy, (double)streak));
   out.consecutiveLosses = streak;

   // Until pending-order exposure and lifecycle are accounted for, do not
   // add risk while any account order remains active (including other EAs).
   out.checksRun++;
   if(OrdersTotal() > 0)
      return(Fail(out, QME_REJ_INTERNAL, "active orders require reconciliation", (double)OrdersTotal()));

   // The portfolio snapshot filters by magic. Refuse to trade rather than
   // silently omit another EA's or a manual position from account risk.
   out.checksRun++;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         return(Fail(out, QME_REJ_INTERNAL, "cannot inspect account position", 0.0));
      if((ulong)PositionGetInteger(POSITION_MAGIC) != cfg.In.magic)
         return(Fail(out, QME_REJ_INTERNAL, "foreign position not included in portfolio risk", (double)ticket));
     }

   //--- never open more risk when an owned position is unprotected or
   //--- the position snapshot could not be read completely.
   out.checksRun++;
   if(pf.ScanErrors() > 0)
      return(Fail(out, QME_REJ_INTERNAL, "portfolio snapshot incomplete", (double)pf.ScanErrors()));
   if(pf.WithoutStop() > 0)
      return(Fail(out, QME_REJ_SL_INVALID, "owned position without stop loss", (double)pf.WithoutStop()));

   //--- 14/15 exposure + duplicates
   out.checksRun++;
   out.positionsOpen = pf.Count();
   double symbolPct = 0.0, portfolioPct = 0.0;
   ENUM_QME_REJECT expReject = QME_REJ_NONE;
   string expWhy = "";
   if(!CExposureManager::Check(spec.symbol, spec, plan.side, plan.volume, plan.entry, pf,
                               acc.equity, cfg.In.maxPositions, cfg.In.maxPositionsPerSymbol,
                               cfg.In.maxSymbolExposurePct, cfg.In.maxPortfolioExposurePct,
                               symbolPct, portfolioPct, expReject, expWhy))
      return(Fail(out, expReject, expWhy, portfolioPct));
   out.exposureSymbolPct = symbolPct;
   out.exposurePortfolioPct = portfolioPct;

   //--- 16 correlation
   out.checksRun++;
   const double addNotional = CExposureManager::Notional(spec.symbol, plan.volume, plan.entry);
   string corrWhy = "";
   if(!CCorrelationRisk::Check(spec.symbol, plan.side, addNotional, pf, acc.equity,
                               cfg.In.maxPortfolioExposurePct, corrWhy))
      return(Fail(out, QME_REJ_CORRELATION, corrWhy, 0.0));

   //--- 17 margin
   out.checksRun++;
   const ENUM_ORDER_TYPE ot = (plan.side == QME_SIDE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double required = 0.0, freeAfter = 0.0;
   if(!CMarginManager::Check(spec.symbol, ot, plan.volume, plan.entry, 20.0, required, freeAfter))
      return(Fail(out, QME_REJ_MARGIN,
                  "insufficient free margin for " + QmeFmtMoney(required), required));
   out.marginRequired = required;
   out.marginFreeAfter = freeAfter;

   out.passed = true;
   out.reason = QME_REJ_NONE;
   out.note = "all " + IntegerToString(out.checksRun) + " checks passed";
   return(true);
  }

#endif // __QME_RISK_PRETRADE_MQH__
//+------------------------------------------------------------------+
