//+------------------------------------------------------------------+
//|                                        Output/AlertEngine         |
//|  Fan-out for alerts: one call, every registered port.                 |
//|                                                                   |
//|  The engine owns the guard so the rate limiting cannot be skipped by   |
//|  a caller, and it survives a failing port: one broken channel never    |
//|  stops the others.                                                 |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_ALERTENGINE_MQH__
#define __QME_OUT_ALERTENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "AlertPort.mqh"
#include "AlertGuard.mqh"

#define QME_MAX_ALERT_PORTS 4

class CAlertEngine
  {
private:
   CAlertPort       *m_ports[QME_MAX_ALERT_PORTS];
   int               m_count;
   CAlertGuard       m_guard;
   long              m_attempts;
   long              m_delivered;
   bool              m_ready;

public:
                     CAlertEngine(void);
   void              Init(const ENUM_QME_SEVERITY floor, const int windowSec,
                          const int maxPerWindow, const int cooldownSec);
   bool              Add(CAlertPort *port);
   void              Shutdown(void);

   void              Notify(const ENUM_QME_SEVERITY sev, const string key,
                            const string title, const string text);
   void              Critical(const string key, const string title, const string text);
   void              Warn(const string key, const string title, const string text);
   void              Info(const string key, const string title, const string text);
   void              SetQuiet(const bool quiet) { m_guard.SetQuiet(quiet); }

   long              Attempts(void) { return(m_attempts); }
   long              Delivered(void) { return(m_delivered); }
   long              Suppressed(void) { return(m_guard.Suppressed()); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CAlertEngine::CAlertEngine(void)
  {
   m_count = 0;
   m_attempts = 0;
   m_delivered = 0;
   m_ready = false;
   for(int i = 0; i < QME_MAX_ALERT_PORTS; i++) m_ports[i] = NULL;
   m_guard.Init(QME_LOG_WARN, 300, 3, 60);
  }

//------------------------------------------------------------------//
void CAlertEngine::Init(const ENUM_QME_SEVERITY floor, const int windowSec,
                        const int maxPerWindow, const int cooldownSec)
  {
   m_count = 0;
   m_attempts = 0;
   m_delivered = 0;
   for(int i = 0; i < QME_MAX_ALERT_PORTS; i++) m_ports[i] = NULL;
   m_guard.Init(floor, windowSec, maxPerWindow, cooldownSec);
   m_ready = true;
  }

//------------------------------------------------------------------//
bool CAlertEngine::Add(CAlertPort *port)
  {
   if(port == NULL) return(false);
   if(m_count >= QME_MAX_ALERT_PORTS)
     {
      QmeLogMsg(QME_LOG_WARN, "Alerts", "port table full, cannot add " + port.Name());
      return(false);
     }
   m_ports[m_count] = port;
   m_count++;
   return(true);
  }

void CAlertEngine::Shutdown(void)
  {
   for(int i = 0; i < m_count; i++)
     {
      if(m_ports[i] == NULL) continue;
      //--- ports are owned by the caller: do not delete them here
      m_ports[i] = NULL;
     }
   m_count = 0;
   m_ready = false;
  }

//------------------------------------------------------------------//
void CAlertEngine::Notify(const ENUM_QME_SEVERITY sev, const string key,
                          const string title, const string text)
  {
   if(!m_ready) return;
   m_attempts++;

   string why = "";
   if(!m_guard.Allow(sev, key, title + "|" + text, TimeCurrent(), why))
     {
      if(StringLen(why) > 0 && why != "duplicate suppressed")
         QmeLogMsg(QME_LOG_DEBUG, "Alerts", "suppressed (" + why + "): " + title);
      return;
     }

   for(int i = 0; i < m_count; i++)
     {
      if(m_ports[i] == NULL) continue;
      if(!m_ports[i].Enabled()) continue;
      if(!m_ports[i].Send(sev, title, text))
         QmeLogMsg(QME_LOG_WARN, "Alerts", "port " + m_ports[i].Name() + " failed");
      else
         m_delivered++;
     }
  }

void CAlertEngine::Critical(const string key, const string title, const string text)
  { Notify(QME_LOG_CRITICAL, key, title, text); }
void CAlertEngine::Warn(const string key, const string title, const string text)
  { Notify(QME_LOG_WARN, key, title, text); }
void CAlertEngine::Info(const string key, const string title, const string text)
  { Notify(QME_LOG_INFO, key, title, text); }

//------------------------------------------------------------------//
string CAlertEngine::Describe(void)
  {
   int active = 0;
   for(int i = 0; i < m_count; i++)
      if(m_ports[i] != NULL && m_ports[i].Enabled()) active++;
   return("alerts ports=" + IntegerToString(m_count) +
          " active=" + IntegerToString(active) +
          " attempts=" + IntegerToString((int)m_attempts) +
          " delivered=" + IntegerToString((int)m_delivered) +
          " suppressed=" + IntegerToString((int)m_guard.Suppressed()));
  }

#endif // __QME_OUT_ALERTENGINE_MQH__
//+------------------------------------------------------------------+
