//+------------------------------------------------------------------+
//|                                 Execution/PositionReconciler      |
//|  Compares the engine's belief with the broker's actual positions.     |
//|                                                                   |
//|  The broker is always right. After an ambiguous send (timeout,        |
//|  disconnect) the engine MUST call this before re-sending anything.    |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_RECONCILER_MQH__
#define __QME_EXECUTION_RECONCILER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

struct SReconcileReport
  {
   int               brokerPositions;
   int               ownedPositions;
   int               withoutStop;
   double            ownedVolume;
   double            ownedRisk;
   bool              consistent;
   string            note;
  };

class CPositionReconciler
  {
public:
   static bool       FindPosition(const string symbol, const ulong magic,
                                  ulong &ticket, double &volume, double &openPrice,
                                  double &sl, double &tp);
   static int        CountOwned(const ulong magic);
   static SReconcileReport Report(const ulong magic);
   static bool       Exists(const ulong ticket);
  };

//------------------------------------------------------------------//
bool CPositionReconciler::FindPosition(const string symbol, const ulong magic,
                                       ulong &ticket, double &volume, double &openPrice,
                                       double &sl, double &tp)
  {
   ticket = 0; volume = 0.0; openPrice = 0.0; sl = 0.0; tp = 0.0;
   const int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      const ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(magic != 0 && (ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      ticket = t;
      volume = PositionGetDouble(POSITION_VOLUME);
      openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      return(true);
     }
   return(false);
  }

//------------------------------------------------------------------//
int CPositionReconciler::CountOwned(const ulong magic)
  {
   int n = 0;
   const int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      const ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(magic != 0 && (ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      n++;
     }
   return(n);
  }

//------------------------------------------------------------------//
bool CPositionReconciler::Exists(const ulong ticket)
  {
   if(ticket == 0) return(false);
   if(!PositionSelectByTicket(ticket)) return(false);
   return(true);
  }

//------------------------------------------------------------------//
SReconcileReport CPositionReconciler::Report(const ulong magic)
  {
   SReconcileReport r;
   r.brokerPositions = PositionsTotal();
   r.ownedPositions = 0;
   r.withoutStop = 0;
   r.ownedVolume = 0.0;
   r.ownedRisk = 0.0;
   r.consistent = true;
   r.note = "";

   for(int i = 0; i < r.brokerPositions; i++)
     {
      const ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!PositionSelectByTicket(t)) continue;
      if(magic != 0 && (ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      r.ownedPositions++;
      r.ownedVolume += PositionGetDouble(POSITION_VOLUME);
      const double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) r.withoutStop++;
     }

   if(r.withoutStop > 0)
     {
      r.consistent = false;
      r.note = IntegerToString(r.withoutStop) + " owned position(s) have no stop loss";
      QmeLogMsg(QME_LOG_ERROR, "Reconcile", r.note);
     }
   else
      r.note = IntegerToString(r.ownedPositions) + " owned position(s), all protected";

   return(r);
  }

#endif // __QME_EXECUTION_RECONCILER_MQH__
//+------------------------------------------------------------------+
