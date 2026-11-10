//+------------------------------------------------------------------+
//|                                       Risk/CorrelationRisk        |
//|  Prevents stacking the same directional bet on correlated symbols.   |
//|                                                                   |
//|  This is a HEURISTIC correlation model, not a statistical estimate:   |
//|   * same symbol                 -> 1.00                             |
//|   * FX pairs sharing a currency -> 0.60                             |
//|   * FX pairs with USD on the opposite side -> 0.50 (inverse)          |
//|   * same asset class            -> 0.50                             |
//|   * otherwise                   -> 0.10                             |
//|  The limit applies to the SUM of correlated notional in one direction.|
//+------------------------------------------------------------------+
#ifndef __QME_RISK_CORRELATION_MQH__
#define __QME_RISK_CORRELATION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Data/AssetClassTuning.mqh"
#include "PortfolioRisk.mqh"

class CCorrelationRisk
  {
private:
   static bool       IsFx(const string symbol);
   static bool       SharesCurrency(const string a, const string b);
   static bool       InverseUsd(const string a, const string b);

public:
   static double     Score(const string a, const string b);
   static bool       Check(const string symbol, const ENUM_QME_SIDE side,
                           const double addNotional, CPortfolioSnapshot &pf,
                           const double equity, const double maxCorrelatedPct,
                           string &why);
  };

//------------------------------------------------------------------//
bool CCorrelationRisk::IsFx(const string symbol)
  {
   return(CAssetClassTuning::Detect(symbol, "", "") == QME_ASSET_FX);
  }

bool CCorrelationRisk::SharesCurrency(const string a, const string b)
  {
   if(StringLen(a) < 6 || StringLen(b) < 6) return(false);
   const string a1 = StringSubstr(a, 0, 3);
   const string a2 = StringSubstr(a, 3, 3);
   const string b1 = StringSubstr(b, 0, 3);
   const string b2 = StringSubstr(b, 3, 3);
   return(a1 == b1 || a1 == b2 || a2 == b1 || a2 == b2);
  }

bool CCorrelationRisk::InverseUsd(const string a, const string b)
  {
   if(!IsFx(a) || !IsFx(b)) return(false);
   if(StringLen(a) < 6 || StringLen(b) < 6) return(false);
   const string aBase = StringSubstr(a, 0, 3);
   const string aQuote = StringSubstr(a, 3, 3);
   const string bBase = StringSubstr(b, 0, 3);
   const string bQuote = StringSubstr(b, 3, 3);
   //--- one is USD/XXX and the other is XXX/USD
   return((aBase == "USD" && bQuote == "USD") || (bBase == "USD" && aQuote == "USD"));
  }

//------------------------------------------------------------------//
double CCorrelationRisk::Score(const string a, const string b)
  {
   const string ua = QmeUpper(a);
   const string ub = QmeUpper(b);
   if(ua == ub) return(1.0);

   if(IsFx(ua) && IsFx(ub))
     {
      if(InverseUsd(ua, ub)) return(0.55);
      if(SharesCurrency(ua, ub)) return(0.60);
      return(0.25);
     }

   const ENUM_QME_ASSET ca = CAssetClassTuning::Detect(ua, "", "");
   const ENUM_QME_ASSET cb = CAssetClassTuning::Detect(ub, "", "");
   if(ca != QME_ASSET_UNKNOWN && ca == cb) return(0.50);
   return(0.10);
  }

//------------------------------------------------------------------//
bool CCorrelationRisk::Check(const string symbol, const ENUM_QME_SIDE side,
                             const double addNotional, CPortfolioSnapshot &pf,
                             const double equity, const double maxCorrelatedPct,
                             string &why)
  {
   why = "";
   if(maxCorrelatedPct <= 0.0 || equity <= 0.0) return(true);

   double correlated = addNotional;
   for(int i = 0; i < pf.Count(); i++)
     {
      SPositionRisk p;
      if(!pf.At(i, p)) continue;
      if(p.side != side) continue;                 // opposite direction hedges
      if(Score(symbol, p.symbol) < 0.49) continue; // weakly related: ignore
      correlated += p.notional;
     }

   const double pct = QmeSafePct(correlated, equity, 0.0);
   if(pct > maxCorrelatedPct)
     {
      why = "correlated " + QmeSideName(side) + " exposure " + QmeFmt(pct, 2) +
            "% > " + QmeFmt(maxCorrelatedPct, 2) + "%";
      return(false);
     }
   return(true);
  }

#endif // __QME_RISK_CORRELATION_MQH__
//+------------------------------------------------------------------+
