//+------------------------------------------------------------------+
//|                                  Persistence/CheckpointManager    |
//|  Decides WHEN state is written and keeps the last-save facts.        |
//|                                                                   |
//|  The payload is produced by CStateRecovery::Compose(); this class     |
//|  only owns timing, failure counting and the retry note.               |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_CHECKPOINT_MQH__
#define __QME_PERSIST_CHECKPOINT_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "StateStore.mqh"

class CCheckpointManager
  {
private:
   CStateStore       m_store;
   int               m_intervalSec;
   datetime          m_lastSave;
   long              m_saves;
   long              m_failures;
   string            m_note;

public:
                     CCheckpointManager(void) { m_intervalSec = 30; m_lastSave = 0; m_saves = 0; m_failures = 0; m_note = "idle"; }
   bool              Init(const bool enabled, const string name, const int intervalSec, string &err);
   bool              Due(const datetime now);
   bool              Save(const string payload, const datetime now, string &err);
   bool              Load(string &payload, string &err);
   bool              Enabled(void) { return(m_store.Enabled()); }
   datetime          LastSave(void) { return(m_lastSave); }
   long              Saves(void) { return(m_saves); }
   long              Failures(void) { return(m_failures); }
   string            Note(void) { return(m_note); }
   CStateStore*      Store(void) { return(&m_store); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
bool CCheckpointManager::Init(const bool enabled, const string name, const int intervalSec,
                              string &err)
  {
   m_intervalSec = MathMax(intervalSec, 5);
   m_lastSave = 0;
   m_saves = 0;
   m_failures = 0;
   m_note = enabled ? "ready" : "disabled";
   return(m_store.Init(name, enabled, err));
  }

//------------------------------------------------------------------//
bool CCheckpointManager::Due(const datetime now)
  {
   if(!m_store.Enabled()) return(false);
   if(m_lastSave == 0) return(true);
   if(now <= m_lastSave) return(false);        // clock went backwards: never spam
   return((now - m_lastSave) >= m_intervalSec);
  }

//------------------------------------------------------------------//
bool CCheckpointManager::Save(const string payload, const datetime now, string &err)
  {
   if(!m_store.Enabled()) { err = "persistence disabled"; return(false); }

   string localErr = "";
   if(!m_store.Write(payload, localErr))
     {
      m_failures++;
      m_note = "save failed: " + localErr;
      err = localErr;
      return(false);
     }
   m_saves++;
   m_lastSave = now;
   m_note = "saved " + IntegerToString(StringLen(payload)) + " bytes";
   err = "";
   return(true);
  }

//------------------------------------------------------------------//
bool CCheckpointManager::Load(string &payload, string &err)
  {
   if(!m_store.Read(payload, err))
     {
      m_note = "load: " + err;
      return(false);
     }
   m_note = "loaded " + IntegerToString(StringLen(payload)) + " bytes";
   return(true);
  }

//------------------------------------------------------------------//
string CCheckpointManager::Describe(void)
  {
   return("checkpoint " + m_note +
          " saves=" + IntegerToString((int)m_saves) +
          " failures=" + IntegerToString((int)m_failures) +
          (m_lastSave > 0 ? " last=" + TimeToString(m_lastSave, TIME_DATE | TIME_SECONDS) : ""));
  }

#endif // __QME_PERSIST_CHECKPOINT_MQH__
//+------------------------------------------------------------------+
