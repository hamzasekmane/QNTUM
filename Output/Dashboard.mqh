//+------------------------------------------------------------------+
//|                                            Output/Dashboard       |
//|  On-chart panel. Reads nothing by itself: the caller supplies rows.    |
//|                                                                   |
//|  Kept deliberately dumb so it can never influence trading. All         |
//|  numbers come from the engine's own state through SDashboardData.      |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_DASHBOARD_MQH__
#define __QME_OUT_DASHBOARD_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

#define QME_DASH_ROWS 16

struct SDashboardData
  {
   string            title;
   string            mode;
   string            health;
   string            account;
   string            scanner;
   string            signals;
   string            risk;
   string            execution;
   string            persistence;
   string            session;
   string            performance;
   string            alerts;
   string            lastDecision;
   string            footer;
  };

void QmeDashboardClear(SDashboardData &d)
  {
   d.title = ""; d.mode = ""; d.health = ""; d.account = ""; d.scanner = "";
   d.signals = ""; d.risk = ""; d.execution = ""; d.persistence = "";
   d.session = ""; d.performance = ""; d.alerts = ""; d.lastDecision = ""; d.footer = "";
  }

class CDashboard
  {
private:
   bool              m_enabled;
   bool              m_created;
   string            m_prefix;
   int               m_x;
   int               m_y;
   int               m_width;
   int               m_lineHeight;
   int               m_drawnRows;
   datetime          m_lastUpdate;

   void              DeleteObjects(void);
   void              EnsureLabel(const int index, const int total);
   void              SetLabel(const int index, const string text, const color clr);

public:
                     CDashboard(void);
   bool              Init(const bool enabled, const int x, const int y, const int width);
   void              Shutdown(void);
   bool              Update(SDashboardData &data);
   bool              Enabled(void) { return(m_enabled); }
   datetime          LastUpdate(void) { return(m_lastUpdate); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CDashboard::CDashboard(void)
  {
   m_enabled = false;
   m_created = false;
   m_prefix = "qme_dash_";
   m_x = 12;
   m_y = 24;
   m_width = 430;
   m_lineHeight = 15;
   m_drawnRows = 0;
   m_lastUpdate = 0;
  }

//------------------------------------------------------------------//
bool CDashboard::Init(const bool enabled, const int x, const int y, const int width)
  {
   m_enabled = enabled;
   m_x = MathMax(x, 0);
   m_y = MathMax(y, 0);
   m_width = MathMax(width, 260);
   m_drawnRows = 0;
   m_created = false;
   if(!m_enabled) return(true);

   DeleteObjects();

   //--- panel background
   const string bg = m_prefix + "bg";
   if(ObjectFind(0, bg) < 0)
     {
      if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return(false);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, m_x - 6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, m_y - 6);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, m_width);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, m_lineHeight * (QME_DASH_ROWS + 1) + 12);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'18,22,28');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'60,70,85');
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   m_created = true;
   return(true);
  }

//------------------------------------------------------------------//
void CDashboard::DeleteObjects(void)
  {
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      const string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, m_prefix) != 0) continue;
      ObjectDelete(0, name);
     }
   m_created = false;
  }

//------------------------------------------------------------------//
void CDashboard::EnsureLabel(const int index, const int total)
  {
   const string name = m_prefix + "row" + IntegerToString(index);
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + index * m_lineHeight);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
  }

//------------------------------------------------------------------//
void CDashboard::SetLabel(const int index, const string text, const color clr)
  {
   const string name = m_prefix + "row" + IntegerToString(index);
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//------------------------------------------------------------------//
bool CDashboard::Update(SDashboardData &data)
  {
   if(!m_enabled) return(false);
   if(!m_created && !Init(true, m_x, m_y, m_width)) return(false);

   string rows[QME_DASH_ROWS];
   color colors[QME_DASH_ROWS];

   rows[0] = "  " + data.title;                      colors[0] = C'200,210,225';
   rows[1] = "  mode      : " + data.mode;           colors[1] = C'120,200,255';
   rows[2] = "  health    : " + data.health;         colors[2] = C'150,230,150';
   rows[3] = "  account   : " + data.account;        colors[3] = C'200,200,200';
   rows[4] = "  session   : " + data.session;        colors[4] = C'200,200,200';
   rows[5] = "  scanner   : " + data.scanner;        colors[5] = C'200,200,200';
   rows[6] = "  signals   : " + data.signals;        colors[6] = C'200,200,200';
   rows[7] = "  risk      : " + data.risk;           colors[7] = C'230,200,140';
   rows[8] = "  execution : " + data.execution;      colors[8] = C'200,200,200';
   rows[9] = "  state     : " + data.persistence;    colors[9] = C'200,200,200';
   rows[10] = "  perf      : " + data.performance;   colors[10] = C'160,170,185';
   rows[11] = "  alerts    : " + data.alerts;        colors[11] = C'160,170,185';
   rows[12] = "  last      : " + data.lastDecision;  colors[12] = C'220,220,160';
   rows[13] = "  " + data.footer;                    colors[13] = C'110,120,135';

   for(int i = 0; i < QME_DASH_ROWS; i++)
     {
      if(StringLen(rows[i]) == 0) continue;
      EnsureLabel(i, QME_DASH_ROWS);
      SetLabel(i, rows[i], colors[i]);
      m_drawnRows = i + 1;
     }
   m_lastUpdate = TimeCurrent();
   ChartRedraw(0);
   return(true);
  }

//------------------------------------------------------------------//
void CDashboard::Shutdown(void)
  {
   DeleteObjects();
   m_enabled = false;
   ChartRedraw(0);
  }

//------------------------------------------------------------------//
string CDashboard::Describe(void)
  {
   return("dashboard " + (m_enabled ? "on" : "off") +
          " rows=" + IntegerToString(m_drawnRows) +
          (m_lastUpdate > 0 ? " updated=" + TimeToString(m_lastUpdate, TIME_MINUTES) : ""));
  }

#endif // __QME_OUT_DASHBOARD_MQH__
//+------------------------------------------------------------------+
