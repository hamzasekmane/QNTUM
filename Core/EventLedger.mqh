//+------------------------------------------------------------------+
//|                                                 EventLedger.mqh  |
//|  QuantumMarketEngine — append-only record of decision events.       |
//|                                                                   |
//|  Purpose: every signal state change, rejection and execution is     |
//|  recorded with a monotonic id so the UI and the journal can prove   |
//|  the exact order of events after a restart.                        |
//|  OWNERSHIP: one instance owned by CEngine; optionally registered    |
//|  as an event sink.                                                 |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_EVENTLEDGER_MQH__
#define __QME_CORE_EVENTLEDGER_MQH__

#include "Constants.mqh"
#include "EventTypes.mqh"
#include "Logger.mqh"

class CEventLedger : public IQmeEventSink
  {
private:
   //--- parallel arrays (no structures containing strings in fixed arrays)
   ulong             m_id[QME_MAX_EVENT_QUEUE];
   datetime          m_time[QME_MAX_EVENT_QUEUE];
   int               m_type[QME_MAX_EVENT_QUEUE];
   int               m_reject[QME_MAX_EVENT_QUEUE];
   long              m_ref[QME_MAX_EVENT_QUEUE];
   string            m_symbol[QME_MAX_EVENT_QUEUE];
   string            m_text[QME_MAX_EVENT_QUEUE];
   int               m_count;
   int               m_head;
   ulong             m_seq;
   int               m_capacity;
   bool              m_verbose;

public:
                     CEventLedger(void) { Init(QME_MAX_EVENT_QUEUE, false); }
   void              Init(const int capacity, const bool verbose);
   void              Record(const ENUM_QME_EVENT type, const string symbol,
                            const long ref, const string text,
                            const ENUM_QME_REJECT reject = QME_REJ_NONE);
   //--- sink implementation
   virtual void      OnQmeEvent(const SQmeEvent &e);

   int               Count(void) { return(m_count); }
   ulong             LastId(void) { return(m_seq); }
   //--- i = 0 -> oldest retained record
   bool              At(const int i, ulong &id, datetime &time, int &type,
                        long &ref, string &symbol, string &text, int &reject);
   //--- i = 0 -> newest record
   bool              Recent(const int i, string &line);
   string            Export(const int maxLines = 200);
  };

//------------------------------------------------------------------//
void CEventLedger::Init(const int capacity, const bool verbose)
  {
   m_capacity = (capacity < 8) ? 8 : ((capacity > QME_MAX_EVENT_QUEUE) ? QME_MAX_EVENT_QUEUE : capacity);
   m_count = 0;
   m_head = 0;
   m_seq = 0;
   m_verbose = verbose;
   for(int i = 0; i < QME_MAX_EVENT_QUEUE; i++)
     {
      m_id[i] = 0;
      m_time[i] = 0;
      m_type[i] = QME_EVT_NONE;
      m_reject[i] = QME_REJ_NONE;
      m_ref[i] = 0;
      m_symbol[i] = "";
      m_text[i] = "";
     }
  }

//------------------------------------------------------------------//
void CEventLedger::Record(const ENUM_QME_EVENT type, const string symbol,
                          const long ref, const string text, const ENUM_QME_REJECT reject)
  {
   m_seq++;
   m_id[m_head] = m_seq;
   m_time[m_head] = TimeCurrent();
   m_type[m_head] = (int)type;
   m_reject[m_head] = (int)reject;
   m_ref[m_head] = ref;
   m_symbol[m_head] = symbol;
   m_text[m_head] = text;
   m_head = (m_head + 1) % m_capacity;
   if(m_count < m_capacity) m_count++;
   if(m_verbose)
      QmeLogMsg(QME_LOG_DEBUG, "Ledger", QmeEventName(type) + " " + symbol + " " + text);
  }

//------------------------------------------------------------------//
void CEventLedger::OnQmeEvent(const SQmeEvent &e)
  {
   Record(e.type, e.symbol, e.ref, e.text, e.reject);
  }

//------------------------------------------------------------------//
bool CEventLedger::At(const int i, ulong &id, datetime &time, int &type,
                      long &ref, string &symbol, string &text, int &reject)
  {
   id = 0; time = 0; type = QME_EVT_NONE; ref = 0; symbol = ""; text = ""; reject = QME_REJ_NONE;
   if(i < 0 || i >= m_count) return(false);
   const int start = (m_head - m_count + m_capacity * 2) % m_capacity;
   const int idx = (start + i) % m_capacity;
   id = m_id[idx];
   time = m_time[idx];
   type = m_type[idx];
   ref = m_ref[idx];
   symbol = m_symbol[idx];
   text = m_text[idx];
   reject = m_reject[idx];
   return(true);
  }

//------------------------------------------------------------------//
bool CEventLedger::Recent(const int i, string &line)
  {
   line = "";
   if(i < 0 || i >= m_count) return(false);
   const int idx = (m_head - 1 - i + m_capacity * 2) % m_capacity;
   line = "#" + IntegerToString((long)m_id[idx]) + " " +
          TimeToString(m_time[idx], TIME_MINUTES | TIME_SECONDS) + " " +
          QmeEventName((ENUM_QME_EVENT)m_type[idx]) + " " + m_symbol[idx] + " " + m_text[idx];
   return(true);
  }

//------------------------------------------------------------------//
string CEventLedger::Export(const int maxLines)
  {
   string s = "";
   const int n = (m_count < maxLines) ? m_count : maxLines;
   string line;
   for(int i = 0; i < n; i++)
     {
      if(!Recent(i, line)) break;
      s += line + "\n";
     }
   return(s);
  }

#endif // __QME_CORE_EVENTLEDGER_MQH__
//+------------------------------------------------------------------+
