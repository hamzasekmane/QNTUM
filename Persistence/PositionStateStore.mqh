//+------------------------------------------------------------------+
//|                                 Persistence/PositionStateStore    |
//|  Remembers which positions belong to the engine.                     |
//|                                                                   |
//|  After a restart the broker still has the positions but the engine    |
//|  has no memory of them. This store is what lets the engine adopt      |
//|  its own open positions again — and verify that each still has a      |
//|  protective stop.                                                   |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_POSITIONSTORE_MQH__
#define __QME_PERSIST_POSITIONSTORE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "StateSerializer.mqh"
#include "../Execution/PositionReconciler.mqh"

struct STrackedPosition
  {
   ulong             ticket;
   string            symbol;
   ENUM_QME_SIDE     side;
   double            volume;
   double            entry;
   double            sl;
   double            tp;
   ulong             signalId;
   datetime          opened;
   bool              closed;
  };

class CPositionStateStore
  {
private:
   STrackedPosition  m_items[QME_MAX_TRACKED_POSITIONS];
   int               m_count;
   int               IndexOf(const ulong ticket);

public:
                     CPositionStateStore(void) { Reset(); }
   void              Reset(void) { m_count = 0; }

   bool              Track(const STrackedPosition &p);
   bool              Find(const ulong ticket, STrackedPosition &out) { return(Read(ticket, out)); }
   bool              Read(const ulong ticket, STrackedPosition &out);
   bool              UpdateStops(const ulong ticket, const double sl, const double tp);
   bool              Close(const ulong ticket);
   int               Count(void) { return(m_count); }
   int               OpenCount(void);
   bool              At(const int i, STrackedPosition &out);

   //--- drop records the broker no longer has; returns how many were dropped
   int               ReconcileWithBroker(const ulong magic);

   string            Serialize(void);
   bool              Deserialize(const string blob);
   string            Describe(void);
  };

//------------------------------------------------------------------//
int CPositionStateStore::IndexOf(const ulong ticket)
  {
   for(int i = 0; i < m_count; i++)
      if(m_items[i].ticket == ticket) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CPositionStateStore::Track(const STrackedPosition &p)
  {
   if(p.ticket == 0 || StringLen(p.symbol) == 0) return(false);
   const int i = IndexOf(p.ticket);
   if(i >= 0) { m_items[i] = p; return(true); }
   if(m_count >= QME_MAX_TRACKED_POSITIONS)
     {
      // Closed slots may be reused; never evict an open position.
      for(int k = 0; k < m_count; k++)
         if(m_items[k].closed) { m_items[k] = p; return(true); }
      QmeLogMsg(QME_LOG_WARN, "Positions", "position store full, cannot track " +
                IntegerToString((long)p.ticket));
      return(false);
     }
   m_items[m_count] = p;
   m_count++;
   return(true);
  }

bool CPositionStateStore::Read(const ulong ticket, STrackedPosition &out)
  {
   const int i = IndexOf(ticket);
   if(i < 0) return(false);
   out = m_items[i];
   return(true);
  }

bool CPositionStateStore::UpdateStops(const ulong ticket, const double sl, const double tp)
  {
   const int i = IndexOf(ticket);
   if(i < 0) return(false);
   m_items[i].sl = sl;
   m_items[i].tp = tp;
   return(true);
  }

bool CPositionStateStore::Close(const ulong ticket)
  {
   const int i = IndexOf(ticket);
   if(i < 0) return(false);
   m_items[i].closed = true;
   return(true);
  }

int CPositionStateStore::OpenCount(void)
  {
   int n = 0;
   for(int i = 0; i < m_count; i++)
      if(!m_items[i].closed) n++;
   return(n);
  }

bool CPositionStateStore::At(const int i, STrackedPosition &out)
  {
   if(i < 0 || i >= m_count) return(false);
   out = m_items[i];
   return(true);
  }

//------------------------------------------------------------------//
int CPositionStateStore::ReconcileWithBroker(const ulong magic)
  {
   int dropped = 0;
   // A disconnected terminal's position list is not reliable evidence of closure.
   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED) && !(bool)MQLInfoInteger(MQL_TESTER))
      return(0);
   for(int i = 0; i < m_count; i++)
     {
      if(m_items[i].closed) continue;
      bool alive = false;
      if(PositionSelectByTicket(m_items[i].ticket))
        {
         alive = (magic == 0 || (ulong)PositionGetInteger(POSITION_MAGIC) == magic);
        }
      if(!alive)
        {
         m_items[i].closed = true;
         dropped++;
         QmeLogMsg(QME_LOG_WARN, "Positions", "tracked position " +
                   IntegerToString((long)m_items[i].ticket) + " no longer exists; marked closed");
        }
     }
   return(dropped);
  }

//------------------------------------------------------------------//
string CPositionStateStore::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      const STrackedPosition p = m_items[i];
      s += "pos|" + IntegerToString((long)p.ticket) + "|" +
           CStateSerializer::Escape(p.symbol) + "|" +
           QmeSideName(p.side) + "|" +
           DoubleToString(p.volume, 2) + "|" +
           DoubleToString(p.entry, 8) + "|" +
           DoubleToString(p.sl, 8) + "|" +
           DoubleToString(p.tp, 8) + "|" +
           IntegerToString((long)p.signalId) + "|" +
           IntegerToString((long)p.opened) + "|" +
           (p.closed ? "1" : "0") + "\n";
     }
   return(s);
  }

//------------------------------------------------------------------//
bool CPositionStateStore::Deserialize(const string blob)
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
      if(f[0] != "pos") continue;
      if(m_count >= QME_MAX_TRACKED_POSITIONS) break;

      STrackedPosition p;
      p.ticket = (ulong)StringToInteger(f[1]);
      p.symbol = CStateSerializer::Unescape(f[2]);
      p.side = (f[3] == "BUY") ? QME_SIDE_BUY : QME_SIDE_SELL;
      p.volume = StringToDouble(f[4]);
      p.entry = StringToDouble(f[5]);
      p.sl = StringToDouble(f[6]);
      p.tp = StringToDouble(f[7]);
      p.signalId = (ulong)StringToInteger(f[8]);
      p.opened = (datetime)StringToInteger(f[9]);
      p.closed = (f[10] == "1");
      if(p.ticket == 0 || StringLen(p.symbol) == 0) continue;
      m_items[m_count] = p;
      m_count++;
      loaded++;
     }
   return(loaded > 0);
  }

//------------------------------------------------------------------//
string CPositionStateStore::Describe(void)
  {
   return("positions tracked=" + IntegerToString(m_count) +
          " open=" + IntegerToString(OpenCount()));
  }

#endif // __QME_PERSIST_POSITIONSTORE_MQH__
//+------------------------------------------------------------------+
