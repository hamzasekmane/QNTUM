//+------------------------------------------------------------------+
//|                                          Output/AlertGuard        |
//|  Keeps alerts useful: no spam, no duplicates, no noise.               |
//|                                                                   |
//|  Rules:                                                           |
//|   * a severity floor (alerts below it are dropped);                   |
//|   * per-key rate limit (N alerts per window, key = symbol/reason);     |
//|   * identical text suppression inside a cooldown window;              |
//|   * optional quiet period after shutdown begins.                      |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_ALERTGUARD_MQH__
#define __QME_OUT_ALERTGUARD_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

#define QME_ALERT_KEYS 32

class CAlertGuard
  {
private:
   ENUM_QME_SEVERITY m_floor;
   int               m_windowSec;
   int               m_maxPerWindow;
   int               m_cooldownSec;
   bool              m_quiet;

   string            m_key[QME_ALERT_KEYS];
   string            m_lastText[QME_ALERT_KEYS];
   datetime          m_firstTime[QME_ALERT_KEYS];
   datetime          m_lastTime[QME_ALERT_KEYS];
   int               m_countInWindow[QME_ALERT_KEYS];
   int               m_keys;
   long              m_suppressed;

   int               IndexOf(const string key, const bool create);

public:
                     CAlertGuard(void);
   void              Init(const ENUM_QME_SEVERITY floor, const int windowSec,
                          const int maxPerWindow, const int cooldownSec);
   void              Reset(void) { m_keys = 0; m_suppressed = 0; m_quiet = false; }
   void              SetQuiet(const bool q) { m_quiet = q; }

   bool              Allow(const ENUM_QME_SEVERITY sev, const string key,
                           const string text, const datetime now, string &why);
   long              Suppressed(void) { return(m_suppressed); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CAlertGuard::CAlertGuard(void)
  {
   m_floor = QME_LOG_WARN;
   m_windowSec = 300;
   m_maxPerWindow = 3;
   m_cooldownSec = 60;
   m_keys = 0;
   m_suppressed = 0;
   m_quiet = false;
  }

void CAlertGuard::Init(const ENUM_QME_SEVERITY floor, const int windowSec,
                       const int maxPerWindow, const int cooldownSec)
  {
   m_floor = floor;
   m_windowSec = MathMax(windowSec, 10);
   m_maxPerWindow = MathMax(maxPerWindow, 1);
   m_cooldownSec = MathMax(cooldownSec, 0);
   Reset();
  }

//------------------------------------------------------------------//
int CAlertGuard::IndexOf(const string key, const bool create)
  {
   for(int i = 0; i < m_keys; i++)
      if(m_key[i] == key) return(i);
   if(!create || m_keys >= QME_ALERT_KEYS) return(-1);
   m_key[m_keys] = key;
   m_lastText[m_keys] = "";
   m_firstTime[m_keys] = 0;
   m_lastTime[m_keys] = 0;
   m_countInWindow[m_keys] = 0;
   m_keys++;
   return(m_keys - 1);
  }

//------------------------------------------------------------------//
bool CAlertGuard::Allow(const ENUM_QME_SEVERITY sev, const string key,
                        const string text, const datetime now, string &why)
  {
   why = "";
   if(m_quiet)
     {
      why = "quiet mode";
      m_suppressed++;
      return(false);
     }
   if((int)sev < (int)m_floor)
     {
      why = "below severity floor";
      m_suppressed++;
      return(false);
     }

   const int i = IndexOf(key, true);
   if(i < 0)
     {
      why = "alert key table full";
      m_suppressed++;
      return(false);
     }

   //--- window bookkeeping
   if(m_firstTime[i] == 0 || (now - m_firstTime[i]) >= m_windowSec)
     {
      m_firstTime[i] = now;
      m_countInWindow[i] = 0;
     }
   if(m_countInWindow[i] >= m_maxPerWindow)
     {
      why = "rate limit for " + key;
      m_suppressed++;
      return(false);
     }

   //--- identical text suppression
   if(m_lastText[i] == text && m_lastTime[i] > 0 && (now - m_lastTime[i]) < m_cooldownSec)
     {
      why = "duplicate suppressed";
      m_suppressed++;
      return(false);
     }

   m_lastText[i] = text;
   m_lastTime[i] = now;
   m_countInWindow[i]++;
   return(true);
  }

//------------------------------------------------------------------//
string CAlertGuard::Describe(void)
  {
   return("alerts keys=" + IntegerToString(m_keys) +
          " suppressed=" + IntegerToString((int)m_suppressed) +
          (m_quiet ? " quiet" : ""));
  }

#endif // __QME_OUT_ALERTGUARD_MQH__
//+------------------------------------------------------------------+
