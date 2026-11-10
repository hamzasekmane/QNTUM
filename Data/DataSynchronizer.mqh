//+------------------------------------------------------------------+
//|                                         Data/DataSynchronizer     |
//|  QuantumMarketEngine — knows when a NEW closed bar appeared.         |
//|                                                                   |
//|  Rationale: the analysis pipeline is only valid on closed bars, so   |
//|  re-running it between bar closes wastes CPU and can produce          |
//|  duplicate work. This class answers "did anything change?"            |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_DATASYNC_MQH__
#define __QME_DATA_DATASYNC_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "TimeframeContext.mqh"

class CDataSynchronizer
  {
private:
   string            m_key[QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES];
   datetime          m_seen[QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES];
   int               m_count;
   int               Find(const string key);

public:
                     CDataSynchronizer(void) { Reset(); }
   void              Reset(void);
   static string     Key(const string symbol, const ENUM_TIMEFRAMES tf);
   //--- never seen, or a newer closed bar is available
   bool              IsNewClosedBar(const string symbol, const ENUM_TIMEFRAMES tf,
                                    const datetime lastClosedBar);
   void              Commit(const string symbol, const ENUM_TIMEFRAMES tf,
                            const datetime lastClosedBar);
   datetime          LastSeen(const string symbol, const ENUM_TIMEFRAMES tf);
   int               Contexts(void) { return(m_count); }
  };

//------------------------------------------------------------------//
void CDataSynchronizer::Reset(void)
  {
   m_count = 0;
   for(int i = 0; i < QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES; i++)
     {
      m_key[i] = "";
      m_seen[i] = 0;
     }
  }

string CDataSynchronizer::Key(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   return(symbol + "_" + QmeTimeframeName(tf));
  }

int CDataSynchronizer::Find(const string key)
  {
   for(int i = 0; i < m_count; i++)
      if(m_key[i] == key) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CDataSynchronizer::IsNewClosedBar(const string symbol, const ENUM_TIMEFRAMES tf,
                                       const datetime lastClosedBar)
  {
   if(lastClosedBar <= 0) return(false);
   const int i = Find(Key(symbol, tf));
   if(i < 0) return(true);
   return(m_seen[i] != lastClosedBar);
  }

//------------------------------------------------------------------//
void CDataSynchronizer::Commit(const string symbol, const ENUM_TIMEFRAMES tf,
                               const datetime lastClosedBar)
  {
   const string key = Key(symbol, tf);
   const int i = Find(key);
   if(i >= 0)
     {
      m_seen[i] = lastClosedBar;
      return;
     }
   const int cap = QME_MAX_SYMBOLS * QME_MAX_TIMEFRAMES;
   if(m_count >= cap) return;
   m_key[m_count] = key;
   m_seen[m_count] = lastClosedBar;
   m_count++;
  }

//------------------------------------------------------------------//
datetime CDataSynchronizer::LastSeen(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   const int i = Find(Key(symbol, tf));
   return(i >= 0 ? m_seen[i] : 0);
  }

#endif // __QME_DATA_DATASYNC_MQH__
//+------------------------------------------------------------------+
