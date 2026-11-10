//+------------------------------------------------------------------+
//|                                                    EventBus.mqh  |
//|  QuantumMarketEngine — bounded FIFO event queue.                   |
//|                                                                   |
//|  The bus never allocates unbounded memory: when full, the OLDEST    |
//|  event is dropped and the overflow is counted and reported.        |
//|  OWNERSHIP: one instance owned by CEngine.                         |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_EVENTBUS_MQH__
#define __QME_CORE_EVENTBUS_MQH__

#include "Constants.mqh"
#include "EventTypes.mqh"

class CEventBus
  {
private:
   SQmeEvent         m_queue[QME_MAX_EVENT_QUEUE];
   int               m_head;
   int               m_tail;
   int               m_count;
   ulong             m_seq;
   long              m_byType[QME_EVT_COUNT];
   long              m_dropped;

public:
                     CEventBus(void);
   void              Reset(void);

   //--- enqueue; the caller supplies type/time/symbol/payload
   ulong             Publish(const ENUM_QME_EVENT type, const string symbol,
                             const long ref, const double value, const string text,
                             const ENUM_QME_SEVERITY sev = QME_LOG_INFO,
                             const ENUM_QME_REJECT reject = QME_REJ_NONE);

   bool              IsEmpty(void) { return(m_count == 0); }
   int               Count(void) { return(m_count); }
   bool              Pop(SQmeEvent &out);
   long              Published(const ENUM_QME_EVENT type);
   long              Dropped(void) { return(m_dropped); }
  };

//------------------------------------------------------------------//
CEventBus::CEventBus(void)
  {
   Reset();
  }

void CEventBus::Reset(void)
  {
   m_head = 0;
   m_tail = 0;
   m_count = 0;
   m_seq = 0;
   m_dropped = 0;
   for(int i = 0; i < QME_MAX_EVENT_QUEUE; i++) QmeEventClear(m_queue[i]);
   for(int i = 0; i < QME_EVT_COUNT; i++) m_byType[i] = 0;
  }

//------------------------------------------------------------------//
ulong CEventBus::Publish(const ENUM_QME_EVENT type, const string symbol,
                         const long ref, const double value, const string text,
                         const ENUM_QME_SEVERITY sev, const ENUM_QME_REJECT reject)
  {
   if(m_count >= QME_MAX_EVENT_QUEUE)
     {
      //--- drop the oldest event, keep the newest information
      m_head = (m_head + 1) % QME_MAX_EVENT_QUEUE;
      m_count--;
      m_dropped++;
     }
   m_seq++;
   SQmeEvent e;
   e.id = m_seq;
   e.type = type;
   e.time = TimeCurrent();
   e.symbol = symbol;
   e.ref = ref;
   e.value = value;
   e.text = text;
   e.reject = reject;
   e.severity = sev;
   m_queue[m_tail] = e;
   m_tail = (m_tail + 1) % QME_MAX_EVENT_QUEUE;
   m_count++;
   if(type >= 0 && type < QME_EVT_COUNT) m_byType[(int)type]++;
   return(m_seq);
  }

//------------------------------------------------------------------//
bool CEventBus::Pop(SQmeEvent &out)
  {
   if(m_count <= 0) return(false);
   out = m_queue[m_head];
   m_head = (m_head + 1) % QME_MAX_EVENT_QUEUE;
   m_count--;
   return(true);
  }

//------------------------------------------------------------------//
long CEventBus::Published(const ENUM_QME_EVENT type)
  {
   if(type < 0 || type >= QME_EVT_COUNT) return(0);
   return(m_byType[(int)type]);
  }

#endif // __QME_CORE_EVENTBUS_MQH__
//+------------------------------------------------------------------+
