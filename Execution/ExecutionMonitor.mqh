//+------------------------------------------------------------------+
//|                                     Execution/ExecutionMonitor    |
//|  Live counters and the last execution fact.                          |
//|  Used by the dashboard and by the health check; it never decides      |
//|  anything, it only reports.                                        |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_MONITOR_MQH__
#define __QME_EXECUTION_MONITOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"

class CExecutionMonitor
  {
private:
   long              m_built;
   long              m_sent;
   long              m_confirmed;
   long              m_failed;
   long              m_unknown;
   long              m_rejectedLocal;
   long              m_retries;
   uint              m_lastRetcode;
   uint              m_lastCheckRetcode;
   string            m_lastSymbol;
   string            m_lastComment;
   datetime          m_lastTime;
   double            m_lastLatencyMs;
   ulong             m_lastPosition;

public:
                     CExecutionMonitor(void) { Reset(); }
   void              Reset(void);
   void              OnRequestBuilt(const string symbol);
   void              OnLocalReject(const string symbol, const string reason);
   void              OnSent(const string symbol, const double latencyMs);
   void              OnRetry(void);
   void              OnResult(const SExecutionResult &res, const double latencyMs);

   long              Sent(void) { return(m_sent); }
   long              Confirmed(void) { return(m_confirmed); }
   long              Failed(void) { return(m_failed); }
   long              Unknown(void) { return(m_unknown); }
   long              RejectedLocal(void) { return(m_rejectedLocal); }
   long              Retries(void) { return(m_retries); }
   uint              LastRetcode(void) { return(m_lastRetcode); }
   string            LastComment(void) { return(m_lastComment); }
   double            LastLatencyMs(void) { return(m_lastLatencyMs); }
   ulong             LastPosition(void) { return(m_lastPosition); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
void CExecutionMonitor::Reset(void)
  {
   m_built = 0; m_sent = 0; m_confirmed = 0; m_failed = 0; m_unknown = 0;
   m_rejectedLocal = 0; m_retries = 0;
   m_lastRetcode = 0; m_lastCheckRetcode = 0;
   m_lastSymbol = ""; m_lastComment = ""; m_lastTime = 0;
   m_lastLatencyMs = 0.0; m_lastPosition = 0;
  }

void CExecutionMonitor::OnRequestBuilt(const string symbol) { m_built++; m_lastSymbol = symbol; }
void CExecutionMonitor::OnLocalReject(const string symbol, const string reason)
  {
   m_rejectedLocal++;
   m_lastSymbol = symbol;
   m_lastComment = reason;
   m_lastTime = TimeCurrent();
  }
void CExecutionMonitor::OnSent(const string symbol, const double latencyMs)
  {
   m_sent++;
   m_lastSymbol = symbol;
   m_lastLatencyMs = latencyMs;
   m_lastTime = TimeCurrent();
  }
void CExecutionMonitor::OnRetry(void) { m_retries++; }

//------------------------------------------------------------------//
void CExecutionMonitor::OnResult(const SExecutionResult &res, const double latencyMs)
  {
   m_lastRetcode = res.retcode;
   m_lastCheckRetcode = res.orderCheckRetcode;
   m_lastComment = res.comment;
   m_lastTime = res.time > 0 ? res.time : TimeCurrent();
   m_lastLatencyMs = latencyMs;
   m_lastPosition = res.positionTicket;

   if(res.confirmed) m_confirmed++;
   else if(res.state == QME_EXEC_UNKNOWN_STATE) m_unknown++;
   else m_failed++;
  }

//------------------------------------------------------------------//
string CExecutionMonitor::Describe(void)
  {
   return("exec built=" + IntegerToString((int)m_built) +
          " sent=" + IntegerToString((int)m_sent) +
          " ok=" + IntegerToString((int)m_confirmed) +
          " failed=" + IntegerToString((int)m_failed) +
          " unknown=" + IntegerToString((int)m_unknown) +
          " localReject=" + IntegerToString((int)m_rejectedLocal) +
          " retries=" + IntegerToString((int)m_retries) +
          " latencyMs=" + QmeFmt(m_lastLatencyMs, 0) +
          " lastRetcode=" + IntegerToString((int)m_lastRetcode) +
          (StringLen(m_lastComment) > 0 ? " (" + m_lastComment + ")" : ""));
  }

#endif // __QME_EXECUTION_MONITOR_MQH__
//+------------------------------------------------------------------+
