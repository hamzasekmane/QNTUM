//+------------------------------------------------------------------+
//|                                     Monitoring/HealthMonitor      |
//|  Turns scattered facts into one verdict: is the engine healthy?       |
//|                                                                   |
//|  Each check is independent and reports its own reason, so "unhealthy"  |
//|  is always explainable instead of a single opaque flag.               |
//+------------------------------------------------------------------+
#ifndef __QME_MON_HEALTH_MQH__
#define __QME_MON_HEALTH_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountContext.mqh"
#include "../Execution/PositionReconciler.mqh"

enum ENUM_QME_HEALTH
  {
   QME_HEALTH_OK = 0,
   QME_HEALTH_WARN,
   QME_HEALTH_CRITICAL
  };

struct SHealthReport
  {
   ENUM_QME_HEALTH   status;
   bool              accountOk;
   bool              permissionsOk;
   bool              dataFresh;
   bool              positionsProtected;
   bool              checkpointRecent;
   bool              errorsAcceptable;
   string            issues;
   datetime          time;
  };

void QmeHealthClear(SHealthReport &h)
  {
   h.status = QME_HEALTH_OK;
   h.accountOk = false; h.permissionsOk = false; h.dataFresh = false;
   h.positionsProtected = false; h.checkpointRecent = false; h.errorsAcceptable = false;
   h.issues = ""; h.time = 0;
  }

class CHealthMonitor
  {
public:
   static SHealthReport Evaluate(CAccountContext &account, const ulong magic,
                                 const datetime lastDataTime, const int dataTimeoutSec,
                                 const datetime lastCheckpoint, const int checkpointTimeoutSec,
                                 const long errorCount, const long errorThreshold);
   static string     StatusName(const ENUM_QME_HEALTH h);
  };

//------------------------------------------------------------------//
SHealthReport CHealthMonitor::Evaluate(CAccountContext &account, const ulong magic,
                                       const datetime lastDataTime, const int dataTimeoutSec,
                                       const datetime lastCheckpoint, const int checkpointTimeoutSec,
                                       const long errorCount, const long errorThreshold)
  {
   SHealthReport h;
   QmeHealthClear(h);
   h.time = TimeCurrent();

   const SAccountContext acc = account.Snapshot();
   h.accountOk = (acc.valid && acc.mode != QME_ACC_UNKNOWN);
   if(!h.accountOk) h.issues += "account;";

   h.permissionsOk = (acc.terminalTradeAllowed || acc.mode == QME_ACC_UNKNOWN);
   //--- TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) is authoritative
   h.permissionsOk = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   if(!h.permissionsOk) h.issues += "terminal-trading-disabled;";

   if(lastDataTime <= 0) h.dataFresh = false;
   else h.dataFresh = (h.time - lastDataTime) <= MathMax(dataTimeoutSec, 5);
   if(!h.dataFresh) h.issues += "data-stale;";

   const SReconcileReport rep = CPositionReconciler::Report(magic);
   h.positionsProtected = rep.consistent;
   if(!h.positionsProtected) h.issues += "unprotected-positions;";

   if(lastCheckpoint <= 0) h.checkpointRecent = false;
   else h.checkpointRecent = (h.time - lastCheckpoint) <= MathMax(checkpointTimeoutSec * 2, 60);
   if(!h.checkpointRecent) h.issues += "checkpoint-old;";

   h.errorsAcceptable = (errorCount < MathMax(errorThreshold, 1));
   if(!h.errorsAcceptable) h.issues += "error-threshold;";

   //--- verdict: any protective failure is critical, the rest are warnings
   if(!h.positionsProtected || !h.permissionsOk || !h.dataFresh)
      h.status = QME_HEALTH_CRITICAL;
   else if(!h.checkpointRecent || !h.errorsAcceptable || !h.accountOk)
      h.status = QME_HEALTH_WARN;
   else
      h.status = QME_HEALTH_OK;

   if(StringLen(h.issues) == 0) h.issues = "none";
   return(h);
  }

//------------------------------------------------------------------//
string CHealthMonitor::StatusName(const ENUM_QME_HEALTH h)
  {
   switch(h)
     {
      case QME_HEALTH_OK:       return("OK");
      case QME_HEALTH_WARN:     return("WARN");
      case QME_HEALTH_CRITICAL: return("CRITICAL");
     }
   return("?");
  }

#endif // __QME_MON_HEALTH_MQH__
//+------------------------------------------------------------------+
