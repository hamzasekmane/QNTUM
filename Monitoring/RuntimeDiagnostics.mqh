//+------------------------------------------------------------------+
//|                                 Monitoring/RuntimeDiagnostics     |
//|  One call that gathers the state of every component for support.      |
//|                                                                   |
//|  The dashboard shows a summary; this produces the full text that the  |
//|  user can paste into an incident report. It never invents values:      |
//|  components that are unavailable are reported as unavailable.          |
//+------------------------------------------------------------------+
#ifndef __QME_MON_DIAGNOSTICS_MQH__
#define __QME_MON_DIAGNOSTICS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Account/AccountContext.mqh"
#include "HealthMonitor.mqh"
#include "ErrorTracker.mqh"
#include "PerformanceMetrics.mqh"
#include "ExecutionStatistics.mqh"

class CRuntimeDiagnostics
  {
public:
   static string     Header(const CConfig &cfg, const SAccountContext &acc,
                            const ENUM_QME_ACCOUNT_MODE detected);
   static string     Compose(const CConfig &cfg, CAccountContext &account,
                             const string engineStatus, const string scannerStatus,
                             const string riskStatus, const string gatewayStatus,
                             const string persistenceStatus, const string controllerStatus,
                             const SHealthReport &health, CErrorTracker &errors,
                             CPerformanceMetrics &perf, CExecutionStatistics &exec);
   static string     AiSummary(const SHealthReport &health, CErrorTracker &errors,
                               CPerformanceMetrics &perf);
  };

//------------------------------------------------------------------//
string CRuntimeDiagnostics::Header(const CConfig &cfg, const SAccountContext &acc,
                                   const ENUM_QME_ACCOUNT_MODE detected)
  {
   string s = "\n=== QME DIAGNOSTICS " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " ===\n";
   s += "build        : " + QME_BUILD_TAG + "\n";
   s += "terminal     : " + TerminalInfoString(TERMINAL_NAME) + " " +
        IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)) + "\n";
   s += "server       : " + acc.server + "  login " + IntegerToString(acc.login) + "\n";
   s += "account mode : detected=" + QmeAccountModeName(detected) +
        " live=" + QmeAccountModeName(acc.mode) + "\n";
   s += "trading      : terminal=" + QmeBoolStr((bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) +
        " expert=" + QmeBoolStr((bool)MQLInfoInteger(MQL_TRADE_ALLOWED)) +
        " account=" + QmeBoolStr(acc.accountTradeAllowed) +
        " symbol=" + QmeBoolStr(acc.mqlTradeAllowed) + "\n";
   s += "authorization: demoTrading=" + QmeBoolStr(cfg.In.enableDemoTrading && !cfg.In.analysisOnly) +
        " realTrading=" + QmeBoolStr(cfg.RealTradingEnabled()) +
        " analysisOnly=" + QmeBoolStr(cfg.In.analysisOnly) + "\n";
   return(s);
  }

//------------------------------------------------------------------//
string CRuntimeDiagnostics::Compose(const CConfig &cfg, CAccountContext &account,
                                    const string engineStatus, const string scannerStatus,
                                    const string riskStatus, const string gatewayStatus,
                                    const string persistenceStatus, const string controllerStatus,
                                    const SHealthReport &health, CErrorTracker &errors,
                                    CPerformanceMetrics &perf, CExecutionStatistics &exec)
  {
   const SAccountContext acc = account.Snapshot();
   string s = Header(cfg, acc, acc.mode);
   s += "health       : " + CHealthMonitor::StatusName(health.status) +
        "  issues=" + health.issues + "\n";
   s += "engine       : " + engineStatus + "\n";
   s += "scanner      : " + scannerStatus + "\n";
   s += "risk         : " + riskStatus + "\n";
   s += "gateway      : " + gatewayStatus + "\n";
   s += "persistence  : " + persistenceStatus + "\n";
   s += "controller   : " + controllerStatus + "\n";
   s += "errors       : " + errors.Describe() + "\n";
   s += "performance  : " + perf.Describe() + "\n";
   s += "statistics   : " + exec.Describe() + "\n";
   s += "=== END DIAGNOSTICS ===\n";
   return(s);
  }

//------------------------------------------------------------------//
string CRuntimeDiagnostics::AiSummary(const SHealthReport &health, CErrorTracker &errors,
                                      CPerformanceMetrics &perf)
  {
   string s = "health " + CHealthMonitor::StatusName(health.status);
   if(health.status != QME_HEALTH_OK) s += " (" + health.issues + ")";
   if(errors.Total() > 0) s += ", errors " + IntegerToString((int)errors.Total());
   if(perf.SlowCycles() > 0) s += ", slow cycles " + IntegerToString((int)perf.SlowCycles());
   return(s);
  }

#endif // __QME_MON_DIAGNOSTICS_MQH__
//+------------------------------------------------------------------+
