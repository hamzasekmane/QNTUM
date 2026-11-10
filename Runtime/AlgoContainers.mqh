//+------------------------------------------------------------------+
//|                                       Runtime/AlgoContainers      |
//|  Small, allocation-free containers used across the runtime.          |
//|                                                                   |
//|  MQL5 has no STL; these types give the engine predictable, bounded     |
//|  storage with no hidden growth. Every container reports when it       |
//|  refuses an item instead of silently dropping it.                    |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_CONTAINERS_MQH__
#define __QME_RUNTIME_CONTAINERS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

//+------------------------------------------------------------------+
class CQmeStringList
  {
private:
   string            m_items[QME_MAX_SYMBOLS];
   int               m_count;

public:
   void              Clear(void) { m_count = 0; }
   int               Count(void) { return(m_count); }
   bool              Has(const string v);
   bool              Add(const string v);      // refuses duplicates and overflow
   bool              Remove(const string v);
   string            At(const int i);
   string            Join(const string sep = ",");
  };

//------------------------------------------------------------------//
bool CQmeStringList::Has(const string v)
  {
   for(int i = 0; i < m_count; i++)
      if(m_items[i] == v) return(true);
   return(false);
  }

bool CQmeStringList::Add(const string v)
  {
   if(StringLen(v) == 0) return(false);
   if(Has(v)) return(false);
   if(m_count >= QME_MAX_SYMBOLS) return(false);
   m_items[m_count] = v;
   m_count++;
   return(true);
  }

bool CQmeStringList::Remove(const string v)
  {
   for(int i = 0; i < m_count; i++)
     {
      if(m_items[i] != v) continue;
      for(int k = i; k < m_count - 1; k++) m_items[k] = m_items[k + 1];
      m_count--;
      return(true);
     }
   return(false);
  }

string CQmeStringList::At(const int i)
  {
   if(i < 0 || i >= m_count) return("");
   return(m_items[i]);
  }

string CQmeStringList::Join(const string sep)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      if(i > 0) s += sep;
      s += m_items[i];
     }
   return(s);
  }

//+------------------------------------------------------------------+
class CQmeTicketList
  {
private:
   ulong             m_items[QME_MAX_TRACKED_POSITIONS];
   int               m_count;

public:
   void              Clear(void) { m_count = 0; }
   int               Count(void) { return(m_count); }
   bool              Has(const ulong t);
   bool              Add(const ulong t);
   bool              Remove(const ulong t);
   ulong             At(const int i);
  };

bool CQmeTicketList::Has(const ulong t)
  {
   if(t == 0) return(false);
   for(int i = 0; i < m_count; i++)
      if(m_items[i] == t) return(true);
   return(false);
  }

bool CQmeTicketList::Add(const ulong t)
  {
   if(t == 0 || Has(t)) return(false);
   if(m_count >= QME_MAX_TRACKED_POSITIONS) return(false);
   m_items[m_count] = t;
   m_count++;
   return(true);
  }

bool CQmeTicketList::Remove(const ulong t)
  {
   for(int i = 0; i < m_count; i++)
     {
      if(m_items[i] != t) continue;
      for(int k = i; k < m_count - 1; k++) m_items[k] = m_items[k + 1];
      m_count--;
      return(true);
     }
   return(false);
  }

ulong CQmeTicketList::At(const int i)
  {
   if(i < 0 || i >= m_count) return(0);
   return(m_items[i]);
  }

//+------------------------------------------------------------------+
//| Fixed-size numeric ring: last N samples with simple statistics.    |
//+------------------------------------------------------------------+
class CQmeRing
  {
private:
   double            m_values[128];
   int               m_capacity;
   int               m_count;
   int               m_next;

public:
   void              Init(const int capacity);
   void              Clear(void) { m_count = 0; m_next = 0; }
   void              Push(const double v);
   int               Count(void) { return(m_count); }
   double            Last(const double def = 0.0);
   double            Average(const double def = 0.0);
   double            Minimum(const double def = 0.0);
   double            Maximum(const double def = 0.0);
  };

void CQmeRing::Init(const int capacity)
  {
   m_capacity = MathMin(MathMax(capacity, 1), 128);
   Clear();
  }

void CQmeRing::Push(const double v)
  {
   if(!QmeIsFinite(v)) return;
   if(m_capacity <= 0) m_capacity = 1;
   m_values[m_next] = v;
   m_next = (m_next + 1) % m_capacity;
   if(m_count < m_capacity) m_count++;
  }

double CQmeRing::Last(const double def)
  {
   if(m_count <= 0) return(def);
   const int i = (m_next - 1 + m_capacity) % m_capacity;
   return(m_values[i]);
  }

double CQmeRing::Average(const double def)
  {
   if(m_count <= 0) return(def);
   double s = 0.0;
   for(int i = 0; i < m_count; i++) s += m_values[i];
   return(s / m_count);
  }

double CQmeRing::Minimum(const double def)
  {
   if(m_count <= 0) return(def);
   double m = m_values[0];
   for(int i = 1; i < m_count; i++) m = MathMin(m, m_values[i]);
   return(m);
  }

double CQmeRing::Maximum(const double def)
  {
   if(m_count <= 0) return(def);
   double m = m_values[0];
   for(int i = 1; i < m_count; i++) m = MathMax(m, m_values[i]);
   return(m);
  }

#endif // __QME_RUNTIME_CONTAINERS_MQH__
//+------------------------------------------------------------------+
