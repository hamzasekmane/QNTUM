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
   int               m_count;
   int               m_head;
   int               Find(const string fp);

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
  }

int CSignalDeduplicator::Find(const string fp)
  {
   for(int i = 0; i < m_count; i++)
      if(m_fp[i] == fp) return(i);
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
      //--- ring: overwrite the oldest slot
      m_fp[m_head] = fp;
      m_time[m_head] = now;
      m_signalId[m_head] = signalId;
      m_head = (m_head + 1) % QME_MAX_FINGERPRINTS;
      return(true);
     }
   m_fp[m_count] = fp;
   m_time[m_count] = now;
   m_signalId[m_count] = signalId;
   m_count++;
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
   Reset();
   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n && m_count < QME_MAX_FINGERPRINTS; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], ';', f) < 4) continue;
      if(f[0] != "fp") continue;
      m_time[m_count] = (datetime)StringToInteger(f[1]);
      m_signalId[m_count] = (ulong)StringToInteger(f[2]);
      m_fp[m_count] = f[3];
      m_count++;
      loaded++;
     }
   return(loaded > 0);
  }

#endif // __QME_STRATEGY_SIGNALDEDUP_MQH__
//+------------------------------------------------------------------+
