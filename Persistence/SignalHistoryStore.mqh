//+------------------------------------------------------------------+
//|                                Persistence/SignalHistoryStore     |
//|  Bounded history of every signal the engine produced.                |
//|                                                                   |
//|  The history is what makes the engine auditable after a restart:      |
//|  what was generated, what the engine decided, and why it ended.       |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_SIGNALHISTORY_MQH__
#define __QME_PERSIST_SIGNALHISTORY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Strategy/SignalTypes.mqh"
#include "StateSerializer.mqh"

struct SSignalRecord
  {
   ulong                  id;
   string                 symbol;
   ENUM_QME_SIDE          side;
   ENUM_QME_SIGNAL_STATE  finalState;
   ENUM_QME_REJECT        reason;
   double                 score;
   double                 rr;
   datetime               opened;
   datetime               closed;
   string                 fingerprint;
  };

class CSignalHistoryStore
  {
private:
   SSignalRecord     m_items[QME_MAX_HISTORY];
   int               m_count;
   int               m_next;
   long              m_dropped;
   int               IndexOf(const ulong id);

public:
                     CSignalHistoryStore(void) { Reset(); }
   void              Reset(void) { m_count = 0; m_next = 0; m_dropped = 0; }

   void              Add(const SSignalRecord &r);
   bool              At(const int i, SSignalRecord &out);
   bool              Get(const ulong id, SSignalRecord &out);
   int               Count(void) { return(m_count); }
   long              Dropped(void) { return(m_dropped); }
   int               CountInState(const ENUM_QME_SIGNAL_STATE st);
   int               CountRejected(void);
   double            AverageScore(void);
   double            AverageRR(void);

   string            Serialize(void);
   bool              Deserialize(const string blob);
   string            Describe(void);
  };

//------------------------------------------------------------------//
int CSignalHistoryStore::IndexOf(const ulong id)
  {
   for(int i = 0; i < m_count; i++)
      if(m_items[i].id == id) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
void CSignalHistoryStore::Add(const SSignalRecord &r)
  {
   if(r.id == 0) return;
   const int existing = IndexOf(r.id);
   if(existing >= 0)
     {
      m_items[existing] = r;   // keep the latest state of the same signal
      return;
     }

   if(m_count < QME_MAX_HISTORY)
     {
      m_items[m_count] = r;
      m_count++;
      m_next = (m_count % QME_MAX_HISTORY);
      return;
     }

   //--- ring buffer: overwrite the oldest slot and count the loss
   m_items[m_next] = r;
   m_next = (m_next + 1) % QME_MAX_HISTORY;
   m_dropped++;
  }

bool CSignalHistoryStore::At(const int i, SSignalRecord &out)
  {
   if(i < 0 || i >= m_count) return(false);
   out = m_items[i];
   return(true);
  }

bool CSignalHistoryStore::Get(const ulong id, SSignalRecord &out)
  {
   const int i = IndexOf(id);
   if(i < 0) return(false);
   out = m_items[i];
   return(true);
  }

int CSignalHistoryStore::CountInState(const ENUM_QME_SIGNAL_STATE st)
  {
   int n = 0;
   for(int i = 0; i < m_count; i++)
      if(m_items[i].finalState == st) n++;
   return(n);
  }

int CSignalHistoryStore::CountRejected(void)
  {
   int n = 0;
   for(int i = 0; i < m_count; i++)
      if(m_items[i].reason != QME_REJ_NONE) n++;
   return(n);
  }

double CSignalHistoryStore::AverageScore(void)
  {
   if(m_count == 0) return(0.0);
   double s = 0.0;
   for(int i = 0; i < m_count; i++) s += m_items[i].score;
   return(s / m_count);
  }

double CSignalHistoryStore::AverageRR(void)
  {
   if(m_count == 0) return(0.0);
   double s = 0.0;
   for(int i = 0; i < m_count; i++) s += m_items[i].rr;
   return(s / m_count);
  }

//------------------------------------------------------------------//
string CSignalHistoryStore::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      const SSignalRecord r = m_items[i];
      s += "sig|" + IntegerToString((long)r.id) + "|" +
           CStateSerializer::Escape(r.symbol) + "|" +
           QmeSideName(r.side) + "|" +
           IntegerToString((int)r.finalState) + "|" +
           IntegerToString((int)r.reason) + "|" +
           DoubleToString(r.score, 2) + "|" +
           DoubleToString(r.rr, 2) + "|" +
           IntegerToString((long)r.opened) + "|" +
           IntegerToString((long)r.closed) + "|" +
           CStateSerializer::Escape(r.fingerprint) + "\n";
     }
   return(s);
  }

//------------------------------------------------------------------//
bool CSignalHistoryStore::Deserialize(const string blob)
  {
   Reset();
   if(StringLen(blob) == 0) return(false);

   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n; i++)
     {
      string f[];
      if(StringSplit(lines[i], '|', f) < 11) continue;
      if(f[0] != "sig") continue;

      SSignalRecord r;
      r.id = (ulong)StringToInteger(f[1]);
      r.symbol = CStateSerializer::Unescape(f[2]);
      r.side = (f[3] == "BUY") ? QME_SIDE_BUY : QME_SIDE_SELL;
      r.finalState = (ENUM_QME_SIGNAL_STATE)StringToInteger(f[4]);
      r.reason = (ENUM_QME_REJECT)StringToInteger(f[5]);
      r.score = StringToDouble(f[6]);
      r.rr = StringToDouble(f[7]);
      r.opened = (datetime)StringToInteger(f[8]);
      r.closed = (datetime)StringToInteger(f[9]);
      r.fingerprint = CStateSerializer::Unescape(f[10]);
      if(r.id == 0) continue;
      Add(r);
      loaded++;
     }
   return(loaded > 0);
  }

//------------------------------------------------------------------//
string CSignalHistoryStore::Describe(void)
  {
   return("history signals=" + IntegerToString(m_count) +
          " rejected=" + IntegerToString(CountRejected()) +
          " avgScore=" + QmeFmt(AverageScore(), 1) +
          " avgRR=" + QmeFmt(AverageRR(), 2) +
          " dropped=" + IntegerToString((int)m_dropped));
  }

#endif // __QME_PERSIST_SIGNALHISTORY_MQH__
//+------------------------------------------------------------------+
