//+------------------------------------------------------------------+
//|                                    Runtime/ShutdownManager        |
//|  One ordered way to stop the engine.                                 |
//|                                                                   |
//|  Order matters: stop generating, persist, close files, then log.      |
//|  A half-stopped engine that lost its checkpoint is worse than one     |
//|  that kept running, so every step reports success and the summary      |
//|  records exactly what completed.                                    |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_SHUTDOWN_MQH__
#define __QME_RUNTIME_SHUTDOWN_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

struct SShutdownSummary
  {
   bool              requested;
   string            reason;
   datetime          requestedAt;
   bool              checkpointSaved;
   bool              journalFlushed;
   bool              positionsSafe;
   long              cycles;
   long              signals;
   long              trades;
   long              errors;
   string            note;
  };

void QmeShutdownClear(SShutdownSummary &s)
  {
   s.requested = false; s.reason = ""; s.requestedAt = 0;
   s.checkpointSaved = false; s.journalFlushed = false; s.positionsSafe = false;
   s.cycles = 0; s.signals = 0; s.trades = 0; s.errors = 0; s.note = "";
  }

class CShutdownManager
  {
private:
   SShutdownSummary  m_summary;

public:
                     CShutdownManager(void) { QmeShutdownClear(m_summary); }
   void              Request(const string reason);
   void              Cancel(void);
   bool              Requested(void) { return(m_summary.requested); }

   void              SetCounters(const long cycles, const long signals,
                                 const long trades, const long errors);
   void              MarkCheckpoint(const bool ok);
   void              MarkJournal(const bool ok);
   void              MarkPositions(const bool safe);

   SShutdownSummary  Summary(void) { return(m_summary); }
   string            Report(void);
  };

//------------------------------------------------------------------//
void CShutdownManager::Request(const string reason)
  {
   m_summary.requested = true;
   m_summary.reason = (StringLen(reason) > 0) ? reason : "requested";
   m_summary.requestedAt = TimeCurrent();
   QmeLogMsg(QME_LOG_INFO, "Shutdown", "shutdown requested: " + m_summary.reason);
  }

void CShutdownManager::Cancel(void)
  {
   m_summary.requested = false;
   m_summary.reason = "cancelled";
   QmeLogMsg(QME_LOG_INFO, "Shutdown", "shutdown cancelled");
  }

void CShutdownManager::SetCounters(const long cycles, const long signals,
                                   const long trades, const long errors)
  {
   m_summary.cycles = cycles;
   m_summary.signals = signals;
   m_summary.trades = trades;
   m_summary.errors = errors;
  }

void CShutdownManager::MarkCheckpoint(const bool ok) { m_summary.checkpointSaved = ok; }
void CShutdownManager::MarkJournal(const bool ok) { m_summary.journalFlushed = ok; }
void CShutdownManager::MarkPositions(const bool safe) { m_summary.positionsSafe = safe; }

//------------------------------------------------------------------//
string CShutdownManager::Report(void)
  {
   string s = "shutdown " + (m_summary.requested ? m_summary.reason : "clean") +
              " cycles=" + IntegerToString((int)m_summary.cycles) +
              " signals=" + IntegerToString((int)m_summary.signals) +
              " trades=" + IntegerToString((int)m_summary.trades) +
              " errors=" + IntegerToString((int)m_summary.errors) +
              " checkpoint=" + (m_summary.checkpointSaved ? "saved" : "not saved") +
              " journal=" + (m_summary.journalFlushed ? "flushed" : "not flushed") +
              " positions=" + (m_summary.positionsSafe ? "protected" : "CHECK");
   return(s);
  }

#endif // __QME_RUNTIME_SHUTDOWN_MQH__
//+------------------------------------------------------------------+
