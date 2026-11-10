//+------------------------------------------------------------------+
//|                                              Risk/RiskBudget      |
//|  Position sizing from risk in account currency.                     |
//|                                                                   |
//|  FORMULA (explicit, broker-driven, no magic numbers):                |
//|    valuePerPriceUnit = tickValue / tickSize        (account ccy, 1 lot)|
//|    lossPerLot        = stopDistance * valuePerPriceUnit               |
//|    rawVolume         = riskMoney / lossPerLot                         |
//|    volume            = floorToStep(rawVolume) inside [volMin, volMax] |
//|                                                                   |
//|  If any input is invalid (stop distance, tick value, tick size,       |
//|  volume limits) the result is 0.0 and the caller MUST reject the       |
//|  trade. Volume is never rounded up to force an order through.          |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_RISKBUDGET_MQH__
#define __QME_RISK_RISKBUDGET_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Account/SymbolSpecifications.mqh"

class CRiskBudget
  {
public:
   static double     RiskMoney(const SAccountContext &acc, const double riskPct);
   static double     LossPerLot(const SSymbolSpec &spec, const double stopDistance);
   static double     VolumeForRisk(const SSymbolSpec &spec, const double riskMoney,
                                   const double stopDistance);
   static double     ActualRiskMoney(const SSymbolSpec &spec, const double volume,
                                     const double stopDistance);
   static double     RiskPctOfEquity(const double riskMoney, const double equity);
  };

//------------------------------------------------------------------//
double CRiskBudget::RiskMoney(const SAccountContext &acc, const double riskPct)
  {
   if(acc.equity <= 0.0 || riskPct <= 0.0) return(0.0);
   return(acc.equity * riskPct / 100.0);
  }

//------------------------------------------------------------------//
double CRiskBudget::LossPerLot(const SSymbolSpec &spec, const double stopDistance)
  {
   const double perUnit = QmeValuePerPriceUnit(spec);
   if(perUnit <= 0.0 || stopDistance <= 0.0) return(0.0);
   return(stopDistance * perUnit);
  }

//------------------------------------------------------------------//
double CRiskBudget::VolumeForRisk(const SSymbolSpec &spec, const double riskMoney,
                                  const double stopDistance)
  {
   if(riskMoney <= 0.0 || stopDistance <= 0.0) return(0.0);
   const double lossPerLot = LossPerLot(spec, stopDistance);
   if(lossPerLot <= 0.0) return(0.0);

   const double raw = riskMoney / lossPerLot;
   if(!QmeIsFinite(raw) || raw <= 0.0) return(0.0);

   //--- NormalizeVolume rounds DOWN to the volume step and returns 0.0 when
   //--- the result is below the broker minimum, which the caller treats as
   //--- "cannot size this trade" rather than "trade the minimum anyway".
   const double v = CSymbolSpecifications::NormalizeVolume(spec, raw);
   if(v <= 0.0) return(0.0);
   if(!CSymbolSpecifications::VolumeInRange(spec, v)) return(0.0);
   return(v);
  }

//------------------------------------------------------------------//
double CRiskBudget::ActualRiskMoney(const SSymbolSpec &spec, const double volume,
                                    const double stopDistance)
  {
   const double lossPerLot = LossPerLot(spec, stopDistance);
   if(lossPerLot <= 0.0) return(0.0);
   return(lossPerLot * volume);
  }

//------------------------------------------------------------------//
double CRiskBudget::RiskPctOfEquity(const double riskMoney, const double equity)
  {
   return(QmeSafePct(riskMoney, equity, 0.0));
  }

#endif // __QME_RISK_RISKBUDGET_MQH__
//+------------------------------------------------------------------+
