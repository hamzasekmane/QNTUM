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
      if(m_state[i] != (int)QME_IDEM_FAILED) return(false);
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
   string fps[QME_MAX_FINGERPRINTS];
   datetime times[QME_MAX_FINGERPRINTS];
   int states[QME_MAX_FINGERPRINTS];
   int loaded = 0;
   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      if(loaded >= QME_MAX_FINGERPRINTS) return(false);
      string f[];
      const int fields = StringSplit(lines[i], ';', f);
      if(fields < 4 || f[0] != "idem") return(false);
      const long t = StringToInteger(f[1]);
      const long state = StringToInteger(f[2]);
      if(t <= 0 || IntegerToString(t) != f[1] ||
         state < (long)QME_IDEM_IN_FLIGHT || state > (long)QME_IDEM_FAILED ||
         IntegerToString(state) != f[2]) return(false);
      string fp = f[3];
      for(int k = 4; k < fields; k++) fp += ";" + f[k];
      if(StringLen(fp) == 0) return(false);
      for(int k = 0; k < loaded; k++) if(fps[k] == fp) return(false);
      fps[loaded] = fp;
      times[loaded] = (datetime)t;
      states[loaded] = (int)state;
      loaded++;
     }
   if(loaded == 0) return(false);
   Reset();
   for(int i = 0; i < loaded; i++)
     {
      m_fp[i] = fps[i];
      m_time[i] = times[i];
      m_state[i] = states[i];
     }
   m_count = loaded;
   return(true);
  }

#endif // __QME_EXECUTION_IDEMPOTENCY_MQH__
//+------------------------------------------------------------------+
