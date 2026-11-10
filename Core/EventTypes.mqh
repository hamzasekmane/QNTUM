//+------------------------------------------------------------------+
//|                                                 EventTypes.mqh   |
//|  QuantumMarketEngine — event record + observer interface.          |
//|                                                                   |
//|  MQL5 has no function pointers, so the observer pattern is done    |
//|  with a pure-virtual interface. Sinks are registered by pointer    |
//|  and must be allocated with `new` by their owner.                  |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_EVENTTYPES_MQH__
#define __QME_CORE_EVENTTYPES_MQH__

#include "Constants.mqh"
#include "Enums.mqh"
#include "Utils.mqh"

struct SQmeEvent
  {
   ulong             id;        // monotonic sequence
   ENUM_QME_EVENT    type;
   datetime          time;
   string            symbol;
   long              ref;       // signal id / ticket / etc.
   double            value;     // free numeric payload
   string            text;      // free text payload
   ENUM_QME_REJECT   reject;
   ENUM_QME_SEVERITY severity;
  };

void QmeEventClear(SQmeEvent &e)
  {
   e.id = 0;
   e.type = QME_EVT_NONE;
   e.time = 0;
   e.symbol = "";
   e.ref = 0;
   e.value = 0.0;
   e.text = "";
   e.reject = QME_REJ_NONE;
   e.severity = QME_LOG_INFO;
  }

//+------------------------------------------------------------------+
//| Observer interface                                               |
//+------------------------------------------------------------------+
class IQmeEventSink
  {
public:
   virtual void      OnQmeEvent(const SQmeEvent &e) = 0;
  };

#endif // __QME_CORE_EVENTTYPES_MQH__
//+------------------------------------------------------------------+
