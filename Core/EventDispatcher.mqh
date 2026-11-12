//+------------------------------------------------------------------+
//|                                             EventDispatcher.mqh  |
//|  QuantumMarketEngine — routes queued events to registered sinks.   |
//|                                                                   |
//|  Filtering is per-sink and per-event-type (a boolean mask), so a    |
//|  sink is never woken for events it does not consume.               |
//|  OWNERSHIP: owns only REGISTRATIONS, never the sink objects.       |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_EVENTDISPATCHER_MQH__
#define __QME_CORE_EVENTDISPATCHER_MQH__

#include "Constants.mqh"
#include "EventTypes.mqh"
#include "EventBus.mqh"

class CEventDispatcher
  {
private:
   IQmeEventSink     *m_sinks[16];
   bool              m_filter[16][QME_EVT_COUNT];
   string            m_sinkName[16];
   int               m_sinkCount;
   long              m_delivered;
   long              m_dispatchCalls;

public:
                     CEventDispatcher(void);
   void              Reset(void);
   bool              AddSink(IQmeEventSink *sink, const string name);
   bool              Subscribe(const string name, const ENUM_QME_EVENT type);
   bool              SubscribeAll(const string name);

   //--- drain up to maxEvents from the bus and fan out
   int               Dispatch(CEventBus &bus, const int maxEvents = 128);
   long              Delivered(void) { return(m_delivered); }
   long              DispatchCalls(void) { return(m_dispatchCalls); }
   int               SinkCount(void) { return(m_sinkCount); }
   string            SinkName(const int i);
  };

//------------------------------------------------------------------//
CEventDispatcher::CEventDispatcher(void)
  {
   Reset();
  }

//------------------------------------------------------------------//
void CEventDispatcher::Reset(void)
  {
   m_sinkCount = 0;
   m_delivered = 0;
   m_dispatchCalls = 0;
   for(int i = 0; i < 16; i++)
     {
      m_sinks[i] = NULL;
      m_sinkName[i] = "";
      for(int t = 0; t < QME_EVT_COUNT; t++) m_filter[i][t] = false;
     }
  }

//------------------------------------------------------------------//
bool CEventDispatcher::AddSink(IQmeEventSink *sink, const string name)
  {
   if(sink == NULL) return(false);
   if(m_sinkCount >= 16) return(false);
   for(int i = 0; i < m_sinkCount; i++)
      if(m_sinkName[i] == name) return(false);   // duplicate registration
   m_sinks[m_sinkCount] = sink;
   m_sinkName[m_sinkCount] = name;
   m_sinkCount++;
   return(true);
  }

//------------------------------------------------------------------//
bool CEventDispatcher::Subscribe(const string name, const ENUM_QME_EVENT type)
  {
   if(type < 0 || type >= QME_EVT_COUNT) return(false);
   for(int i = 0; i < m_sinkCount; i++)
      if(m_sinkName[i] == name)
        {
         m_filter[i][(int)type] = true;
         return(true);
        }
   return(false);
  }

//------------------------------------------------------------------//
bool CEventDispatcher::SubscribeAll(const string name)
  {
   for(int i = 0; i < m_sinkCount; i++)
      if(m_sinkName[i] == name)
        {
         for(int t = 0; t < QME_EVT_COUNT; t++) m_filter[i][t] = true;
         return(true);
        }
   return(false);
  }

//------------------------------------------------------------------//
int CEventDispatcher::Dispatch(CEventBus &bus, const int maxEvents)
  {
   m_dispatchCalls++;
   int handled = 0;
   SQmeEvent e;
   while(handled < maxEvents && bus.Pop(e))
     {
      handled++;
      const int t = (int)e.type;
      if(t < 0 || t >= QME_EVT_COUNT) continue;
      for(int s = 0; s < m_sinkCount; s++)
        {
         if(!m_filter[s][t]) continue;
         if(m_sinks[s] == NULL) continue;
         m_sinks[s].OnQmeEvent(e);
         m_delivered++;
        }
     }
   return(handled);
  }

//------------------------------------------------------------------//
string CEventDispatcher::SinkName(const int i)
  {
   if(i < 0 || i >= m_sinkCount) return("");
   return(m_sinkName[i]);
  }

#endif // __QME_CORE_EVENTDISPATCHER_MQH__
//+------------------------------------------------------------------+
