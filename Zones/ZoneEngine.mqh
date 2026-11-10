//+------------------------------------------------------------------+
//|                                              Zones/ZoneEngine     |
//|  Per-symbol zone orchestrator.                                      |
//|                                                                   |
//|  Flow: SMarketAnalysis -> CZoneBuilder -> CZoneBoard (merge/dedup)   |
//|        -> lifecycle update -> prune -> queries for the strategy.     |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_ZONEENGINE_MQH__
#define __QME_ZONES_ZONEENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "../Data/BarSeries.mqh"
#include "ZoneBuilder.mqh"
#include "ZoneBoard.mqh"
#include "TopZones.mqh"

class CZoneEngine
  {
private:
   CZoneBoard        m_board;
   string            m_symbol;
   int               m_maxAgeHours;
   double            m_mergePct;
   int               m_lastBuilt;
   bool              m_initialized;

public:
   bool              Init(const string symbol, const int maxAgeHours, const double mergePct);
   void              Shutdown(void);

   //--- build/refresh zones from one analysis result
   int               Update(const SMarketAnalysis &a, CBarSeries &series,
                            const datetime now, const double point);

   CZoneBoard*       Board(void) { return(&m_board); }
   int               Count(void) { return(m_board.Count()); }
   int               ActiveCount(const datetime now) { return(m_board.ActiveCount(now)); }

   bool              BestZone(const ENUM_QME_SIDE side, const double price,
                              const double atr, const datetime now,
                              const double maxDistAtr, STradingZone &out);
   bool              ZoneAtPrice(const ENUM_QME_SIDE side, const double price,
                                 const datetime now, STradingZone &out);
   int               TopForSide(const ENUM_QME_SIDE side, const double price,
                                const double atr, const datetime now,
                                const int maxCount, SRankedZone &out[]);
   string            Describe(void) { return(m_board.Describe()); }
   string            Symbol(void) { return(m_symbol); }
  };

//------------------------------------------------------------------//
bool CZoneEngine::Init(const string symbol, const int maxAgeHours, const double mergePct)
  {
   m_symbol = symbol;
   m_maxAgeHours = (maxAgeHours > 0) ? maxAgeHours : 72;
   m_mergePct = QmeClamp(mergePct, 0.0, 100.0);
   m_lastBuilt = 0;
   m_board.Init(symbol);
   m_initialized = true;
   return(true);
  }

//------------------------------------------------------------------//
void CZoneEngine::Shutdown(void)
  {
   m_board.Clear();
   m_initialized = false;
  }

//------------------------------------------------------------------//
int CZoneEngine::Update(const SMarketAnalysis &a, CBarSeries &series,
                        const datetime now, const double point)
  {
   if(!m_initialized) return(0);
   if(!a.valid) return(0);

   const double atr = MathMax(a.atr, point * 10.0);

   STradingZone zones[];

   //--- order blocks
   int n = CZoneBuilder::FromOrderBlocks(a.symbol, a.tf, a.orderBlocks, a.obCount,
                                         point, atr, now, m_maxAgeHours,
                                         QME_MAX_ZONES_PER_TF, zones);
   for(int i = 0; i < n; i++) m_board.AddOrMerge(zones[i], m_mergePct);

   //--- fair value gaps
   n = CZoneBuilder::FromFvgs(a.symbol, a.tf, a.fvgs, a.fvgCount, point, atr, now,
                              m_maxAgeHours, QME_MAX_ZONES_PER_TF, zones);
   for(int i = 0; i < n; i++) m_board.AddOrMerge(zones[i], m_mergePct);

   //--- liquidity-derived zones
   n = CZoneBuilder::FromLiquidity(a.symbol, a.tf, a.liquidity.map, point, atr, now,
                                   m_maxAgeHours, QME_MAX_ZONES_PER_TF, zones);
   for(int i = 0; i < n; i++) m_board.AddOrMerge(zones[i], m_mergePct);

   //--- structural swing levels
   n = CZoneBuilder::FromSwingRange(a.symbol, a.tf, a.structure, point, atr, now,
                                    m_maxAgeHours, zones);
   for(int i = 0; i < n; i++) m_board.AddOrMerge(zones[i], m_mergePct);

   //--- volume nodes (only for the setup timeframe result)
   n = CZoneBuilder::FromVolumeProfile(a.symbol, a.tf, a.volumeProfile, point, atr, now,
                                       m_maxAgeHours, 4, zones);
   for(int i = 0; i < n; i++) m_board.AddOrMerge(zones[i], m_mergePct);

   //--- lifecycle + retention
   m_board.Update(series, now, atr, point);
   m_board.Prune(now, m_maxAgeHours * 2, a.price, atr);

   m_lastBuilt = m_board.Count();
   return(m_lastBuilt);
  }

//------------------------------------------------------------------//
bool CZoneEngine::BestZone(const ENUM_QME_SIDE side, const double price,
                           const double atr, const datetime now,
                           const double maxDistAtr, STradingZone &out)
  {
   return(m_board.BestForSide(side, price, atr, now, maxDistAtr, out));
  }

//------------------------------------------------------------------//
bool CZoneEngine::ZoneAtPrice(const ENUM_QME_SIDE side, const double price,
                              const datetime now, STradingZone &out)
  {
   return(m_board.ZoneAtPrice(side, price, now, out));
  }

//------------------------------------------------------------------//
int CZoneEngine::TopForSide(const ENUM_QME_SIDE side, const double price,
                            const double atr, const datetime now,
                            const int maxCount, SRankedZone &out[])
  {
   return(CTopZones::Select(m_board, side, price, atr, now, maxCount, out));
  }

#endif // __QME_ZONES_ZONEENGINE_MQH__
//+------------------------------------------------------------------+
