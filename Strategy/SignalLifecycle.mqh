//+------------------------------------------------------------------+
//|                                    Strategy/SignalLifecycle       |
//|  The ONLY place a signal state may change.                          |
//|                                                                   |
//|  Legal transitions:                                                |
//|   DETECTED -> EVALUATING -> APPROVED -> EXECUTION_PENDING ->        |
//|   EXECUTED -> MONITORING -> CLOSED                                  |
//|   alternatives: REJECTED, EXPIRED, INVALIDATED, EXECUTION_FAILED,     |
//|   CANCELLED (all terminal)                                          |
//|  Any other transition is REFUSED and logged, never applied.           |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SIGNALLIFECYCLE_MQH__
#define __QME_STRATEGY_SIGNALLIFECYCLE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Core/EventLedger.mqh"
#include "SignalTypes.mqh"

class CSignalLifecycle
  {
private:
   CEventLedger     *m_ledger;
   long              m_refused;

public:
                     CSignalLifecycle(void) { m_ledger = NULL; m_refused = 0; }
   void              Attach(CEventLedger *ledger) { m_ledger = ledger; }

   static bool       Allowed(const ENUM_QME_SIGNAL_STATE from, const ENUM_QME_SIGNAL_STATE to);

   bool              Transition(STradingSignal &s, const ENUM_QME_SIGNAL_STATE to,
                                const ENUM_QME_REJECT reason, const string note,
                                const datetime now);
   long              Refused(void) { return(m_refused); }
  };

//------------------------------------------------------------------//
bool CSignalLifecycle::Allowed(const ENUM_QME_SIGNAL_STATE from, const ENUM_QME_SIGNAL_STATE to)
  {
   if(from == to) return(false);
   if(CSignalTypes::IsTerminal(from)) return(false);

   switch(from)
     {
      case QME_SIG_DETECTED:
         return(to == QME_SIG_EVALUATING || to == QME_SIG_REJECTED ||
                to == QME_SIG_EXPIRED || to == QME_SIG_CANCELLED);
      case QME_SIG_EVALUATING:
         return(to == QME_SIG_APPROVED || to == QME_SIG_REJECTED ||
                to == QME_SIG_EXPIRED || to == QME_SIG_CANCELLED);
      case QME_SIG_APPROVED:
         return(to == QME_SIG_EXECUTION_PENDING || to == QME_SIG_EXPIRED ||
                to == QME_SIG_CANCELLED || to == QME_SIG_REJECTED);
      case QME_SIG_EXECUTION_PENDING:
         return(to == QME_SIG_EXECUTED || to == QME_SIG_EXECUTION_FAILED ||
                to == QME_SIG_CANCELLED || to == QME_SIG_EXPIRED);
      case QME_SIG_EXECUTED:
         return(to == QME_SIG_MONITORING || to == QME_SIG_CLOSED ||
                to == QME_SIG_INVALIDATED);
      case QME_SIG_MONITORING:
         return(to == QME_SIG_CLOSED || to == QME_SIG_INVALIDATED);
     }
   return(false);
  }

//------------------------------------------------------------------//
bool CSignalLifecycle::Transition(STradingSignal &s, const ENUM_QME_SIGNAL_STATE to,
                                  const ENUM_QME_REJECT reason, const string note,
                                  const datetime now)
  {
   if(!Allowed(s.state, to))
     {
      m_refused++;
      QmeLogMsg(QME_LOG_WARN, "SignalLifecycle",
                "refused transition " + QmeSignalStateName(s.state) + " -> " +
                QmeSignalStateName(to) + " for signal #" + IntegerToString((long)s.id));
      return(false);
     }

   const ENUM_QME_SIGNAL_STATE from = s.state;
   s.state = to;
   s.updated = (now > 0) ? now : TimeCurrent();
   if(reason != QME_REJ_NONE) s.reject = reason;
   if(StringLen(note) > 0) s.rejectNote = note;

   //--- ledger entries (never silent)
   if(m_ledger != NULL)
     {
      ENUM_QME_EVENT evt = QME_EVT_SIGNAL_DETECTED;
      switch(to)
        {
         case QME_SIG_REJECTED:        evt = QME_EVT_SIGNAL_REJECTED; break;
         case QME_SIG_EXPIRED:         evt = QME_EVT_SIGNAL_EXPIRED;  break;
         case QME_SIG_APPROVED:        evt = QME_EVT_SIGNAL_APPROVED; break;
         case QME_SIG_EXECUTED:        evt = QME_EVT_POSITION_UPDATE; break;
         case QME_SIG_EXECUTION_FAILED:evt = QME_EVT_ERROR;           break;
         default:                      evt = QME_EVT_SIGNAL_DETECTED; break;
        }
      m_ledger.Record(evt, s.symbol, (long)s.id,
                      QmeSignalStateName(from) + "->" + QmeSignalStateName(to) +
                      (StringLen(note) > 0 ? ": " + note : ""), reason);
     }

   QmeLogMsg((to == QME_SIG_REJECTED || to == QME_SIG_EXECUTION_FAILED) ? QME_LOG_WARN : QME_LOG_INFO,
             "Signal", CSignalTypes::Describe(s) +
             " [" + QmeSignalStateName(from) + "->" + QmeSignalStateName(to) + "]" +
             (StringLen(note) > 0 ? " " + note : ""));
   return(true);
  }

#endif // __QME_STRATEGY_SIGNALLIFECYCLE_MQH__
//+------------------------------------------------------------------+
