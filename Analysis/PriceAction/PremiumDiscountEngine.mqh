//+------------------------------------------------------------------+
//|                       Analysis/PriceAction/PremiumDiscountEngine  |
//|  Premium / discount (equilibrium) context inside a dealing range.     |
//|                                                                   |
//|  The dealing range defaults to the last confirmed swing high/low,     |
//|  which is the structure the engine already trusts. It can also be     |
//|  supplied explicitly (e.g. previous day range).                      |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_PREMDISC_MQH__
#define __QME_ANALYSIS_PREMDISC_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

class CPremiumDiscountEngine
  {
public:
   static SRangeContext Evaluate(const double rangeLow, const double rangeHigh,
                                 const double price, const double equilibriumBand = 0.10);
   static SRangeContext FromStructure(const SStructureState &state, const double price,
                                      const double equilibriumBand = 0.10);
  };

//------------------------------------------------------------------//
SRangeContext CPremiumDiscountEngine::Evaluate(const double rangeLow, const double rangeHigh,
                                              const double price, const double equilibriumBand)
  {
   SRangeContext r;
   r.rangeHigh = rangeHigh;
   r.rangeLow = rangeLow;
   r.equilibrium = 0.5 * (rangeHigh + rangeLow);
   r.position = 0.5;
   r.premium = false;
   r.discount = false;
   r.valid = false;

   if(rangeHigh <= rangeLow || price <= 0.0) return(r);
   if(!QmeIsFinite(rangeLow) || !QmeIsFinite(rangeHigh)) return(r);

   r.position = QmeClamp((price - rangeLow) / (rangeHigh - rangeLow), 0.0, 1.0);

   const double band = QmeClamp(equilibriumBand, 0.0, 0.45);
   r.premium = (r.position > 0.5 + band);
   r.discount = (r.position < 0.5 - band);
   r.valid = true;
   return(r);
  }

//------------------------------------------------------------------//
SRangeContext CPremiumDiscountEngine::FromStructure(const SStructureState &state,
                                                    const double price,
                                                    const double equilibriumBand)
  {
   if(!state.valid)
     {
      SRangeContext empty;
      empty.rangeHigh = 0.0; empty.rangeLow = 0.0; empty.equilibrium = 0.0;
      empty.position = 0.5; empty.premium = false; empty.discount = false;
      empty.valid = false;
      return(empty);
     }
   return(Evaluate(state.lastSwingLow, state.lastSwingHigh, price, equilibriumBand));
  }

#endif // __QME_ANALYSIS_PREMDISC_MQH__
//+------------------------------------------------------------------+
