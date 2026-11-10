//+------------------------------------------------------------------+
//|                                                   Profiler.mqh   |
//|  QuantumMarketEngine — per-section timing to prove the engine does |
//|  not repeat expensive work on every tick.                         |
//|  OWNERSHIP: one instance owned by CEngine (g_prof optional).       |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_PROFILER_MQH__
#define __QME_CORE_PROFILER_MQH__

#include "Constants.mqh"
#include "Utils.mqh"

class CProfiler
  {
private:
   bool              m_enabled;
   int               m_count;
   string            m_name[QME_MAX_PROFILER_SECTIONS];
   ulong             m_totalUs[QME_MAX_PROFILER_SECTIONS];
   ulong             m_maxUs[QME_MAX_PROFILER_SECTIONS];
   ulong             m_startUs[QME_MAX_PROFILER_SECTIONS];
   long              m_calls[QME_MAX_PROFILER_SECTIONS];
   bool              m_open[QME_MAX_PROFILER_SECTIONS];

public:
                     CProfiler(void) { Init(false); }
   void              Init(const bool enabled);
   void              Reset(void);
   void              Enable(const bool on) { m_enabled = on; }
   bool              Enabled(void) { return(m_enabled); }

   //--- returns the section index, creating it on first use (or -1)
   int               Section(const string name);
   void              Begin(const int idx);
   void              End(const int idx);

   double            AvgMs(const int idx);
   double            MaxMs(const int idx);
   long              Calls(const int idx);
   string            Name(const int idx);
   int               Count(void) { return(m_count); }
   string            Report(void);
  };

//------------------------------------------------------------------//
void CProfiler::Init(const bool enabled)
  {
   m_enabled = enabled;
   m_count = 0;
   for(int i = 0; i < QME_MAX_PROFILER_SECTIONS; i++)
     {
      m_name[i] = "";
      m_totalUs[i] = 0;
      m_maxUs[i] = 0;
      m_startUs[i] = 0;
      m_calls[i] = 0;
      m_open[i] = false;
     }
  }

//------------------------------------------------------------------//
void CProfiler::Reset(void)
  {
   for(int i = 0; i < m_count; i++)
     {
      m_totalUs[i] = 0;
      m_maxUs[i] = 0;
      m_calls[i] = 0;
      m_open[i] = false;
     }
  }

//------------------------------------------------------------------//
int CProfiler::Section(const string name)
  {
   for(int i = 0; i < m_count; i++)
      if(m_name[i] == name) return(i);
   if(m_count >= QME_MAX_PROFILER_SECTIONS)
      return(-1);
   m_name[m_count] = name;
   m_totalUs[m_count] = 0;
   m_maxUs[m_count] = 0;
   m_calls[m_count] = 0;
   m_open[m_count] = false;
   m_count++;
   return(m_count - 1);
  }

//------------------------------------------------------------------//
void CProfiler::Begin(const int idx)
  {
   if(!m_enabled || idx < 0 || idx >= m_count) return;
   m_startUs[idx] = GetMicrosecondCount();
   m_open[idx] = true;
  }

//------------------------------------------------------------------//
void CProfiler::End(const int idx)
  {
   if(!m_enabled || idx < 0 || idx >= m_count || !m_open[idx]) return;
   const ulong dt = GetMicrosecondCount() - m_startUs[idx];
   m_totalUs[idx] += dt;
   if(dt > m_maxUs[idx]) m_maxUs[idx] = dt;
   m_calls[idx]++;
   m_open[idx] = false;
  }

//------------------------------------------------------------------//
double CProfiler::AvgMs(const int idx)
  {
   if(idx < 0 || idx >= m_count || m_calls[idx] <= 0) return(0.0);
   return(0.001 * (double)m_totalUs[idx] / (double)m_calls[idx]);
  }

double CProfiler::MaxMs(const int idx)
  {
   if(idx < 0 || idx >= m_count) return(0.0);
   return(0.001 * (double)m_maxUs[idx]);
  }

long CProfiler::Calls(const int idx)
  {
   if(idx < 0 || idx >= m_count) return(0);
   return(m_calls[idx]);
  }

string CProfiler::Name(const int idx)
  {
   if(idx < 0 || idx >= m_count) return("");
   return(m_name[idx]);
  }

//------------------------------------------------------------------//
string CProfiler::Report(void)
  {
   string r = "";
   for(int i = 0; i < m_count; i++)
     {
      if(m_calls[i] <= 0) continue;
      r += m_name[i] + "=" + DoubleToString(AvgMs(i), 3) + "ms/" +
           IntegerToString((int)m_calls[i]) + " max=" + DoubleToString(MaxMs(i), 3) + "  ";
     }
   return(r);
  }

#endif // __QME_CORE_PROFILER_MQH__
//+------------------------------------------------------------------+
