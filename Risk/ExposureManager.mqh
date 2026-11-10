//+------------------------------------------------------------------+
//|                                       Risk/ExposureManager        |
//|  Position-count and notional-exposure limits.                        |
//|                                                                   |
//|  Notional is approximated as volume * contractSize * price. That is   |
//|  exact for CFDs/stocks and a consistent approximation for FX; the     |
//|  limits are expressed as a percentage of equity, so they behave the    |
//|  same way on every broker.                                          |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_EXPOSURE_MQH__
#define __QME_RISK_EXPOSURE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "PortfolioRisk.mqh"

class CExposureManager
  {
public:
   static double     Notional(const string symbol, const double volume, const double price);
   static bool       Check(const string symbol, const SSymbolSpec &spec,
                           const ENUM_QME_SIDE side, const double volume,
                           const double price, CPortfolioSnapshot &pf,
                           const double equity, const int maxPositions,
                           const int maxPerSymbol, const double maxSymbolPct,
                           const double maxPortfolioPct,
                           double &symbolPct, double &portfolioPct,
                           ENUM_QME_REJECT &reason, string &why);
  };

//------------------------------------------------------------------//
double CExposureManager::Notional(const string symbol, const double volume, const double price)
  {
   const double contract = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract <= 0.0 || volume <= 0.0 || price <= 0.0) return(0.0);
   return(volume * contract * price);
  }

//------------------------------------------------------------------//
bool CExposureManager::Check(const string symbol, const SSymbolSpec &spec,
                             const ENUM_QME_SIDE side, const double volume,
                             const double price, CPortfolioSnapshot &pf,
                             const double equity, const int maxPositions,
                             const int maxPerSymbol, const double maxSymbolPct,
                             const double maxPortfolioPct,
                             double &symbolPct, double &portfolioPct,
                             ENUM_QME_REJECT &reason, string &why)
  {
   symbolPct = 0.0;
   portfolioPct = 0.0;
   reason = QME_REJ_NONE;
   why = "";

   if(equity <= 0.0)
     {
      reason = QME_REJ_INTERNAL;
      why = "account equity is not available";
      return(false);
     }
   if(volume <= 0.0)
     {
      reason = QME_REJ_VOLUME_INVALID;
      why = "volume is zero";
      return(false);
     }

   //--- 1. concurrent positions
   if(pf.Count() >= maxPositions)
     {
      reason = QME_REJ_MAX_POSITIONS;
      why = "already " + IntegerToString(pf.Count()) + " open positions (max " +
            IntegerToString(maxPositions) + ")";
      return(false);
     }

   //--- 2. duplicate position on the same symbol/side
   if(pf.CountFor(symbol) >= maxPerSymbol)
     {
      reason = QME_REJ_DUPLICATE_POSITION;
      why = "already " + IntegerToString(pf.CountFor(symbol)) + " position(s) on " + symbol;
      return(false);
     }
   if(pf.CountFor(symbol, side) > 0)
     {
      reason = QME_REJ_DUPLICATE_POSITION;
      why = "a " + QmeSideName(side) + " position already exists on " + symbol;
      return(false);
     }

   //--- 3. symbol exposure
   const double addNotional = Notional(symbol, volume, price);
   if(addNotional <= 0.0)
     {
      //--- some brokers do not report contract size: skip the notional limit
      //--- but say so instead of silently passing
      why = "notional unavailable for " + symbol + " (contract size not reported)";
      return(true);
     }

   const double symbolNotional = pf.NotionalFor(symbol) + addNotional;
   const double totalNotional  = pf.TotalNotional() + addNotional;
   symbolPct = QmeSafePct(symbolNotional, equity, 0.0);
   portfolioPct = QmeSafePct(totalNotional, equity, 0.0);

   if(maxSymbolPct > 0.0 && symbolPct > maxSymbolPct)
     {
      reason = QME_REJ_SYMBOL_EXPOSURE;
      why = "symbol exposure " + QmeFmt(symbolPct, 2) + "% > " + QmeFmt(maxSymbolPct, 2) + "%";
      return(false);
     }
   if(maxPortfolioPct > 0.0 && portfolioPct > maxPortfolioPct)
     {
      reason = QME_REJ_PORTFOLIO_EXPOSURE;
      why = "portfolio exposure " + QmeFmt(portfolioPct, 2) + "% > " +
            QmeFmt(maxPortfolioPct, 2) + "%";
      return(false);
     }
   return(true);
  }

#endif // __QME_RISK_EXPOSURE_MQH__
//+------------------------------------------------------------------+
