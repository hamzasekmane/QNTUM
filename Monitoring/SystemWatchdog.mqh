//+------------------------------------------------------------------+
//|                                    Monitoring/SystemWatchdog      |
//|  Detects a stalled or degraded engine and asks for a downgrade.       |
//|                                                                   |
//|  The watchdog does not trade. It observes three things that must      |
//|  never silently break: the cycle heartbeat, the data heartbeat and     |
//|  the error rate. It can only ever reduce activity (pause / fault),      |
//|  never resume it — resuming requires the operator.                    |
//+------------------------------------------------------------------+
#ifndef __QME_MON_WATCHDOG_MQH__
#define __QME_MON_WATCHDOG_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "ErrorTracker.mqh"

enum ENUM_QME_WATCH_ACTION
  {
   QME_WATCH_NONE = 0,
   QME_WATCH_WARN,
   QME_WATCH_PAUSE,
   QME_WATCH_FAULT
  };

struct SWatchdogVerdict
  {
   ENUM_QME_WATCH_ACTION action;
   string            reason;
   int               cycleAgeSec;
   int               dataAgeSec;
   long              errorCount;
  };

void QmeWatchdogClear(SWatchdogVerdict &v)
  {
   v.action = QME_WATCH_NONE;
   v.reason = "";
   v.cycleAgeSec = 0;
   v.dataAgeSec = 0;
   v.errorCount = 0;
  }

class CSystemWatchdog
  {
private:
   int               m_cycleTimeoutSec;
   int               m_dataTimeoutSec;
   long              m_errorLimit;
   ENUM_QME_WATCH_ACTION m_lastAction;
   long              m_triggers;

public:
                     CSystemWatchdog(void);
   void              Init(const int cycleTimeoutSec, const int dataTimeoutSec, const long errorLimit);
   SWatchdogVerdict  Evaluate(const datetime now, const datetime lastCycle,
                              const datetime lastData, CErrorTracker &errors);
   ENUM_QME_WATCH_ACTION LastAction(void) { return(m_lastAction); }
   long              Triggers(void) { return(m_triggers); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CSystemWatchdog::CSystemWatchdog(void)
  {
   m_cycleTimeoutSec = 180;
   m_dataTimeoutSec = 300;
   m_errorLimit = 50;
   m_lastAction = QME_WATCH_NONE;
   m_triggers = 0;
  }

void CSystemWatchdog::Init(const int cycleTimeoutSec, const int dataTimeoutSec, const long errorLimit)
  {
   m_cycleTimeoutSec = MathMax(cycleTimeoutSec, 30);
   m_dataTimeoutSec = MathMax(dataTimeoutSec, 60);
   m_errorLimit = MathMax(errorLimit, 5);
  }

//------------------------------------------------------------------//
SWatchdogVerdict CSystemWatchdog::Evaluate(const datetime now, const datetime lastCycle,
                                           const datetime lastData, CErrorTracker &errors)
  {
   SWatchdogVerdict v;
   QmeWatchdogClear(v);
   v.errorCount = errors.Total();

   if(now <= 0)
     {
      v.action = QME_WATCH_WARN;
      v.reason = "server time unavailable";
      return(v);
     }

   v.cycleAgeSec = (lastCycle > 0 && now > lastCycle) ? (int)(now - lastCycle) : 999999;
   v.dataAgeSec = (lastData > 0 && now > lastData) ? (int)(now - lastData) : 999999;

   //--- a dead cycle is a fault: nothing is being evaluated any more
   if(v.cycleAgeSec > m_cycleTimeoutSec * 3)
     {
      v.action = QME_WATCH_FAULT;
      v.reason = "engine cycle stalled for " + IntegerToString(v.cycleAgeSec) + "s";
     }
   else if(v.cycleAgeSec > m_cycleTimeoutSec)
     {
      v.action = QME_WATCH_PAUSE;
      v.reason = "engine cycle slow: " + IntegerToString(v.cycleAgeSec) + "s without a cycle";
     }
   else if(v.dataAgeSec > m_dataTimeoutSec)
     {
      v.action = QME_WATCH_PAUSE;
      v.reason = "market data stale for " + IntegerToString(v.dataAgeSec) + "s";
     }
   else if(v.errorCount > m_errorLimit)
     {
      v.action = QME_WATCH_PAUSE;
      v.reason = "error count " + IntegerToString((int)v.errorCount) + " > " +
                 IntegerToString((int)m_errorLimit);
     }
   else if(errors.Repeated(QME_ERRC_EXECUTION, 5) || errors.Repeated(QME_ERRC_PERSISTENCE, 3))
     {
      v.action = QME_WATCH_WARN;
      v.reason = "repeated execution or persistence failures";
     }

   if(v.action != m_lastAction)
     {
      m_lastAction = v.action;
      if(v.action != QME_WATCH_NONE)
        {
         m_triggers++;
         QmeLogMsg(QME_LOG_WARN, "Watchdog", v.reason);
        }
     }
   return(v);
  }

//------------------------------------------------------------------//
string CSystemWatchdog::Describe(void)
  {
   return("watchdog triggers=" + IntegerToString((int)m_triggers) +
          " cycleTimeout=" + IntegerToString(m_cycleTimeoutSec) + "s" +
          " dataTimeout=" + IntegerToString(m_dataTimeoutSec) + "s");
  }

#endif // __QME_MON_WATCHDOG_MQH__
//+------------------------------------------------------------------+
