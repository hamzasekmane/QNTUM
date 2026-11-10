//+------------------------------------------------------------------+
//|                                       Intelligence/ClassPrior     |
//|  Base rates observed on historical outcomes.                        |
//|                                                                   |
//|  HONESTY RULE: a prior is only reported when it is supported by       |
//|  at least `minSamples` observations. Until then the prior is          |
//|  "unavailable" and no probability may be derived from it.             |
//|                                                                   |
//|  The key is deliberately coarse (side + regime + zone source) so that |
//|  classes fill up quickly and cannot be over-fitted per symbol or       |
//|  per timeframe.                                                     |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_CLASSPRIOR_MQH__
#define __QME_INTEL_CLASSPRIOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

struct SClassPrior
  {
   string            key;
   int               samples;
   int               wins;
   double            winRate;      // wins / samples
  };

class CClassPrior
  {
private:
   SClassPrior       m_items[64];
   int               m_count;
   int               m_minSamples;

public:
                     CClassPrior(void) { Init(30); }
   void              Init(const int minSamples);
   void              Reset(void);

   static string     Key(const ENUM_QME_SIDE side, const ENUM_QME_REGIME regime,
                         const ENUM_QME_ZONE_SOURCE source);

   void              Observe(const string key, const bool win);
   bool              Get(const string key, SClassPrior &out);
   bool              WinRate(const string key, double &rate, int &samples);
   int               Classes(void) { return(m_count); }
   string            Serialize(void);
   bool              Deserialize(const string blob);
  };

//------------------------------------------------------------------//
void CClassPrior::Init(const int minSamples)
  {
   m_minSamples = (minSamples < 5) ? 5 : minSamples;
   Reset();
  }

void CClassPrior::Reset(void)
  {
   m_count = 0;
   for(int i = 0; i < 64; i++)
     {
      m_items[i].key = "";
      m_items[i].samples = 0;
      m_items[i].wins = 0;
      m_items[i].winRate = 0.0;
     }
  }

//------------------------------------------------------------------//
string CClassPrior::Key(const ENUM_QME_SIDE side, const ENUM_QME_REGIME regime,
                        const ENUM_QME_ZONE_SOURCE source)
  {
   return(QmeSideName(side) + "|" + QmeRegimeName(regime) + "|" + QmeZoneSourceName(source));
  }

//------------------------------------------------------------------//
void CClassPrior::Observe(const string key, const bool win)
  {
   if(StringLen(key) == 0) return;
   for(int i = 0; i < m_count; i++)
     {
      if(m_items[i].key != key) continue;
      m_items[i].samples++;
      if(win) m_items[i].wins++;
      m_items[i].winRate = (double)m_items[i].wins / (double)m_items[i].samples;
      return;
     }
   if(m_count >= 64) return;   // capacity: ignore further classes
   m_items[m_count].key = key;
   m_items[m_count].samples = 1;
   m_items[m_count].wins = win ? 1 : 0;
   m_items[m_count].winRate = win ? 1.0 : 0.0;
   m_count++;
  }

//------------------------------------------------------------------//
bool CClassPrior::Get(const string key, SClassPrior &out)
  {
   for(int i = 0; i < m_count; i++)
     {
      if(m_items[i].key != key) continue;
      out = m_items[i];
      return(out.samples >= m_minSamples);
     }
   out.key = key;
   out.samples = 0;
   out.wins = 0;
   out.winRate = 0.0;
   return(false);
  }

//------------------------------------------------------------------//
bool CClassPrior::WinRate(const string key, double &rate, int &samples)
  {
   SClassPrior p;
   const bool ok = Get(key, p);
   rate = p.winRate;
   samples = p.samples;
   return(ok);
  }

//------------------------------------------------------------------//
string CClassPrior::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
      s += "prior;" + m_items[i].key + ";" + IntegerToString(m_items[i].samples) + ";" +
           IntegerToString(m_items[i].wins) + "\n";
   return(s);
  }

//------------------------------------------------------------------//
bool CClassPrior::Deserialize(const string blob)
  {
   if(StringLen(blob) == 0) return(false);
   Reset();
   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], ';', f) < 4) continue;
      if(f[0] != "prior") continue;
      if(m_count >= 64) break;
      m_items[m_count].key = f[1];
      m_items[m_count].samples = (int)StringToInteger(f[2]);
      m_items[m_count].wins = (int)StringToInteger(f[3]);
      m_items[m_count].winRate = (m_items[m_count].samples > 0) ?
                                 (double)m_items[m_count].wins / (double)m_items[m_count].samples : 0.0;
      m_count++;
      loaded++;
     }
   return(loaded > 0);
  }

#endif // __QME_INTEL_CLASSPRIOR_MQH__
//+------------------------------------------------------------------+
