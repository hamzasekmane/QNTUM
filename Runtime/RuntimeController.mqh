//+------------------------------------------------------------------+
//|                                   Runtime/RuntimeController       |
//|  Owns the engine's operating mode and the kill switch.               |
//|                                                                   |
//|  MODES                                                            |
//|    ANALYSIS   : analyse and explain, never send anything              |
//|    LIVE       : DEMO or REAL, both authorized by the permission layer  |
//|    PAUSED     : no new trades, open positions keep being monitored     |
//|    FAULT      : a safety check failed; no new trades until cleared     |
//|    STOPPING   : shutdown in progress                                  |
//|                                                                   |
//|  The controller can only ever REDUCE what is allowed. It cannot grant  |
//|  trading: authorization stays with CTradingPermissions.               |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_CONTROLLER_MQH__
#define __QME_RUNTIME_CONTROLLER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountContext.mqh"
#include "../Account/TradingPermissions.mqh"

enum ENUM_QME_RUNTIME_STATE
  {
   QME_RT_INIT = 0,
   QME_RT_ANALYSIS,
   QME_RT_LIVE,
   QME_RT_PAUSED,
   QME_RT_FAULT,
   QME_RT_STOPPING,
   QME_RT_STOPPED
  };

class CRuntimeController
  {
private:
   ENUM_QME_RUNTIME_STATE m_state;
   string            m_reason;
   datetime          m_changed;
   long              m_pauses;
   long              m_kills;

public:
                     CRuntimeController(void);
   void              Init(const CConfig &cfg, const SAccountContext &acc);
   void              Shutdown(void);

   bool              MayTrade(const CConfig &cfg, const SAccountContext &acc,
                              const bool sessionAllowed, string &why);
   void              Pause(const string reason);
   void              Resume(const string reason);
   void              Fault(const string reason);
   void              BeginStop(void);
   void              Stopped(void);

   ENUM_QME_RUNTIME_STATE State(void) { return(m_state); }
   string            Reason(void) { return(m_reason); }
   datetime          Changed(void) { return(m_changed); }
   bool              IsLive(void) { return(m_state == QME_RT_LIVE); }
   long              Pauses(void) { return(m_pauses); }
   long              Kills(void) { return(m_kills); }
   string            Describe(void);
  };

//------------------------------------------------------------------//
CRuntimeController::CRuntimeController(void)
  {
   m_state = QME_RT_INIT;
   m_reason = "not started";
   m_changed = 0;
   m_pauses = 0;
   m_kills = 0;
  }

//------------------------------------------------------------------//
void CRuntimeController::Init(const CConfig &cfg, const SAccountContext &acc)
  {
   m_changed = TimeCurrent();

   if(cfg.In.analysisOnly)
     {
      m_state = QME_RT_ANALYSIS;
      m_reason = "analysisOnly is enabled";
      return;
     }

   if(acc.mode == QME_ACC_UNKNOWN)
     {
      m_state = QME_RT_ANALYSIS;
      m_reason = "account mode unknown: trading is never authorized";
      QmeLogMsg(QME_LOG_WARN, "Controller", m_reason);
      return;
     }

   if(acc.mode == QME_ACC_REAL || acc.mode == QME_ACC_CONTEST)
     {
      if(!(cfg.In.enableRealTrading && cfg.In.realTradingArmed && !cfg.In.analysisOnly))
        {
         m_state = QME_RT_ANALYSIS;
         m_reason = "REAL account but real trading is not enabled/armed";
         return;
        }
     }
   else if(!(cfg.In.enableDemoTrading && !cfg.In.analysisOnly))
     {
      m_state = QME_RT_ANALYSIS;
      m_reason = "DEMO account but demo trading is not enabled";
      return;
     }

   m_state = QME_RT_LIVE;
   m_reason = "trading authorized by configuration and account mode";
   QmeLogMsg(QME_LOG_INFO, "Controller", "runtime LIVE: " + m_reason);
  }

//------------------------------------------------------------------//
void CRuntimeController::Shutdown(void)
  {
   m_state = QME_RT_STOPPED;
   m_reason = "stopped";
   m_changed = TimeCurrent();
  }

//------------------------------------------------------------------//
bool CRuntimeController::MayTrade(const CConfig &cfg, const SAccountContext &acc,
                                  const bool sessionAllowed, string &why)
  {
   why = "";
   if(m_state == QME_RT_LIVE) return(true);

   if(m_state == QME_RT_ANALYSIS)
     {
      why = "analysis mode: " + m_reason;
      return(false);
     }
   if(m_state == QME_RT_PAUSED)
     {
      why = "paused: " + m_reason;
      return(false);
     }
   if(m_state == QME_RT_FAULT)
     {
      why = "fault: " + m_reason;
      return(false);
     }
   if(m_state == QME_RT_STOPPING || m_state == QME_RT_STOPPED)
     {
      why = "engine stopping";
      return(false);
     }

   //--- never started
   why = "engine not started";
   return(false);
  }

//------------------------------------------------------------------//
void CRuntimeController::Pause(const string reason)
  {
   if(m_state == QME_RT_FAULT || m_state == QME_RT_STOPPING || m_state == QME_RT_STOPPED) return;
   m_state = QME_RT_PAUSED;
   m_reason = reason;
   m_changed = TimeCurrent();
   m_pauses++;
   QmeLogMsg(QME_LOG_WARN, "Controller", "paused: " + reason);
  }

void CRuntimeController::Resume(const string reason)
  {
   if(m_state != QME_RT_PAUSED) return;
   m_state = QME_RT_LIVE;
   m_reason = reason;
   m_changed = TimeCurrent();
   QmeLogMsg(QME_LOG_INFO, "Controller", "resumed: " + reason);
  }

void CRuntimeController::Fault(const string reason)
  {
   m_state = QME_RT_FAULT;
   m_reason = reason;
   m_changed = TimeCurrent();
   m_kills++;
   QmeLogMsg(QME_LOG_ERROR, "Controller", "FAULT: " + reason);
  }

void CRuntimeController::BeginStop(void)
  {
   m_state = QME_RT_STOPPING;
   m_reason = "shutdown requested";
   m_changed = TimeCurrent();
  }

void CRuntimeController::Stopped(void) { Shutdown(); }

//------------------------------------------------------------------//
string CRuntimeController::Describe(void)
  {
   string name = "INIT";
   switch(m_state)
     {
      case QME_RT_INIT:      name = "INIT";      break;
      case QME_RT_ANALYSIS:  name = "ANALYSIS";  break;
      case QME_RT_LIVE:      name = "LIVE";      break;
      case QME_RT_PAUSED:    name = "PAUSED";    break;
      case QME_RT_FAULT:     name = "FAULT";     break;
      case QME_RT_STOPPING:  name = "STOPPING";  break;
      case QME_RT_STOPPED:   name = "STOPPED";   break;
     }
   return("runtime " + name + " (" + m_reason + ")");
  }

#endif // __QME_RUNTIME_CONTROLLER_MQH__
//+------------------------------------------------------------------+
