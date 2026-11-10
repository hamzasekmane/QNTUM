//+------------------------------------------------------------------+
//|                                                     Funnel.mqh   |
//|  QuantumMarketEngine — processing funnel accounting.               |
//|                                                                   |
//|  Every candidate that enters the pipeline is accounted for at each  |
//|  stage. This is how the engine proves it never silently drops a     |
//|  signal: symbols -> candidates -> scored -> risk-passed -> sent ->  |
//|  confirmed.                                                        |
//|  OWNERSHIP: one instance owned by CEngine (or by the Scanner).      |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_FUNNEL_MQH__
#define __QME_CORE_FUNNEL_MQH__

#include "Constants.mqh"
#include "Utils.mqh"

class CFunnel
  {
private:
   string            m_stage[QME_MAX_FUNNEL_STAGES];
   long              m_in[QME_MAX_FUNNEL_STAGES];
   long              m_out[QME_MAX_FUNNEL_STAGES];
   int               m_count;
   string            m_rejectName[QME_MAX_FUNNEL_STAGES];
   long              m_rejectCount[QME_MAX_FUNNEL_STAGES];
   int               m_rejectStages;
   datetime          m_cycleStart;

public:
                     CFunnel(void);
   void              Reset(void);
   int               Stage(const string name);
   void              Enter(const int idx);
   void              Pass(const int idx, const int n = 1);
   void              Drop(const int idx, const string reason, const int n = 1);
   long              In(const int idx);
   long              Out(const int idx);
   int               Count(void) { return(m_count); }
   string            StageName(const int idx);
   int               RejectCategories(void) { return(m_rejectStages); }
   bool              RejectAt(const int i, string &reason, long &count);
   string            Summary(void);
   void              CycleBegin(void) { m_cycleStart = TimeCurrent(); }
   datetime          CycleStart(void) { return(m_cycleStart); }
  };

//------------------------------------------------------------------//
CFunnel::CFunnel(void)
  {
   Reset();
  }

void CFunnel::Reset(void)
  {
   m_count = 0;
   m_rejectStages = 0;
   m_cycleStart = 0;
   for(int i = 0; i < QME_MAX_FUNNEL_STAGES; i++)
     {
      m_stage[i] = "";
      m_in[i] = 0;
      m_out[i] = 0;
      m_rejectName[i] = "";
      m_rejectCount[i] = 0;
     }
  }

//------------------------------------------------------------------//
int CFunnel::Stage(const string name)
  {
   for(int i = 0; i < m_count; i++)
      if(m_stage[i] == name) return(i);
   if(m_count >= QME_MAX_FUNNEL_STAGES) return(-1);
   m_stage[m_count] = name;
   m_in[m_count] = 0;
   m_out[m_count] = 0;
   m_count++;
   return(m_count - 1);
  }

void CFunnel::Enter(const int idx)
  {
   if(idx < 0 || idx >= m_count) return;
   m_in[idx]++;
  }

void CFunnel::Pass(const int idx, const int n)
  {
   if(idx < 0 || idx >= m_count) return;
   m_out[idx] += n;
  }

//------------------------------------------------------------------//
void CFunnel::Drop(const int idx, const string reason, const int n)
  {
   if(idx < 0 || idx >= m_count) return;
   //--- find or create the rejection reason slot
   for(int i = 0; i < m_rejectStages; i++)
     {
      if(m_rejectName[i] == reason)
        {
         m_rejectCount[i] += n;
         return;
        }
     }
   if(m_rejectStages >= QME_MAX_FUNNEL_STAGES) return;
   m_rejectName[m_rejectStages] = reason;
   m_rejectCount[m_rejectStages] = n;
   m_rejectStages++;
  }

long CFunnel::In(const int idx)
  {
   if(idx < 0 || idx >= m_count) return(0);
   return(m_in[idx]);
  }

long CFunnel::Out(const int idx)
  {
   if(idx < 0 || idx >= m_count) return(0);
   return(m_out[idx]);
  }

string CFunnel::StageName(const int idx)
  {
   if(idx < 0 || idx >= m_count) return("");
   return(m_stage[idx]);
  }

bool CFunnel::RejectAt(const int i, string &reason, long &count)
  {
   if(i < 0 || i >= m_rejectStages) return(false);
   reason = m_rejectName[i];
   count  = m_rejectCount[i];
   return(true);
  }

//------------------------------------------------------------------//
string CFunnel::Summary(void)
  {
   string r = "";
   for(int i = 0; i < m_count; i++)
      r += m_stage[i] + ":" + IntegerToString((int)m_out[i]) + "/" + IntegerToString((int)m_in[i]) + " ";
   if(m_rejectStages > 0)
     {
      r += "| rejects: ";
      for(int i = 0; i < m_rejectStages; i++)
         r += m_rejectName[i] + "=" + IntegerToString((int)m_rejectCount[i]) + " ";
     }
   return(r);
  }

#endif // __QME_CORE_FUNNEL_MQH__
//+------------------------------------------------------------------+
