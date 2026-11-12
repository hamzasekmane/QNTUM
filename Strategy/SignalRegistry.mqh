//+------------------------------------------------------------------+
//|                                      Strategy/SignalRegistry      |
//|  Live signal storage with capacity control and duplicate refusal.    |
//|                                                                   |
//|  INVARIANTS                                                        |
//|   * at most one LIVE signal per fingerprint (symbol+side+tf+zone+bar) |
//|   * at most QME_MAX_SIGNALS records; when full, the oldest terminal    |
//|     record is evicted; if every record is live the new signal is       |
//|     REJECTED with an explicit reason;                                 |
//|   * terminal records are retained for history/persistence.            |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SIGNALREGISTRY_MQH__
#define __QME_STRATEGY_SIGNALREGISTRY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "SignalTypes.mqh"

class CSignalRegistry
  {
private:
   STradingSignal    m_signals[];
   long              m_added;
   long              m_evicted;
   int               FindIndex(const ulong id);
   bool              EvictOneTerminal(void);
   bool              LiveFingerprintExists(const string fingerprint);

public:
                     CSignalRegistry(void) { m_added = 0; m_evicted = 0; ArrayResize(m_signals, 0); }
   void              Clear(void) { ArrayResize(m_signals, 0); }
   void              Reset(void) { Clear(); m_added = 0; m_evicted = 0; }

   //--- returns false with a reason when the signal cannot be stored
   bool              Add(const STradingSignal &s, ENUM_QME_REJECT &reason, string &why);
   bool              Update(const STradingSignal &s);
   bool              Get(const ulong id, STradingSignal &out);
   bool              At(const int i, STradingSignal &out);

   int               Count(void) { return(ArraySize(m_signals)); }
   int               LiveCount(void);
   int               PendingExecutionCount(void);
   bool              HasLiveFingerprint(const string fingerprint) { return(LiveFingerprintExists(fingerprint)); }
   long              Added(void) { return(m_added); }
   long              Evicted(void) { return(m_evicted); }

   //--- signals of one symbol that are still live (used for duplicate checks)
   int               LiveForSymbol(const string symbol, STradingSignal &out[]);
   //--- terminal records can be removed after they are persisted
   int               RemoveTerminalOlderThan(const datetime cutoff);
   string            Describe(void);
  };

//------------------------------------------------------------------//
int CSignalRegistry::FindIndex(const ulong id)
  {
   for(int i = 0; i < ArraySize(m_signals); i++)
      if(m_signals[i].id == id) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CSignalRegistry::LiveFingerprintExists(const string fingerprint)
  {
   if(StringLen(fingerprint) == 0) return(false);
   for(int i = 0; i < ArraySize(m_signals); i++)
     {
      if(m_signals[i].fingerprint != fingerprint) continue;
      if(CSignalTypes::IsLive(m_signals[i].state)) return(true);
     }
   return(false);
  }

//------------------------------------------------------------------//
bool CSignalRegistry::EvictOneTerminal(void)
  {
   int oldest = -1;
   datetime oldestTime = 0;
   for(int i = 0; i < ArraySize(m_signals); i++)
     {
      if(!CSignalTypes::IsTerminal(m_signals[i].state)) continue;
      if(oldest < 0 || m_signals[i].updated < oldestTime)
        {
         oldest = i;
         oldestTime = m_signals[i].updated;
        }
     }
   if(oldest < 0) return(false);

   const int n = ArraySize(m_signals);
   for(int i = oldest; i < n - 1; i++) m_signals[i] = m_signals[i + 1];
   ArrayResize(m_signals, n - 1);
   m_evicted++;
   return(true);
  }

//------------------------------------------------------------------//
bool CSignalRegistry::Add(const STradingSignal &s, ENUM_QME_REJECT &reason, string &why)
  {
   reason = QME_REJ_NONE;
   why = "";

   if(s.id == 0) { reason = QME_REJ_INTERNAL; why = "signal has no id"; return(false); }
   if(FindIndex(s.id) >= 0) { reason = QME_REJ_DUPLICATE_SIGNAL; why = "id already registered"; return(false); }
   if(LiveFingerprintExists(s.fingerprint))
     {
      reason = QME_REJ_DUPLICATE_SIGNAL;
      why = "a live signal already exists for this fingerprint";
      return(false);
     }

   if(ArraySize(m_signals) >= QME_MAX_SIGNALS)
     {
      if(!EvictOneTerminal())
        {
         reason = QME_REJ_MAX_POSITIONS;
         why = "signal registry full and all records are live";
         return(false);
        }
     }

   const int n = ArraySize(m_signals);
   ArrayResize(m_signals, n + 1);
   m_signals[n] = s;
   m_added++;
   return(true);
  }

//------------------------------------------------------------------//
bool CSignalRegistry::Update(const STradingSignal &s)
  {
   const int i = FindIndex(s.id);
   if(i < 0) return(false);
   m_signals[i] = s;
   return(true);
  }

//------------------------------------------------------------------//
bool CSignalRegistry::Get(const ulong id, STradingSignal &out)
  {
   QmeSignalClear(out);
   const int i = FindIndex(id);
   if(i < 0) return(false);
   out = m_signals[i];
   return(true);
  }

bool CSignalRegistry::At(const int i, STradingSignal &out)
  {
   QmeSignalClear(out);
   if(i < 0 || i >= ArraySize(m_signals)) return(false);
   out = m_signals[i];
   return(true);
  }

//------------------------------------------------------------------//
int CSignalRegistry::LiveCount(void)
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_signals); i++)
      if(CSignalTypes::IsLive(m_signals[i].state)) n++;
   return(n);
  }

int CSignalRegistry::PendingExecutionCount(void)
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_signals); i++)
      if(CSignalTypes::IsPendingExecution(m_signals[i].state)) n++;
   return(n);
  }

//------------------------------------------------------------------//
int CSignalRegistry::LiveForSymbol(const string symbol, STradingSignal &out[])
  {
   ArrayResize(out, 0);
   for(int i = 0; i < ArraySize(m_signals); i++)
     {
      if(m_signals[i].symbol != symbol) continue;
      if(!CSignalTypes::IsLive(m_signals[i].state)) continue;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = m_signals[i];
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
int CSignalRegistry::RemoveTerminalOlderThan(const datetime cutoff)
  {
   const int before = ArraySize(m_signals);
   STradingSignal kept[];
   ArrayResize(kept, 0);
   for(int i = 0; i < ArraySize(m_signals); i++)
     {
      const bool drop = CSignalTypes::IsTerminal(m_signals[i].state) &&
                        m_signals[i].updated > 0 && m_signals[i].updated < cutoff;
      if(drop) continue;
      const int n = ArraySize(kept);
      ArrayResize(kept, n + 1);
      kept[n] = m_signals[i];
     }
   ArrayResize(m_signals, ArraySize(kept));
   for(int i = 0; i < ArraySize(kept); i++) m_signals[i] = kept[i];
   return(before - ArraySize(m_signals));
  }

//------------------------------------------------------------------//
string CSignalRegistry::Describe(void)
  {
   return("signals=" + IntegerToString(ArraySize(m_signals)) +
          " live=" + IntegerToString(LiveCount()) +
          " pending=" + IntegerToString(PendingExecutionCount()) +
          " added=" + IntegerToString((int)m_added));
  }

#endif // __QME_STRATEGY_SIGNALREGISTRY_MQH__
//+------------------------------------------------------------------+
