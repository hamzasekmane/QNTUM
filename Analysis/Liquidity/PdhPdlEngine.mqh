//+------------------------------------------------------------------+
//|                              Analysis/Liquidity/PdhPdlEngine      |
//|  Previous day / previous week high and low — observed data only.    |
//|                                                                   |
//|  Source: the last COMPLETED D1 and W1 bar (shift 1). Never uses the  |
//|  day currently forming, so the levels cannot move intraday.         |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_PDHPDL_MQH__
#define __QME_ANALYSIS_PDHPDL_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Core/Logger.mqh"

struct SPdhPdl
  {
   double            pdh;
   double            pdl;
   double            pwh;
   double            pwl;
   datetime          dayBarTime;
   datetime          weekBarTime;
   bool              dayValid;
   bool              weekValid;
   bool              valid;
  };

class CPdhPdlEngine
  {
public:
   static bool       Evaluate(const string symbol, SPdhPdl &out);
  private:
   static bool       LastClosedBar(const string symbol, const ENUM_TIMEFRAMES tf,
                                   double &high, double &low, datetime &barTime);
  };

//------------------------------------------------------------------//
bool CPdhPdlEngine::LastClosedBar(const string symbol, const ENUM_TIMEFRAMES tf,
                                  double &high, double &low, datetime &barTime)
  {
   high = 0.0; low = 0.0; barTime = 0;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   //--- shift 1 = last completed bar of that timeframe
   const int copied = CopyRates(symbol, tf, 1, 1, rates);
   if(copied < 1)
      return(false);
   if(!QmeOhlcPlausible(rates[0].open, rates[0].high, rates[0].low, rates[0].close))
      return(false);
   high = rates[0].high;
   low = rates[0].low;
   barTime = rates[0].time;
   return(true);
  }

//------------------------------------------------------------------//
bool CPdhPdlEngine::Evaluate(const string symbol, SPdhPdl &out)
  {
   out.pdh = 0.0; out.pdl = 0.0; out.pwh = 0.0; out.pwl = 0.0;
   out.dayBarTime = 0; out.weekBarTime = 0;
   out.dayValid = false; out.weekValid = false;
   out.valid = false;

   datetime t = 0;
   out.dayValid = LastClosedBar(symbol, PERIOD_D1, out.pdh, out.pdl, t);
   out.dayBarTime = t;
   out.weekValid = LastClosedBar(symbol, PERIOD_W1, out.pwh, out.pwl, t);
   out.weekBarTime = t;

   out.valid = (out.dayValid || out.weekValid);
   return(out.valid);
  }

#endif // __QME_ANALYSIS_PDHPDL_MQH__
//+------------------------------------------------------------------+
