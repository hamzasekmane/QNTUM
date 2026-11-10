//+------------------------------------------------------------------+
//|                                         Data/HistoryValidator     |
//|  QuantumMarketEngine — cross-timeframe history consistency.         |
//|                                                                   |
//|  A lower timeframe that stops before the higher timeframe's last     |
//|  closed bar indicates a broken feed or a symbol that is not fully    |
//|  downloaded. Such a symbol is skipped for the cycle instead of being |
//|  analysed on partial data.                                          |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_HISTORYVALIDATOR_MQH__
#define __QME_DATA_HISTORYVALIDATOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/HistoryGuard.mqh"
#include "../Core/Logger.mqh"
#include "TimeframeContext.mqh"

class CHistoryValidator
  {
public:
   //--- validate every provided context of one symbol; all must pass
   static bool       ValidateSymbol(CTimeframeContext *ctxs[], const ENUM_TIMEFRAMES tfs[],
                                    const int count, string &note);

   //--- compare just two contexts
   static bool       ValidatePair(CTimeframeContext &fast, CTimeframeContext &slow, string &note);

   //--- is the broker history fully downloaded for this context?
   static bool       IsSynced(const string symbol, const ENUM_TIMEFRAMES tf, string &note);
  };

//------------------------------------------------------------------//
bool CHistoryValidator::ValidateSymbol(CTimeframeContext *ctxs[], const ENUM_TIMEFRAMES tfs[],
                                       const int count, string &note)
  {
   note = "";
   if(count <= 0)
     {
      note = "no contexts";
      return(false);
     }
   for(int i = 0; i < count; i++)
     {
      if(ctxs[i] == NULL)
        {
         note = "null context at " + IntegerToString(i);
         return(false);
        }
      if(!ctxs[i].DataValid())
        {
         note = ctxs[i].Symbol() + " " + QmeTimeframeName(tfs[i]) + " data invalid: " +
                ctxs[i].LastError();
         return(false);
        }
     }
   //--- cross-timeframe ordering
   for(int i = 0; i + 1 < count; i++)
     {
      const datetime tFast = ctxs[i].LastBarTime();
      const datetime tSlow = ctxs[i + 1].LastBarTime();
      if(!QmeCrossTimeframeConsistent(tFast, tfs[i], tSlow, tfs[i + 1]))
        {
         note = "history not synchronised between " + QmeTimeframeName(tfs[i]) +
                " and " + QmeTimeframeName(tfs[i + 1]);
         return(false);
        }
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CHistoryValidator::ValidatePair(CTimeframeContext &fast, CTimeframeContext &slow, string &note)
  {
   note = "";
   if(!fast.DataValid() || !slow.DataValid())
     {
      note = "context data invalid";
      return(false);
     }
   if(!QmeCrossTimeframeConsistent(fast.LastBarTime(), fast.Timeframe(),
                                   slow.LastBarTime(), slow.Timeframe()))
     {
      note = QmeTimeframeName(fast.Timeframe()) + " history lags " +
             QmeTimeframeName(slow.Timeframe());
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CHistoryValidator::IsSynced(const string symbol, const ENUM_TIMEFRAMES tf, string &note)
  {
   note = "";
   const int flags = (int)SeriesInfoInteger(symbol, tf, SERIES_SYNCHRONIZED);
   if(flags == 0)
     {
      note = "series not synchronized for " + symbol + " " + QmeTimeframeName(tf);
      return(false);
     }
   const int bars = (int)SeriesInfoInteger(symbol, tf, SERIES_BARS_COUNT);
   if(bars < QME_MIN_BARS_REQUIRED)
     {
      note = "only " + IntegerToString(bars) + " bars available for " + symbol + " " +
             QmeTimeframeName(tf);
      return(false);
     }
   return(true);
  }

#endif // __QME_DATA_HISTORYVALIDATOR_MQH__
//+------------------------------------------------------------------+
