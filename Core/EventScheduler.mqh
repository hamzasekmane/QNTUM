//+------------------------------------------------------------------+
//|                                             EventScheduler.mqh   |
//|  QuantumMarketEngine — named periodic tasks.                       |
//|                                                                   |
//|  The engine never fat-loops the terminal: every repetitive task     |
//|  (scan, dashboard, health, checkpoint) is registered here with an   |
//|  interval and only reported due when the interval has elapsed.      |
//|  OWNERSHIP: one instance owned by CEngine.                          |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_EVENTSCHEDULER_MQH__
#define __QME_CORE_EVENTSCHEDULER_MQH__

#include "Constants.mqh"
#include "Utils.mqh"

class CEventScheduler
  {
private:
   string            m_name[QME_MAX_PROFILER_SECTIONS];
   int               m_intervalMs[QME_MAX_PROFILER_SECTIONS];
   ulong             m_lastRunMs[QME_MAX_PROFILER_SECTIONS];
   long              m_runs[QME_MAX_PROFILER_SECTIONS];
   bool              m_enabled[QME_MAX_PROFILER_SECTIONS];
   int               m_count;
   bool              m_started;

   int               Find(const string name);

public:
                     CEventScheduler(void);
   void              Reset(void);
   int               Add(const string name, const int intervalMs, const bool enabled = true);
   bool              SetInterval(const string name, const int intervalMs);
   bool              SetEnabled(const string name, const bool enabled);

   //--- true at most once per interval; marks the task as run
   bool              Due(const string name);
   //--- has the interval elapsed without consuming the trigger?
   bool              IsDue(const string name);
   //--- force the next Due() to return true
   void              Kick(const string name);

   void              MarkAllRun(void);
   long              Runs(const string name);
   int               Count(void) { return(m_count); }
   string            Name(const int i);
  };

//------------------------------------------------------------------//
CEventScheduler::CEventScheduler(void)
  {
   Reset();
  }

void CEventScheduler::Reset(void)
  {
   m_count = 0;
   m_started = true;
   for(int i = 0; i < QME_MAX_PROFILER_SECTIONS; i++)
     {
      m_name[i] = "";
      m_intervalMs[i] = 0;
      m_lastRunMs[i] = 0;
      m_runs[i] = 0;
      m_enabled[i] = false;
     }
  }

int CEventScheduler::Find(const string name)
  {
   for(int i = 0; i < m_count; i++)
      if(m_name[i] == name) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
int CEventScheduler::Add(const string name, const int intervalMs, const bool enabled)
  {
   const int existing = Find(name);
   if(existing >= 0)
     {
      m_intervalMs[existing] = intervalMs;
      m_enabled[existing] = enabled;
      return(existing);
     }
   if(m_count >= QME_MAX_PROFILER_SECTIONS) return(-1);
   m_name[m_count] = name;
   m_intervalMs[m_count] = (intervalMs < 1) ? 1 : intervalMs;
   m_lastRunMs[m_count] = 0;
   m_runs[m_count] = 0;
   m_enabled[m_count] = enabled;
   m_count++;
   return(m_count - 1);
  }

bool CEventScheduler::SetInterval(const string name, const int intervalMs)
  {
   const int i = Find(name);
   if(i < 0) return(false);
   m_intervalMs[i] = (intervalMs < 1) ? 1 : intervalMs;
   return(true);
  }

bool CEventScheduler::SetEnabled(const string name, const bool enabled)
  {
   const int i = Find(name);
   if(i < 0) return(false);
   m_enabled[i] = enabled;
   return(true);
  }

//------------------------------------------------------------------//
bool CEventScheduler::IsDue(const string name)
  {
   const int i = Find(name);
   if(i < 0 || !m_enabled[i]) return(false);
   const ulong nowMs = GetTickCount();
   if(m_lastRunMs[i] == 0) return(true);
   return((nowMs - m_lastRunMs[i]) >= (ulong)m_intervalMs[i]);
  }

//------------------------------------------------------------------//
bool CEventScheduler::Due(const string name)
  {
   const int i = Find(name);
   if(i < 0 || !m_enabled[i]) return(false);
   const ulong nowMs = GetTickCount();
   if(m_lastRunMs[i] != 0 && (nowMs - m_lastRunMs[i]) < (ulong)m_intervalMs[i])
      return(false);
   m_lastRunMs[i] = nowMs;
   m_runs[i]++;
   return(true);
  }

//------------------------------------------------------------------//
void CEventScheduler::Kick(const string name)
  {
   const int i = Find(name);
   if(i < 0) return;
   m_lastRunMs[i] = 0;
  }

void CEventScheduler::MarkAllRun(void)
  {
   const ulong nowMs = GetTickCount();
   for(int i = 0; i < m_count; i++)
      m_lastRunMs[i] = nowMs;
  }

long CEventScheduler::Runs(const string name)
  {
   const int i = Find(name);
   if(i < 0) return(0);
   return(m_runs[i]);
  }

string CEventScheduler::Name(const int i)
  {
   if(i < 0 || i >= m_count) return("");
   return(m_name[i]);
  }

#endif // __QME_CORE_EVENTSCHEDULER_MQH__
//+------------------------------------------------------------------+
