//+------------------------------------------------------------------+
//|                                       Persistence/StateRecovery   |
//|  Composes one state document and restores it after a restart.        |
//|                                                                   |
//|  Document layout (sections are literal marker lines):                |
//|    QME|STATE|<version>|<time>          header                          |
//|    [ACCT]    one account-state line                                  |
//|    [POS]     tracked positions                                       |
//|    [SIG]     signal history                                          |
//|    [DEDUP]   fingerprint cooldowns                                   |
//|    [IDEM]    executed intents                                        |
//|    [MEM]     runtime counters                                        |
//|                                                                   |
//|  Recovery is CONSERVATIVE: a document that fails the version check    |
//|  is ignored entirely and the engine starts clean rather than       |
//|  restoring a half-understood state.                                   |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_STATERECOVERY_MQH__
#define __QME_PERSIST_STATERECOVERY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountState.mqh"
#include "../Strategy/SignalDeduplicator.mqh"
#include "../Execution/IdempotencyGuard.mqh"
#include "StateSerializer.mqh"
#include "PositionStateStore.mqh"
#include "SignalHistoryStore.mqh"
#include "RuntimeMemory.mqh"

struct SRecoveryReport
  {
   bool              loaded;
   bool              versionOk;
   bool              accountRestored;
   int               positionsRestored;
   int               positionsStale;
   int               signalsRestored;
   int               fingerprintsRestored;
   int               intentsRestored;
   int               countersRestored;
   string            note;
  };

class CStateRecovery
  {
private:
   static string     Section(const string blob, const string name);

public:
   static string     Compose(CAccountState &state, CPositionStateStore &positions,
                             CSignalHistoryStore &history,
                             CSignalDeduplicator &dedup,
                             CIdempotencyGuard &idem, CRuntimeMemory &memory);
   static SRecoveryReport Apply(const string blob, CAccountState &state,
                                CPositionStateStore &positions, CSignalHistoryStore &history,
                                CSignalDeduplicator &dedup, CIdempotencyGuard &idem,
                                CRuntimeMemory &memory, const ulong magic);
  };

//------------------------------------------------------------------//
string CStateRecovery::Section(const string blob, const string name)
  {
   const string marker = "[" + name + "]";
   const int start = StringFind(blob, marker);
   if(start < 0) return("");

   int from = start + StringLen(marker);
   if(from < StringLen(blob) && StringGetCharacter(blob, from) == '\n') from++;

   const int next = StringFind(blob, "\n[", from - 1);
   const int end = (next < 0) ? StringLen(blob) : next + 1;
   if(end <= from) return("");
   return(StringSubstr(blob, from, end - from));
  }

//------------------------------------------------------------------//
string CStateRecovery::Compose(CAccountState &state, CPositionStateStore &positions,
                               CSignalHistoryStore &history,
                               CSignalDeduplicator &dedup,
                               CIdempotencyGuard &idem, CRuntimeMemory &memory)
  {
   string header = "";
   CStateSerializer::Header(header);

   string s = header + "\n";
   s += "[ACCT]\n" + state.Serialize() + "\n";
   s += "[POS]\n" + positions.Serialize();
   s += "[SIG]\n" + history.Serialize();
   s += "[DEDUP]\n" + dedup.Serialize();
   s += "[IDEM]\n" + idem.Serialize();
   s += "[MEM]\n" + memory.Serialize();
   return(s);
  }

//------------------------------------------------------------------//
SRecoveryReport CStateRecovery::Apply(const string blob, CAccountState &state,
                                      CPositionStateStore &positions,
                                      CSignalHistoryStore &history,
                                      CSignalDeduplicator &dedup, CIdempotencyGuard &idem,
                                      CRuntimeMemory &memory, const ulong magic)
  {
   SRecoveryReport r;
   r.loaded = false;
   r.versionOk = false;
   r.accountRestored = false;
   r.positionsRestored = 0;
   r.positionsStale = 0;
   r.signalsRestored = 0;
   r.fingerprintsRestored = 0;
   r.intentsRestored = 0;
   r.countersRestored = 0;
   r.note = "no saved state";

   if(StringLen(blob) == 0) return(r);

   string why = "";
   r.versionOk = CStateSerializer::CheckVersion(blob, why);
   if(!r.versionOk)
     {
      r.note = "state ignored: " + why;
      QmeLogMsg(QME_LOG_WARN, "Recovery", r.note);
      return(r);
     }

   // Require all section boundaries before applying any part of the state.
   // This detects truncated documents, not arbitrary tampering or corruption.
   const string markers[6] = {"[ACCT]\n", "[POS]\n", "[SIG]\n",
                              "[DEDUP]\n", "[IDEM]\n", "[MEM]\n"};
   int prior = 0;
   for(int i = 0; i < 6; i++)
     {
      const int pos = StringFind(blob, markers[i], prior);
      if(pos < 0)
        {
         r.note = "state ignored: missing or out-of-order section " + markers[i];
         return(r);
        }
      prior = pos + StringLen(markers[i]);
     }

   //--- account state (day equity, peak, streak)
   const string acct = Section(blob, "ACCT");
   if(StringLen(acct) > 0)
     {
      string line = acct;
      StringTrimRight(line);
      if(StringLen(line) > 0 && state.Deserialize(line))
        {
         r.accountRestored = true;
        }
      else
         QmeLogMsg(QME_LOG_WARN, "Recovery", "account state could not be restored");
     }

   if(!r.accountRestored)
     {
      r.note = "state ignored: account baseline missing or invalid";
      return(r);
     }

   //--- positions
   const string pos = Section(blob, "POS");
   if(StringLen(pos) > 0 && positions.Deserialize(pos))
     {
      r.positionsRestored = positions.OpenCount();
      //--- the broker is authoritative: drop what it no longer has
      r.positionsStale = positions.ReconcileWithBroker(magic);
      r.positionsRestored = positions.OpenCount();
     }

   //--- signal history
   const string sig = Section(blob, "SIG");
   if(StringLen(sig) > 0 && history.Deserialize(sig))
      r.signalsRestored = history.Count();

   //--- fingerprint cooldowns
   const string dd = Section(blob, "DEDUP");
   if(StringLen(dd) > 0 && dedup.Deserialize(dd))
      r.fingerprintsRestored = dedup.Count();

   //--- executed intents
   const string idemBlob = Section(blob, "IDEM");
   if(StringLen(idemBlob) > 0)
     {
      if(!idem.Deserialize(idemBlob))
        {
         r.note = "state ignored: invalid intent records";
         return(r);
        }
      r.intentsRestored = idem.Count();
     }

   //--- runtime counters
   const string mem = Section(blob, "MEM");
   if(StringLen(mem) > 0 && memory.Deserialize(mem))
      r.countersRestored = memory.Count();

   r.loaded = true;
   r.note = "restored: account=" + (r.accountRestored ? "yes" : "no") +
            " positions=" + IntegerToString(r.positionsRestored) +
            " stale=" + IntegerToString(r.positionsStale) +
            " signals=" + IntegerToString(r.signalsRestored) +
            " fingerprints=" + IntegerToString(r.fingerprintsRestored) +
            " intents=" + IntegerToString(r.intentsRestored) +
            " counters=" + IntegerToString(r.countersRestored);

   QmeLogMsg(QME_LOG_INFO, "Recovery", r.note);
   return(r);
  }

#endif // __QME_PERSIST_STATERECOVERY_MQH__
//+------------------------------------------------------------------+
