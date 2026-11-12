//+------------------------------------------------------------------+
//|                                  Strategy/SignalDeduplicator      |
//|  Prevents the same market fact from producing multiple orders.       |
//|                                                                   |
//|  A fingerprint is registered the moment an order is SENT, and kept     |
//|  for `cooldownSeconds`. Repeated ticks, restarts and re-scans cannot   |
//|  re-fire the same setup. The store is persisted so a restart does not  |
//|  forget what was already executed.                                    |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_SIGNALDEDUP_MQH__
#define __QME_STRATEGY_SIGNALDEDUP_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

class CSignalDeduplicator
  {
private:
   string            m_fp[QME_MAX_FINGERPRINTS];
   datetime          m_time[QME_MAX_FINGERPRINTS];
   ulong             m_signalId[QME_MAX_FINGERPRINTS];
   //--- rebuildable open-addressed index: 0=empty, -1=tombstone, else slot+1
   int               m_hashIndex[1024];
   int               m_count;
   int               m_head;
   int               Find(const string fp);
   bool              IndexInsert(const string fp, const int record);
   void              IndexRemove(const string fp);
   void              RebuildIndex(void);

public:
                     CSignalDeduplicator(void) { Reset(); }
   void              Reset(void);

   bool              IsDuplicate(const string fp, const int cooldownSeconds, const datetime now);
   bool              Register(const string fp, const ulong signalId, const datetime now);
   int               Count(void) { return(m_count); }
   void              Prune(const int cooldownSeconds, const datetime now);
   string            Serialize(void);
   bool              Deserialize(const string blob);
  };

//------------------------------------------------------------------//
void CSignalDeduplicator::Reset(void)
  {
   m_count = 0;
   m_head = 0;
   for(int i = 0; i < QME_MAX_FINGERPRINTS; i++)
     {
      m_fp[i] = "";
      m_time[i] = 0;
      m_signalId[i] = 0;
     }
   for(int i = 0; i < ArraySize(m_hashIndex); i++) m_hashIndex[i] = 0;
  }

bool CSignalDeduplicator::IndexInsert(const string fp, const int record)
  {
   if(StringLen(fp) == 0 || record < 0 || record >= m_count) return(false);
   const int capacity = ArraySize(m_hashIndex);
   int slot = (int)(QmeHashString(fp) % (ulong)capacity);
   int firstTombstone = -1;
   for(int probe = 0; probe < capacity; probe++)
     {
      const int entry = m_hashIndex[slot];
      if(entry == 0)
        {
         const int target = (firstTombstone >= 0) ? firstTombstone : slot;
         m_hashIndex[target] = record + 1;
         return(true);
        }
      if(entry == -1)
        {
         if(firstTombstone < 0) firstTombstone = slot;
        }
      else
        {
         const int existing = entry - 1;
         if(existing >= 0 && existing < m_count && m_fp[existing] == fp)
           {
            m_hashIndex[slot] = record + 1;
            return(true);
           }
        }
      slot = (slot + 1) % capacity;
     }
   if(firstTombstone >= 0)
     {
      m_hashIndex[firstTombstone] = record + 1;
      return(true);
     }
   return(false);
  }

void CSignalDeduplicator::IndexRemove(const string fp)
  {
   if(StringLen(fp) == 0) return;
   const int capacity = ArraySize(m_hashIndex);
   int slot = (int)(QmeHashString(fp) % (ulong)capacity);
   for(int probe = 0; probe < capacity; probe++)
     {
      const int entry = m_hashIndex[slot];
      if(entry == 0) return;
      if(entry > 0)
        {
         const int record = entry - 1;
         if(record >= 0 && record < m_count && m_fp[record] == fp)
           { m_hashIndex[slot] = -1; return; }
        }
      slot = (slot + 1) % capacity;
     }
  }

void CSignalDeduplicator::RebuildIndex(void)
  {
   for(int i = 0; i < ArraySize(m_hashIndex); i++) m_hashIndex[i] = 0;
   for(int i = 0; i < m_count; i++) IndexInsert(m_fp[i], i);
  }

int CSignalDeduplicator::Find(const string fp)
  {
   if(StringLen(fp) == 0) return(-1);
   const int capacity = ArraySize(m_hashIndex);
   int slot = (int)(QmeHashString(fp) % (ulong)capacity);
   for(int probe = 0; probe < capacity; probe++)
     {
      const int entry = m_hashIndex[slot];
      if(entry == 0) return(-1);
      if(entry > 0)
        {
         const int record = entry - 1;
         if(record >= 0 && record < m_count && m_fp[record] == fp) return(record);
        }
      slot = (slot + 1) % capacity;
     }
   return(-1);
  }

//------------------------------------------------------------------//
bool CSignalDeduplicator::IsDuplicate(const string fp, const int cooldownSeconds, const datetime now)
  {
   if(StringLen(fp) == 0) return(false);
   const int i = Find(fp);
   if(i < 0) return(false);
   if(cooldownSeconds <= 0) return(true);
   if(m_time[i] <= 0) return(true);
   return((now - m_time[i]) < (datetime)cooldownSeconds);
  }

//------------------------------------------------------------------//
bool CSignalDeduplicator::Register(const string fp, const ulong signalId, const datetime now)
  {
   if(StringLen(fp) == 0) return(false);
   const int existing = Find(fp);
   if(existing >= 0)
     {
      m_time[existing] = now;
      m_signalId[existing] = signalId;
      return(true);
     }
   if(m_count >= QME_MAX_FINGERPRINTS)
     {
      //--- ring: remove the evicted key from the secondary index, then reuse slot
      IndexRemove(m_fp[m_head]);
      m_fp[m_head] = fp;
      m_time[m_head] = now;
      m_signalId[m_head] = signalId;
      const bool indexed = IndexInsert(fp, m_head);
      m_head = (m_head + 1) % QME_MAX_FINGERPRINTS;
      return(indexed);
     }
   const int slot = m_count;
   m_fp[slot] = fp;
   m_time[slot] = now;
   m_signalId[slot] = signalId;
   m_count++;
   if(!IndexInsert(fp, slot))
     {
      m_count--;
      m_fp[slot] = "";
      m_time[slot] = 0;
      m_signalId[slot] = 0;
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
void CSignalDeduplicator::Prune(const int cooldownSeconds, const datetime now)
  {
   if(m_count <= 0) return;
   string keptFp[];
   datetime keptTime[];
   ulong keptId[];
   ArrayResize(keptFp, 0);
   ArrayResize(keptTime, 0);
   ArrayResize(keptId, 0);

   for(int i = 0; i < m_count; i++)
     {
      if(cooldownSeconds > 0 && m_time[i] > 0 &&
         (now - m_time[i]) >= (datetime)cooldownSeconds)
         continue;
      const int n = ArraySize(keptFp);
      ArrayResize(keptFp, n + 1);
      ArrayResize(keptTime, n + 1);
      ArrayResize(keptId, n + 1);
      keptFp[n] = m_fp[i];
      keptTime[n] = m_time[i];
      keptId[n] = m_signalId[i];
     }

   m_count = ArraySize(keptFp);
   m_head = 0;
   for(int i = 0; i < m_count; i++)
     {
      m_fp[i] = keptFp[i];
      m_time[i] = keptTime[i];
      m_signalId[i] = keptId[i];
     }
   RebuildIndex();
  }

//------------------------------------------------------------------//
string CSignalDeduplicator::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      if(StringLen(m_fp[i]) == 0) continue;
      s += "fp;" + IntegerToString((long)m_time[i]) + ";" +
           IntegerToString((long)m_signalId[i]) + ";" + m_fp[i] + "\n";
     }
   return(s);
  }

//------------------------------------------------------------------//
bool CSignalDeduplicator::Deserialize(const string blob)
  {
   if(StringLen(blob) == 0) return(false);

   //--- parse into scratch first: a malformed document must never destroy
   //--- the records already held, and malformed lines are rejected one by
   //--- one instead of loading as time=0 entries that would block forever
   string tmpFp[QME_MAX_FINGERPRINTS];
   datetime tmpTime[QME_MAX_FINGERPRINTS];
   ulong tmpId[QME_MAX_FINGERPRINTS];
   int loaded = 0;

   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   for(int i = 0; i < n && loaded < QME_MAX_FINGERPRINTS; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], ';', f) < 4) continue;      // incomplete record
      if(f[0] != "fp") continue;
      const long t = StringToInteger(f[1]);
      if(t <= 0) continue;                                 // no valid timestamp
      string fp = f[3];
      for(int k = 4; k < ArraySize(f); k++) fp += ";" + f[k];  // ';' inside fp
      if(StringLen(fp) == 0) continue;
      bool dup = false;
      for(int k = 0; k < loaded; k++) if(tmpFp[k] == fp) { dup = true; break; }
      if(dup) continue;
      tmpTime[loaded] = (datetime)t;
      tmpId[loaded] = (ulong)StringToInteger(f[2]);
      tmpFp[loaded] = fp;
      loaded++;
     }

   if(loaded <= 0) return(false);   // nothing valid: keep current state

   Reset();
   for(int i = 0; i < loaded; i++)
     {
      m_fp[i] = tmpFp[i];
      m_time[i] = tmpTime[i];
      m_signalId[i] = tmpId[i];
     }
   m_count = loaded;
   RebuildIndex();
   return(true);
  }

#endif // __QME_STRATEGY_SIGNALDEDUP_MQH__
//+------------------------------------------------------------------+
