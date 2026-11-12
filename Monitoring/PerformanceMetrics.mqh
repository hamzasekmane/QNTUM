//+------------------------------------------------------------------+
//|                                   Monitoring/PerformanceMetrics   |
//|  Cycle timing and throughput, measured, never estimated.              |
//+------------------------------------------------------------------+
#ifndef __QME_MON_PERFORMANCE_MQH__
#define __QME_MON_PERFORMANCE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Algorithms.mqh"
#include "../Runtime/AlgoContainers.mqh"

class CPerformanceMetrics
  {
private:
   CQmeRing          m_cycleMs;
   CQmeRing          m_scanMs;
   ulong             m_cycleStartUs;
   ulong             m_scanStartUs;
   long              m_cycles;
   long              m_slowCycles;
   long              m_cycleStatCount;
   double            m_cycleMeanMs;
   double            m_cycleM2Ms;
   double            m_cycleEwmaMs;
   bool              m_cycleEwmaReady;
   double            m_slowThresholdMs;

public:
                     CPerformanceMetrics(void) { Init(100, 250.0); }
   void              Init(const int ringSize, const double slowThresholdMs);
   void              CycleBegin(void);
   void              CycleEnd(void);
   void              ScanBegin(void);
   void              ScanEnd(const int symbols);

   long              Cycles(void) { return(m_cycles); }
   long              SlowCycles(void) { return(m_slowCycles); }
   double            LastCycleMs(void) { return(m_cycleMs.Last()); }
   double            AvgCycleMs(void) { return(m_cycleMs.Average()); }
   double            MaxCycleMs(void) { return(m_cycleMs.Maximum()); }
   double            CycleStdDevMs(void);
   double            CycleEwmaMs(void) { return(m_cycleEwmaReady ? m_cycleEwmaMs : 0.0); }
   double            AvgScanMs(void) { return(m_scanMs.Average()); }
   double            MsPerSymbol(void);
   string            Describe(void);
  };

//------------------------------------------------------------------//
void CPerformanceMetrics::Init(const int ringSize, const double slowThresholdMs)
  {
   m_cycleMs.Init(ringSize);
   m_scanMs.Init(ringSize);
   m_cycleStartUs = 0;
   m_scanStartUs = 0;
   m_cycles = 0;
   m_slowCycles = 0;
   m_cycleStatCount = 0;
   m_cycleMeanMs = 0.0;
   m_cycleM2Ms = 0.0;
   m_cycleEwmaMs = 0.0;
   m_cycleEwmaReady = false;
   m_slowThresholdMs = MathMax(slowThresholdMs, 1.0);
  }

void CPerformanceMetrics::CycleBegin(void) { m_cycleStartUs = GetMicrosecondCount(); }

//------------------------------------------------------------------//
void CPerformanceMetrics::CycleEnd(void)
  {
   if(m_cycleStartUs == 0) return;
   const double ms = (double)(GetMicrosecondCount() - m_cycleStartUs) / 1000.0;
   m_cycleStartUs = 0;
   m_cycleMs.Push(ms);
   //--- cumulative online variance for diagnostics only; never gates trading
   CQmeAlgorithms::WelfordPush(ms, m_cycleStatCount, m_cycleMeanMs, m_cycleM2Ms);
   CQmeAlgorithms::EwmaPush(ms, 0.2, m_cycleEwmaReady, m_cycleEwmaMs);
   m_cycles++;
   if(ms > m_slowThresholdMs) m_slowCycles++;
  }

void CPerformanceMetrics::ScanBegin(void) { m_scanStartUs = GetMicrosecondCount(); }

//------------------------------------------------------------------//
void CPerformanceMetrics::ScanEnd(const int symbols)
  {
   if(m_scanStartUs == 0) return;
   const double ms = (double)(GetMicrosecondCount() - m_scanStartUs) / 1000.0;
   m_scanStartUs = 0;
   m_scanMs.Push(ms);
  }

//------------------------------------------------------------------//
double CPerformanceMetrics::CycleStdDevMs(void)
  {
   double variance = 0.0;
   if(!CQmeAlgorithms::WelfordVariance(m_cycleStatCount, m_cycleM2Ms, true, variance))
      return(0.0);
   return(MathSqrt(variance));
  }

//------------------------------------------------------------------//
double CPerformanceMetrics::MsPerSymbol(void)
  {
   const double avg = m_scanMs.Average();
   if(avg <= 0.0) return(0.0);
   const int n = MathMax(1, (int)m_scanMs.Count());
   return(avg / n);
  }

//------------------------------------------------------------------//
string CPerformanceMetrics::Describe(void)
  {
   return("perf cycles=" + IntegerToString((int)m_cycles) +
          " avgMs=" + QmeFmt(m_cycleMs.Average(), 1) +
          " maxMs=" + QmeFmt(m_cycleMs.Maximum(), 1) +
          " cycleStdMs=" + QmeFmt(CycleStdDevMs(), 3) +
          " cycleEwmaMs=" + QmeFmt(CycleEwmaMs(), 3) +
          " slow=" + IntegerToString((int)m_slowCycles) +
          " scanAvgMs=" + QmeFmt(m_scanMs.Average(), 1));
  }

#endif // __QME_MON_PERFORMANCE_MQH__
//+------------------------------------------------------------------+
