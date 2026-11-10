//+------------------------------------------------------------------+
//|                                  Output/VisualizationEngine      |
//|  Draws what the engine believes, on the chart, without clutter.       |
//|                                                                   |
//|  Only the cheapest, most useful objects are drawn: active zones for    |
//|  the chart symbol, the bias of the bias timeframe, and the last         |
//|  signal's entry/stop/target. Objects are namespaced and removed        |
//|  before each redraw, so nothing is ever orphaned on the chart.          |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_VISUALIZATION_MQH__
#define __QME_OUT_VISUALIZATION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Zones/ZoneEngine.mqh"
#include "../Strategy/SignalTypes.mqh"

class CVisualizationEngine
  {
private:
   bool              m_enabled;
   string            m_prefix;
   int               m_maxZones;
   int               m_drawnZones;
   long              m_draws;

   void              DeleteByPrefix(const string sub);
   bool              MakeZone(const int index, const STradingZone &z, const datetime t1,
                              const datetime t2);
   bool              MakeLevel(const string name, const double price, const color clr);

public:
                     CVisualizationEngine(void);
   void              Init(const bool enabled, const int maxZones);
   void              Shutdown(void);

   int               DrawZones(const string symbol, CZoneEngine &zones, const datetime now);
   bool              DrawBias(const string symbol, const ENUM_QME_SIDE side, const double score,
                              const ENUM_TIMEFRAMES tf);
   bool              DrawSignal(const STradingSignal &s);
   void              Clear(void);

   int               DrawnZones(void) { return(m_drawnZones); }
   long              Draws(void) { return(m_draws); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CVisualizationEngine::CVisualizationEngine(void)
  {
   m_enabled = false;
   m_prefix = "qme_vis_";
   m_maxZones = 8;
   m_drawnZones = 0;
   m_draws = 0;
  }

void CVisualizationEngine::Init(const bool enabled, const int maxZones)
  {
   m_enabled = enabled;
   m_maxZones = MathMax(MathMin(maxZones, 32), 1);
   m_drawnZones = 0;
   m_draws = 0;
  }

//------------------------------------------------------------------//
void CVisualizationEngine::DeleteByPrefix(const string sub)
  {
   const string full = m_prefix + sub;
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      const string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, full) != 0) continue;
      ObjectDelete(0, name);
     }
  }

//------------------------------------------------------------------//
bool CVisualizationEngine::MakeZone(const int index, const STradingZone &z,
                                    const datetime t1, const datetime t2)
  {
   const string name = m_prefix + "zone" + IntegerToString(index);
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, z.upper, t2, z.lower))
         return(false);
     }
   ObjectMove(0, name, 0, t1, z.upper);
   ObjectMove(0, name, 1, t2, z.lower);

   const color clr = (z.side == QME_SIDE_BUY) ? C'40,120,80' : C'140,60,60';
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   QmeZoneSourceName(z.source) + " " + QmeSideName(z.side) +
                   " strength " + QmeFmt(z.strength, 2) + " conf " + QmeFmt(z.confidence, 2));
   return(true);
  }

//------------------------------------------------------------------//
bool CVisualizationEngine::MakeLevel(const string name, const double price, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) return(false);
     }
   ObjectMove(0, name, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return(true);
  }

//------------------------------------------------------------------//
int CVisualizationEngine::DrawZones(const string symbol, CZoneEngine &zones, const datetime now)
  {
   if(!m_enabled) return(0);
   if(symbol != Symbol()) return(0);

   DeleteByPrefix("zone");
   m_drawnZones = 0;

   const int total = zones.Count();
   int drawn = 0;
   for(int i = 0; i < total && drawn < m_maxZones; i++)
     {
      STradingZone z;
      if(!zones.Board().At(i, z)) continue;
      if(z.state != QME_ZSTAT_FRESH && z.state != QME_ZSTAT_TESTED) continue;

      const int period = PeriodSeconds(z.tf);
      const datetime t1 = now - (datetime)(period * 6);
      const datetime t2 = now + (datetime)(period * 6);
      if(!MakeZone(drawn, z, t1, t2)) continue;
      drawn++;
     }
   m_drawnZones = drawn;
   m_draws++;
   ChartRedraw(0);
   return(drawn);
  }

//------------------------------------------------------------------//
bool CVisualizationEngine::DrawBias(const string symbol, const ENUM_QME_SIDE side,
                                    const double score, const ENUM_TIMEFRAMES tf)
  {
   if(!m_enabled || symbol != Symbol()) return(false);
   const string name = m_prefix + "bias";
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return(false);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
   ObjectSetString(0, name, OBJPROP_TEXT,
                   "QME bias " + QmeTfName(tf) + " " + QmeSideName(side) +
                   " " + QmeFmt(score, 2));
   ObjectSetInteger(0, name, OBJPROP_COLOR,
                    side == QME_SIDE_BUY ? C'90,200,120' :
                    (side == QME_SIDE_SELL ? C'220,110,110' : C'180,180,180'));
   ChartRedraw(0);
   return(true);
  }

//------------------------------------------------------------------//
bool CVisualizationEngine::DrawSignal(const STradingSignal &s)
  {
   if(!m_enabled || s.symbol != Symbol()) return(false);
   const bool okEntry = MakeLevel(m_prefix + "sig_entry", s.entry, C'120,180,255');
   const bool okSL    = MakeLevel(m_prefix + "sig_sl", s.stopLoss, C'220,90,90');
   const bool okTP    = MakeLevel(m_prefix + "sig_tp", s.takeProfit1, C'90,200,120');
   m_draws++;
   ChartRedraw(0);
   return(okEntry && okSL && okTP);
  }

//------------------------------------------------------------------//
void CVisualizationEngine::Clear(void)
  {
   DeleteByPrefix("");
   m_drawnZones = 0;
   ChartRedraw(0);
  }

void CVisualizationEngine::Shutdown(void)
  {
   if(m_enabled) Clear();
   m_enabled = false;
  }

//------------------------------------------------------------------//
string CVisualizationEngine::Describe(void)
  {
   return("visual " + (m_enabled ? "on" : "off") +
          " zones=" + IntegerToString(m_drawnZones) +
          " draws=" + IntegerToString((int)m_draws));
  }

#endif // __QME_OUT_VISUALIZATION_MQH__
//+------------------------------------------------------------------+
