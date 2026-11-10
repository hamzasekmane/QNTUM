//+------------------------------------------------------------------+
//|                                              Zones/ZoneBoard      |
//|  Per-symbol zone collection with merging, deduplication, lifecycle    |
//|  maintenance and capacity control.                                  |
//|                                                                   |
//|  INVARIANTS                                                        |
//|   * two zones do not share an id;                                |
//|   * zones of the same side that overlap >= mergePct are merged into   |
//|     one record (union of boundaries, corroboration boost);            |
//|   * invalidated/expired zones never come back;                       |
//|   * the board never exceeds QME_MAX_ZONES_PER_SYMBOL.                 |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONEBOARD_MQH__
#define __QME_ZONES_ZONEBOARD_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Data/BarSeries.mqh"
#include "ZoneTypes.mqh"
#include "ZoneLifecycle.mqh"
#include "ZoneRanking.mqh"
#include "ZoneValidator.mqh"

class CZoneBoard
  {
private:
   STradingZone      m_zones[];
   string            m_symbol;
   int               m_merged;
   int               m_invalidated;
   int               FindById(const ulong id);

public:
                     CZoneBoard(void) { m_symbol = ""; m_merged = 0; m_invalidated = 0; }
   void              Init(const string symbol);
   void              Clear(void);

   //--- add, or merge into an overlapping zone of the same side
   bool              AddOrMerge(const STradingZone &z, const double mergePct);

   //--- lifecycle maintenance for every zone
   void              Update(CBarSeries &series, const datetime now, const double atr,
                            const double point);
   //--- drop terminal zones older than retentionHours and enforce capacity
   int               Prune(const datetime now, const int retentionHours,
                           const double price, const double atr);

   int               Count(void) { return(ArraySize(m_zones)); }
   int               ActiveCount(const datetime now) const;
   bool              At(const int i, STradingZone &out);
   bool              ById(const ulong id, STradingZone &out);
   int               MergedCount(void) { return(m_merged); }
   int               InvalidatedCount(void) { return(m_invalidated); }

   //--- best active zone for a side, closest to `price`
   bool              BestForSide(const ENUM_QME_SIDE side, const double price,
                                 const double atr, const datetime now,
                                 const double maxDistAtr, STradingZone &out);
   //--- active zone that contains the price for a side
   bool              ZoneAtPrice(const ENUM_QME_SIDE side, const double price,
                                 const datetime now, STradingZone &out);

   string            Describe(const int maxItems = 5);
   string            Symbol(void) { return(m_symbol); }
  };

//------------------------------------------------------------------//
void CZoneBoard::Init(const string symbol)
  {
   m_symbol = symbol;
   m_merged = 0;
   m_invalidated = 0;
   ArrayResize(m_zones, 0);
  }

void CZoneBoard::Clear(void)
  {
   ArrayResize(m_zones, 0);
   m_merged = 0;
   m_invalidated = 0;
  }

//------------------------------------------------------------------//
int CZoneBoard::FindById(const ulong id)
  {
   for(int i = 0; i < ArraySize(m_zones); i++)
      if(m_zones[i].id == id) return(i);
   return(-1);
  }

//------------------------------------------------------------------//
bool CZoneBoard::AddOrMerge(const STradingZone &z, const double mergePct)
  {
   if(z.id == 0) return(false);

   //--- exact identity: refresh corroboration, never duplicate
   const int same = FindById(z.id);
   if(same >= 0)
     {
      const double boost = MathMax(z.confidence * 0.5, 0.02);
      m_zones[same].confidence = QmeClamp(m_zones[same].confidence + boost, 0.0, 1.0);
      m_zones[same].strength = QmeClamp(m_zones[same].strength + boost * 0.5, 0.0, 1.0);
      m_zones[same].factorMask |= z.factorMask;
      if(z.expires > m_zones[same].expires) m_zones[same].expires = z.expires;
      return(true);
     }

   //--- overlapping zone of the same side: merge
   for(int i = 0; i < ArraySize(m_zones); i++)
     {
      if(m_zones[i].side != z.side) continue;
      if(m_zones[i].state == QME_ZSTAT_INVALIDATED || m_zones[i].state == QME_ZSTAT_EXPIRED) continue;
      if(!QmeZonesOverlap(m_zones[i], z, mergePct)) continue;

      //--- remember the old geometry so the invalidation buffer is preserved
      const double oldLo = MathMin(m_zones[i].upper, m_zones[i].lower);
      const double oldHi = MathMax(m_zones[i].upper, m_zones[i].lower);
      const double oldInv = m_zones[i].invalidateLevel;

      m_zones[i].upper = MathMax(m_zones[i].upper, z.upper);
      m_zones[i].lower = MathMin(m_zones[i].lower, z.lower);
      m_zones[i].strength = QmeClamp(MathMax(m_zones[i].strength, z.strength) + 0.05, 0.0, 1.0);
      m_zones[i].confidence = QmeClamp(MathMax(m_zones[i].confidence, z.confidence) + 0.08, 0.0, 1.0);
      m_zones[i].factorMask |= z.factorMask;
      if(z.created < m_zones[i].created) m_zones[i].created = z.created;
      if(z.expires > m_zones[i].expires) m_zones[i].expires = z.expires;
      //--- the stronger source defines the merged zone
      if(QmeZoneSourcePriority(z.source) > QmeZoneSourcePriority(m_zones[i].source))
         m_zones[i].source = z.source;
      //--- shift the invalidation level by the same buffer that was in use
      if(oldInv > 0.0)
        {
         if(m_zones[i].side == QME_SIDE_BUY)
           {
            const double buffer = MathMax(oldLo - oldInv, QmeZoneHeight(m_zones[i]) * 0.25);
            m_zones[i].invalidateLevel = MathMin(m_zones[i].upper, m_zones[i].lower) - buffer;
           }
         else if(m_zones[i].side == QME_SIDE_SELL)
           {
            const double buffer = MathMax(oldInv - oldHi, QmeZoneHeight(m_zones[i]) * 0.25);
            m_zones[i].invalidateLevel = MathMax(m_zones[i].upper, m_zones[i].lower) + buffer;
           }
        }
      m_merged++;
      return(true);
     }

   //--- capacity guard: refuse rather than grow without bound
   if(ArraySize(m_zones) >= QME_MAX_ZONES_PER_SYMBOL)
     {
      QmeLogMsg(QME_LOG_WARN, "ZoneBoard", m_symbol + " zone board full, dropping new zone");
      return(false);
     }

   const int n = ArraySize(m_zones);
   ArrayResize(m_zones, n + 1);
   m_zones[n] = z;
   return(true);
  }

//------------------------------------------------------------------//
void CZoneBoard::Update(CBarSeries &series, const datetime now, const double atr,
                        const double point)
  {
   for(int i = 0; i < ArraySize(m_zones); i++)
     {
      const ENUM_QME_ZONE_STATE before = m_zones[i].state;
      CZoneLifecycle::Update(m_zones[i], series, now, atr, point);
      if(before != QME_ZSTAT_INVALIDATED &&
         m_zones[i].state == QME_ZSTAT_INVALIDATED)
         m_invalidated++;
     }
  }

//------------------------------------------------------------------//
int CZoneBoard::Prune(const datetime now, const int retentionHours,
                      const double price, const double atr)
  {
   const int before = ArraySize(m_zones);
   //--- compact in place: keep everything that is still useful
   STradingZone kept[];
   ArrayResize(kept, 0);

   for(int i = 0; i < ArraySize(m_zones); i++)
     {
      const bool terminal = (m_zones[i].state == QME_ZSTAT_INVALIDATED ||
                             m_zones[i].state == QME_ZSTAT_EXPIRED);
      if(terminal && CZoneValidator::AgeHours(m_zones[i], now) > (double)retentionHours)
         continue;
      const int n = ArraySize(kept);
      ArrayResize(kept, n + 1);
      kept[n] = m_zones[i];
     }

   //--- capacity: if still full, keep the best ranked
   if(ArraySize(kept) > QME_MAX_ZONES_PER_SYMBOL)
     {
      CZoneRanking::SortByScore(kept, ArraySize(kept), price, atr, now);
      ArrayResize(kept, QME_MAX_ZONES_PER_SYMBOL);
     }

   ArrayResize(m_zones, ArraySize(kept));
   for(int i = 0; i < ArraySize(kept); i++) m_zones[i] = kept[i];
   return(before - ArraySize(m_zones));
  }

//------------------------------------------------------------------//
int CZoneBoard::ActiveCount(const datetime now) const
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_zones); i++)
      if(QmeZoneIsActive(m_zones[i], now)) n++;
   return(n);
  }

//------------------------------------------------------------------//
bool CZoneBoard::At(const int i, STradingZone &out)
  {
   QmeZoneClear(out);
   if(i < 0 || i >= ArraySize(m_zones)) return(false);
   out = m_zones[i];
   return(true);
  }

bool CZoneBoard::ById(const ulong id, STradingZone &out)
  {
   QmeZoneClear(out);
   const int i = FindById(id);
   if(i < 0) return(false);
   out = m_zones[i];
   return(true);
  }

//------------------------------------------------------------------//
bool CZoneBoard::BestForSide(const ENUM_QME_SIDE side, const double price,
                             const double atr, const datetime now,
                             const double maxDistAtr, STradingZone &out)
  {
   QmeZoneClear(out);
   double bestScore = -1.0;
   bool found = false;

   for(int i = 0; i < ArraySize(m_zones); i++)
     {
      if(m_zones[i].side != side) continue;
      if(!QmeZoneIsActive(m_zones[i], now)) continue;
      const double dist = CZoneValidator::DistanceAtr(m_zones[i], price, atr);
      if(dist > maxDistAtr) continue;
      const double s = CZoneRanking::Score(m_zones[i], price, atr, now, maxDistAtr);
      if(s > bestScore)
        {
         bestScore = s;
         out = m_zones[i];
         found = true;
        }
     }
   return(found);
  }

//------------------------------------------------------------------//
bool CZoneBoard::ZoneAtPrice(const ENUM_QME_SIDE side, const double price,
                             const datetime now, STradingZone &out)
  {
   QmeZoneClear(out);
   double best = -1.0;
   bool found = false;
   for(int i = 0; i < ArraySize(m_zones); i++)
     {
      if(m_zones[i].side != side) continue;
      if(!QmeZoneIsActive(m_zones[i], now)) continue;
      if(!QmeZoneContains(m_zones[i], price)) continue;
      const double s = m_zones[i].strength + m_zones[i].confidence;
      if(s > best)
        {
         best = s;
         out = m_zones[i];
         found = true;
        }
     }
   return(found);
  }

//------------------------------------------------------------------//
string CZoneBoard::Describe(const int maxItems)
  {
   string s = m_symbol + " zones=" + IntegerToString(ArraySize(m_zones)) +
              " merged=" + IntegerToString(m_merged);
   const int n = MathMin(maxItems, ArraySize(m_zones));
   for(int i = 0; i < n; i++)
      s += " [" + QmeSideName(m_zones[i].side) + " " + QmeZoneSourceName(m_zones[i].source) +
           " " + DoubleToString(m_zones[i].lower, 5) + "-" +
           DoubleToString(m_zones[i].upper, 5) + " " +
           QmeZoneStateName(m_zones[i].state) + "]";
   return(s);
  }

#endif // __QME_ZONES_ZONEBOARD_MQH__
//+------------------------------------------------------------------+
