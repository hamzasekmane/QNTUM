//+------------------------------------------------------------------+
//|                                Execution/IdempotencyGuard         |
//|  Prevents the same intent from being executed twice.                 |
//|                                                                   |
//|  States per fingerprint:                                          |
//|   NONE      -> never attempted                                     |
//|   IN_FLIGHT -> a request has been sent, outcome not yet known         |
//|   EXECUTED  -> broker confirmed a position for this intent            |
//|   FAILED    -> broker definitively rejected it (safe to re-evaluate)  |
//|  Only NONE and FAILED may be (re)executed. IN_FLIGHT blocks execution  |
//|  until reconciliation resolves it — this is what stops a restart or a   |
//|  repeated tick from double-firing.                                    |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_IDEMPOTENCY_MQH__
#define __QME_EXECUTION_IDEMPOTENCY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

enum ENUM_QME_IDEM_STATE
  {
   QME_IDEM_NONE = 0,
   QME_IDEM_IN_FLIGHT,
   QME_IDEM_EXECUTED,
   QME_IDEM_FAILED
  };

class CIdempotencyGuard
  {
private:
   string            m_fp[QME_MAX_FINGERPRINTS];
   datetime          m_time[QME_MAX_FINGERPRINTS];
   int               m_state[QME_MAX_FINGERPRINTS];
   int               m_count;
   int               Find(const string fp);

public:
                     CIdempotencyGuard(void) { Reset(); }
   void              Reset(void);

   ENUM_QME_IDEM_STATE State(const string fp);
   bool              CanExecute(const string fp, string &why);
   bool              Begin(const string fp, const datetime now);
   void              Complete(const string fp, const bool executed, const datetime now);
   void              Abort(const string fp);

   int               InFlightCount(void);
   int               Count(void) { return(m_count); }
   string            Serialize(void);
   bool              Deserialize(const string blob);
  };

//------------------------------------------------------------------//
void CIdempotencyGuard::Reset(void)
  {
   m_count = 0;
   for(int i = 0; i < QME_MAX_FINGERPRINTS; i++)
     {
      m_fp[i] = "";
      m_time[i] = 0;
      m_state[i] = (int)QME_IDEM_NONE;
     }
  }

int CIdempotencyGuard::Find(const string fp)
  {
   for(int i = 0; i < m_count; i++)
      if(m_fp[i] == fp) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
ENUM_QME_IDEM_STATE CIdempotencyGuard::State(const string fp)
  {
   const int i = Find(fp);
   if(i < 0) return(QME_IDEM_NONE);
   return((ENUM_QME_IDEM_STATE)m_state[i]);
  }

//------------------------------------------------------------------//
bool CIdempotencyGuard::CanExecute(const string fp, string &why)
  {
   why = "";
   if(StringLen(fp) == 0) { why = "empty fingerprint"; return(false); }
   switch(State(fp))
     {
      case QME_IDEM_NONE:
      case QME_IDEM_FAILED:
         return(true);
      case QME_IDEM_IN_FLIGHT:
         why = "an order for this intent is in flight and unresolved";
         return(false);
      case QME_IDEM_EXECUTED:
         why = "this intent has already been executed";
         return(false);
     }
   return(false);
  }

//------------------------------------------------------------------//
bool CIdempotencyGuard::Begin(const string fp, const datetime now)
  {
   if(StringLen(fp) == 0) return(false);
   const int i = Find(fp);
   if(i >= 0)
     {
      if(m_state[i] == (int)QME_IDEM_EXECUTED) return(false);
      m_state[i] = (int)QME_IDEM_IN_FLIGHT;
      m_time[i] = now;
      return(true);
     }
   if(m_count >= QME_MAX_FINGERPRINTS)
     {
      //--- evict the oldest FAILED record; never evict EXECUTED or IN_FLIGHT
      int victim = -1;
      datetime oldest = 0;
      for(int k = 0; k < m_count; k++)
        {
         if(m_state[k] != (int)QME_IDEM_FAILED) continue;
         if(victim < 0 || m_time[k] < oldest) { victim = k; oldest = m_time[k]; }
        }
      if(victim < 0)
        {
         QmeLogMsg(QME_LOG_ERROR, "Idempotency",
                   "guard full and no replaceable record: refusing execution");
         return(false);
        }
      m_fp[victim] = fp;
      m_time[victim] = now;
      m_state[victim] = (int)QME_IDEM_IN_FLIGHT;
      return(true);
     }
   m_fp[m_count] = fp;
   m_time[m_count] = now;
   m_state[m_count] = (int)QME_IDEM_IN_FLIGHT;
   m_count++;
   return(true);
  }

//------------------------------------------------------------------//
void CIdempotencyGuard::Complete(const string fp, const bool executed, const datetime now)
  {
   const int i = Find(fp);
   if(i < 0) return;
   m_state[i] = executed ? (int)QME_IDEM_EXECUTED : (int)QME_IDEM_FAILED;
   m_time[i] = now;
  }

void CIdempotencyGuard::Abort(const string fp)
  {
   const int i = Find(fp);
   if(i < 0) return;
   //--- an aborted attempt must be reconcilable: mark FAILED, never EXECUTED
   m_state[i] = (int)QME_IDEM_FAILED;
  }

//------------------------------------------------------------------//
int CIdempotencyGuard::InFlightCount(void)
  {
   int n = 0;
   for(int i = 0; i < m_count; i++)
      if(m_state[i] == (int)QME_IDEM_IN_FLIGHT) n++;
   return(n);
  }

//------------------------------------------------------------------//
string CIdempotencyGuard::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      if(StringLen(m_fp[i]) == 0) continue;
      s += "idem;" + IntegerToString((long)m_time[i]) + ";" +
           IntegerToString(m_state[i]) + ";" + m_fp[i] + "\n";
     }
   return(s);
  }

//------------------------------------------------------------------//
bool CIdempotencyGuard::Deserialize(const string blob)
  {
   if(StringLen(blob) == 0) return(false);
   Reset();
   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n && m_count < QME_MAX_FINGERPRINTS; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], ';', f) < 4) continue;
      if(f[0] != "idem") continue;
      m_time[m_count] = (datetime)StringToInteger(f[1]);
      m_state[m_count] = (int)StringToInteger(f[2]);
      m_fp[m_count] = f[3];
      m_count++;
      loaded++;
     }
   return(loaded > 0);
  }

#endif // __QME_EXECUTION_IDEMPOTENCY_MQH__
//+------------------------------------------------------------------+
