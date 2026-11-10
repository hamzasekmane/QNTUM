//+------------------------------------------------------------------+
//|                                     Persistence/RuntimeMemory     |
//|  Named numeric counters that survive a restart.                       |
//|                                                                   |
//|  Used for counters like "signals generated today", "orders rejected    |
//|  by spread", "recovery count". Keys are bounded; new keys are          |
//|  rejected once the table is full instead of silently overwriting.      |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_RUNTIMEMEMORY_MQH__
#define __QME_PERSIST_RUNTIMEMEMORY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "StateSerializer.mqh"

struct SRuntimeCounter
  {
   string            key;
   double            value;
  };

class CRuntimeMemory
  {
private:
   SRuntimeCounter   m_items[QME_MAX_HISTORY];
   int               m_count;
   int               Find(const string key);

public:
                     CRuntimeMemory(void) { Reset(); }
   void              Reset(void) { m_count = 0; }
   void              Set(const string key, const double v);
   double            Inc(const string key, const double by = 1.0);
   double            Get(const string key, const double def = 0.0);
   bool              Has(const string key) { return(Find(key) >= 0); }
   int               Count(void) { return(m_count); }

   string            Serialize(void);
   bool              Deserialize(const string blob);
   string            Describe(void);
  };

//------------------------------------------------------------------//
int CRuntimeMemory::Find(const string key)
  {
   for(int i = 0; i < m_count; i++)
      if(m_items[i].key == key) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
void CRuntimeMemory::Set(const string key, const double v)
  {
   if(StringLen(key) == 0) return;
   if(!QmeIsFinite(v)) return;
   const int i = Find(key);
   if(i >= 0) { m_items[i].value = v; return; }
   if(m_count >= QME_MAX_HISTORY) return;
   m_items[m_count].key = key;
   m_items[m_count].value = v;
   m_count++;
  }

double CRuntimeMemory::Inc(const string key, const double by)
  {
   const int i = Find(key);
   if(i < 0)
     {
      Set(key, by);
      return(by);
     }
   m_items[i].value += by;
   return(m_items[i].value);
  }

double CRuntimeMemory::Get(const string key, const double def)
  {
   const int i = Find(key);
   return((i >= 0) ? m_items[i].value : def);
  }

//------------------------------------------------------------------//
string CRuntimeMemory::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
      s += CStateSerializer::Dbl("mem." + m_items[i].key, m_items[i].value, 6) + "\n";
   return(s);
  }

//------------------------------------------------------------------//
bool CRuntimeMemory::Deserialize(const string blob)
  {
   Reset();
   if(StringLen(blob) == 0) return(false);

   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], '|', f) < 3) continue;
      if(StringFind(f[0], "mem.") != 0) continue;
      const string key = StringSubstr(f[0], 4);
      const double v = StringToDouble(f[2]);
      if(!QmeIsFinite(v)) continue;
      Set(key, v);
      loaded++;
     }
   return(loaded > 0);
  }

//------------------------------------------------------------------//
string CRuntimeMemory::Describe(void)
  {
   return IntegerToString(m_count) + " runtime counter(s)";
  }

#endif // __QME_PERSIST_RUNTIMEMEMORY_MQH__
//+------------------------------------------------------------------+
