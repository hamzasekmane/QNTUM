//+------------------------------------------------------------------+
//|                                      Strategy/StrategyRegistry    |
//|  Named playbooks with independent enable switches and statistics.    |
//|                                                                   |
//|  A playbook is selected from the zone provenance + trigger:           |
//|   SWEEP_REVERSAL   : a liquidity sweep is present                     |
//|   OB_RETEST        : order-block zone                                 |
//|   FVG_CONTINUATION : fair-value-gap zone                              |
//|   LIQUIDITY_TARGET : previous day/week or session level zone          |
//|   SR_REVERSAL      : structural support/resistance zone               |
//|   GENERIC          : anything else (volume nodes, P/D)                |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_REGISTRY_MQH__
#define __QME_STRATEGY_REGISTRY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "MTF/CandidateClusterer.mqh"

struct SPlaybookStats
  {
   string            name;
   bool              enabled;
   long              signals;
   long              wins;
   long              losses;
   double            winRate;
  };

class CStrategyRegistry
  {
private:
   SPlaybookStats    m_items[16];
   int               m_count;
   int               Find(const string name);

public:
                     CStrategyRegistry(void) { Init(); }
   void              Init(void);
   int               Count(void) { return(m_count); }
   bool              At(const int i, SPlaybookStats &out);
   bool              IsEnabled(const string name);
   bool              SetEnabled(const string name, const bool enabled);
   void              RecordSignal(const string name);
   void              RecordOutcome(const string name, const bool win);
   string            PlaybookFor(const SMergedCandidate &mc);
   string            Report(void);
  };

//------------------------------------------------------------------//
void CStrategyRegistry::Init(void)
  {
   m_count = 0;
   const string names[6] = {"SWEEP_REVERSAL", "OB_RETEST", "FVG_CONTINUATION",
                            "LIQUIDITY_TARGET", "SR_REVERSAL", "GENERIC"};
   for(int i = 0; i < 6; i++)
     {
      m_items[m_count].name = names[i];
      m_items[m_count].enabled = true;
      m_items[m_count].signals = 0;
      m_items[m_count].wins = 0;
      m_items[m_count].losses = 0;
      m_items[m_count].winRate = 0.0;
      m_count++;
     }
  }

int CStrategyRegistry::Find(const string name)
  {
   for(int i = 0; i < m_count; i++)
      if(m_items[i].name == name) return(i);
   return(-1);
  }

bool CStrategyRegistry::At(const int i, SPlaybookStats &out)
  {
   if(i < 0 || i >= m_count) return(false);
   out = m_items[i];
   return(true);
  }

//------------------------------------------------------------------//
bool CStrategyRegistry::IsEnabled(const string name)
  {
   const int i = Find(name);
   if(i < 0) return(false);
   return(m_items[i].enabled);
  }

bool CStrategyRegistry::SetEnabled(const string name, const bool enabled)
  {
   const int i = Find(name);
   if(i < 0) return(false);
   m_items[i].enabled = enabled;
   return(true);
  }

//------------------------------------------------------------------//
void CStrategyRegistry::RecordSignal(const string name)
  {
   const int i = Find(name);
   if(i >= 0) m_items[i].signals++;
  }

void CStrategyRegistry::RecordOutcome(const string name, const bool win)
  {
   const int i = Find(name);
   if(i < 0) return;
   if(win) m_items[i].wins++;
   else    m_items[i].losses++;
   const long total = m_items[i].wins + m_items[i].losses;
   if(total > 0) m_items[i].winRate = (double)m_items[i].wins / (double)total;
  }

//------------------------------------------------------------------//
string CStrategyRegistry::PlaybookFor(const SMergedCandidate &mc)
  {
   if(mc.hasSweep) return("SWEEP_REVERSAL");
   switch(mc.cand.source)
     {
      case QME_ZONE_SRC_ORDER_BLOCK:      return("OB_RETEST");
      case QME_ZONE_SRC_FVG:              return("FVG_CONTINUATION");
      case QME_ZONE_SRC_PDH_PDL:
      case QME_ZONE_SRC_LIQUIDITY:
      case QME_ZONE_SRC_SESSION_RANGE:    return("LIQUIDITY_TARGET");
      case QME_ZONE_SRC_SUPPORT_RESISTANCE:return("SR_REVERSAL");
     }
   return("GENERIC");
  }

//------------------------------------------------------------------//
string CStrategyRegistry::Report(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      if(m_items[i].signals <= 0) continue;
      s += m_items[i].name + "=" + IntegerToString((int)m_items[i].signals) +
           "(" + QmeFmt(100.0 * m_items[i].winRate, 0) + "%) ";
     }
   return(s);
  }

#endif // __QME_STRATEGY_REGISTRY_MQH__
//+------------------------------------------------------------------+
