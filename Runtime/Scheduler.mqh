//+------------------------------------------------------------------+
//|                                            Runtime/Scheduler      |
//|  When may the engine do work?                                     |
//|                                                                   |
//|  The scheduler owns every cadence decision: how often the market is   |
//|  scanned, when a checkpoint is due, when the dashboard refreshes, and  |
//|  how long a symbol must rest after a signal. It never reads prices,     |
//|  so it can be unit-tested with fabricated clock values.               |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_SCHEDULER_MQH__
#define __QME_RUNTIME_SCHEDULER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

class CScheduler
  {
private:
   uint              m_scanIntervalMs;
   int               m_checkpointSec;
   int               m_dashboardSec;
   int               m_heartbeatSec;

   ulong             m_lastScanMs;
   datetime          m_lastCheckpoint;
   datetime          m_lastDashboard;
   datetime          m_lastHeartbeat;

   string            m_cooldownSymbol[QME_MAX_SYMBOLS];
   datetime          m_cooldownUntil[QME_MAX_SYMBOLS];
   int               m_cooldownCount;

   int               CooldownIndex(const string symbol);
   bool              TimerDue(datetime last, const int seconds, const datetime now);

public:
                     CScheduler(void);
   void              Init(const SInputs &in);
   void              Reset(void);

   bool              ScanDue(const datetime now);
   void              MarkScan(const datetime now);

   bool              CheckpointDue(const datetime now);
   void              MarkCheckpoint(const datetime now);

   bool              DashboardDue(const datetime now);
   void              MarkDashboard(const datetime now);

   bool              HeartbeatDue(const datetime now);
   void              MarkHeartbeat(const datetime now);

   void              Cooldown(const string symbol, const datetime now, const int seconds);
   bool              IsCooling(const string symbol, const datetime now);
   int               RemainingSeconds(const string symbol, const datetime now);

   string            Describe(void);
  };

//------------------------------------------------------------------//
CScheduler::CScheduler(void)
  {
   m_scanIntervalMs = 5000;
   m_checkpointSec = 30;
   m_dashboardSec = 2;
   m_heartbeatSec = 60;
   Reset();
  }

//------------------------------------------------------------------//
void CScheduler::Init(const SInputs &in)
  {
   m_scanIntervalMs = (uint)MathMax(in.scanIntervalMs, 250);
   m_checkpointSec = MathMax(in.checkpointSec, 5);
   m_dashboardSec = MathMax(in.dashboardRefreshSec, 1);
   m_heartbeatSec = 60;
   Reset();
  }

void CScheduler::Reset(void)
  {
   m_lastScanMs = 0;
   m_lastCheckpoint = 0;
   m_lastDashboard = 0;
   m_lastHeartbeat = 0;
   m_cooldownCount = 0;
  }

//------------------------------------------------------------------//
bool CScheduler::ScanDue(const datetime now)
  {
   if(now <= 0) return(false);
   const ulong nowMs = GetTickCount();
   if(m_lastScanMs == 0 || nowMs < m_lastScanMs) return(true);   // first call or wrap
   return((nowMs - m_lastScanMs) >= m_scanIntervalMs);
  }

void CScheduler::MarkScan(const datetime now) { m_lastScanMs = GetTickCount(); }

//------------------------------------------------------------------//
bool CScheduler::TimerDue(datetime last, const int seconds, const datetime now)
  {
   if(seconds <= 0) return(false);
   if(last == 0) return(true);
   if(now <= last) return(false);
   return((now - last) >= seconds);
  }

bool CScheduler::CheckpointDue(const datetime now)
  { return(TimerDue(m_lastCheckpoint, m_checkpointSec, now)); }
void CScheduler::MarkCheckpoint(const datetime now) { m_lastCheckpoint = now; }

bool CScheduler::DashboardDue(const datetime now)
  { return(TimerDue(m_lastDashboard, m_dashboardSec, now)); }
void CScheduler::MarkDashboard(const datetime now) { m_lastDashboard = now; }

bool CScheduler::HeartbeatDue(const datetime now)
  { return(TimerDue(m_lastHeartbeat, m_heartbeatSec, now)); }
void CScheduler::MarkHeartbeat(const datetime now) { m_lastHeartbeat = now; }

//------------------------------------------------------------------//
int CScheduler::CooldownIndex(const string symbol)
  {
   for(int i = 0; i < m_cooldownCount; i++)
      if(m_cooldownSymbol[i] == symbol) return(i);
   return(-1);
  }

void CScheduler::Cooldown(const string symbol, const datetime now, const int seconds)
  {
   if(StringLen(symbol) == 0 || seconds <= 0) return;
   const datetime until = now + seconds;
   const int i = CooldownIndex(symbol);
   if(i >= 0)
     {
      if(until > m_cooldownUntil[i]) m_cooldownUntil[i] = until;
      return;
     }
   if(m_cooldownCount >= QME_MAX_SYMBOLS) return;
   m_cooldownSymbol[m_cooldownCount] = symbol;
   m_cooldownUntil[m_cooldownCount] = until;
   m_cooldownCount++;
  }

bool CScheduler::IsCooling(const string symbol, const datetime now)
  {
   const int i = CooldownIndex(symbol);
   if(i < 0) return(false);
   return(now < m_cooldownUntil[i]);
  }

int CScheduler::RemainingSeconds(const string symbol, const datetime now)
  {
   const int i = CooldownIndex(symbol);
   if(i < 0) return(0);
   if(now >= m_cooldownUntil[i]) return(0);
   return((int)(m_cooldownUntil[i] - now));
  }

//------------------------------------------------------------------//
string CScheduler::Describe(void)
  {
   return("scheduler scanMs=" + IntegerToString((int)m_scanIntervalMs) +
          " checkpointSec=" + IntegerToString(m_checkpointSec) +
          " dashboardSec=" + IntegerToString(m_dashboardSec) +
          " cooldowns=" + IntegerToString(m_cooldownCount));
  }

#endif // __QME_RUNTIME_SCHEDULER_MQH__
//+------------------------------------------------------------------+
