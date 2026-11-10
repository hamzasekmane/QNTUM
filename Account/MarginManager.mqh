//+------------------------------------------------------------------+
//|                                         Account/MarginManager.mqh |
//|  QuantumMarketEngine — margin requirement + free-margin gate.      |
//|                                                                   |
//|  Interface:                                                       |
//|    bool Required(symbol, type, volume, price, double &margin)       |
//|    bool Check(spec, type, volume, price, bufferPct, SRiskAssessment)|
//|  Uses the terminal's own calculation (OrderCalcMargin) so the       |
//|  broker's leverage/margin rules are respected, not approximated.    |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_MARGIN_MQH__
#define __QME_ACCOUNT_MARGIN_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"

class CMarginManager
  {
public:
   static bool       Required(const string symbol, const ENUM_ORDER_TYPE type,
                              const double volume, const double price, double &margin);
   static double     FreeMargin(void);
   static double     MarginLevel(void);

   //--- margin gate: required margin must fit in free margin after a buffer
   static bool       Check(const string symbol, const ENUM_ORDER_TYPE type,
                           const double volume, const double price,
                           const double bufferPct, double &required, double &freeAfter);
  };

//------------------------------------------------------------------//
bool CMarginManager::Required(const string symbol, const ENUM_ORDER_TYPE type,
                              const double volume, const double price, double &margin)
  {
   margin = 0.0;
   if(volume <= 0.0 || price <= 0.0) return(false);
   const bool ok = OrderCalcMargin(type, symbol, volume, price, margin);
   if(!ok || !QmeIsFinite(margin) || margin < 0.0)
     {
      margin = 0.0;
      QmeLogMsg(QME_LOG_WARN, "Margin", "OrderCalcMargin failed for " + symbol +
                " volume=" + QmeFmt(volume, 2) + " (" + QmeLastErrorText() + ")");
      return(false);
     }
   return(true);
  }

double CMarginManager::FreeMargin(void)  { return(AccountInfoDouble(ACCOUNT_MARGIN_FREE)); }
double CMarginManager::MarginLevel(void) { return(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)); }

//------------------------------------------------------------------//
bool CMarginManager::Check(const string symbol, const ENUM_ORDER_TYPE type,
                           const double volume, const double price,
                           const double bufferPct, double &required, double &freeAfter)
  {
   required = 0.0;
   freeAfter = 0.0;
   if(!Required(symbol, type, volume, price, required))
      return(false);
   const double free = FreeMargin();
   if(free <= 0.0) return(false);
   const double buffer = free * QmeClamp(bufferPct, 0.0, 90.0) / 100.0;
   freeAfter = free - required;
   return(freeAfter > buffer);
  }

#endif // __QME_ACCOUNT_MARGIN_MQH__
//+------------------------------------------------------------------+
