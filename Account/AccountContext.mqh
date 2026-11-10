//+------------------------------------------------------------------+
//|                                        Account/AccountContext.mqh |
//|  QuantumMarketEngine — single source of truth about the account.   |
//|                                                                   |
//|  Owns:   SAccountContext snapshot                                 |
//|          CAccountState  (daily P/L, drawdown, loss streak)          |
//|  Public: Init(), Refresh(), State(), Snapshot(),                    |
//|          Authority() -> is this account allowed to trade at all     |
//|  Every read is validated: a stale or disconnected terminal yields   |
//|  valid=false and no module may trade on invalid account data.       |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_CONTEXT_MQH__
#define __QME_ACCOUNT_CONTEXT_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "AccountModeDetector.mqh"
#include "AccountState.mqh"
#include "MarginManager.mqh"
#include "TradingPermissions.mqh"

class CAccountContext
  {
private:
   SAccountContext   m_acc;
   CAccountState     m_state;
   datetime          m_lastRefresh;
   int               m_refreshSec;
   ulong             m_magic;

public:
                     CAccountContext(void);

   bool              Init(const SInputs &in, const ulong magic, string &err);
   void              Shutdown(void);

   //--- pull fresh account numbers; returns false when they are unusable
   bool              Refresh(void);

   SAccountContext   Snapshot(void) { return(m_acc); }
   CAccountState*    State(void) { return(&m_state); }
   long              Login(void) { return(m_acc.login); }

   ENUM_QME_ACCOUNT_MODE Mode(void) { return(m_acc.mode); }
   bool              IsDemo(void) { return(m_acc.mode == QME_ACC_DEMO); }
   bool              IsReal(void) { return(m_acc.mode == QME_ACC_REAL || m_acc.mode == QME_ACC_CONTEST); }
   double            Equity(void) { return(m_acc.equity); }
   double            Balance(void) { return(m_acc.balance); }
   double            DailyPlPct(void) { return(m_state.DailyPlPct(m_acc)); }
   double            DrawdownPct(void) { return(m_state.DrawdownPct(m_acc)); }
   datetime          LastRefresh(void) { return(m_lastRefresh); }

   //--- is the account in a state where trading is even theoretically possible?
   bool              Authority(string &note);
  };

//------------------------------------------------------------------//
CAccountContext::CAccountContext(void)
  {
   QmeAccountClear(m_acc);
   m_lastRefresh = 0;
   m_refreshSec = 5;
   m_magic = 0;
  }

//------------------------------------------------------------------//
bool CAccountContext::Init(const SInputs &in, const ulong magic, string &err)
  {
   err = "";
   m_magic = magic;
   m_refreshSec = 5;

   m_acc.mode = CAccountModeDetector::Detect();
   if(m_acc.mode == QME_ACC_UNKNOWN)
     {
      err = "account trade mode is not DEMO/CONTEST/REAL — trading will never be authorized";
      QmeLogMsg(QME_LOG_WARN, "Account", err);
     }

   if(!Refresh())
     {
      err = "account refresh failed during init";
      return(false);
     }

   m_state.Init(m_acc);
   //--- authoritative streak / realised P/L from broker history
   m_state.SyncFromHistory(magic, TimeCurrent());

   QmeLogMsg(QME_LOG_INFO, "Account", CAccountModeDetector::Describe());
   QmeLogMsg(QME_LOG_INFO, "Account", CTradingPermissions::AuthorizationSummary(in, m_acc));
   QmeLogMsg(QME_LOG_INFO, "Account", "equity=" + QmeFmtMoney(m_acc.equity) +
             " free=" + QmeFmtMoney(m_acc.freeMargin) +
             " leverage=1:" + IntegerToString(m_acc.leverage) +
             " currency=" + m_acc.currency);
   return(true);
  }

//------------------------------------------------------------------//
void CAccountContext::Shutdown(void)
  {
   QmeLogMsg(QME_LOG_INFO, "Account", "shutdown, last equity=" + QmeFmtMoney(m_acc.equity));
  }

//------------------------------------------------------------------//
bool CAccountContext::Refresh(void)
  {
   const datetime now = TimeCurrent();
   if(m_lastRefresh > 0 && now - m_lastRefresh < m_refreshSec && m_acc.valid)
     {
      //--- cheap path: still update the volatile numbers
      m_acc.equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      m_acc.margin     = AccountInfoDouble(ACCOUNT_MARGIN);
      m_acc.freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      m_acc.marginLevel= AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      m_acc.profit     = AccountInfoDouble(ACCOUNT_PROFIT);
      m_acc.updated    = now;
      m_state.Update(m_acc);
      return(true);
     }

   QmeAccountClear(m_acc);
   m_acc.mode      = CAccountModeDetector::Detect();
   m_acc.login     = AccountInfoInteger(ACCOUNT_LOGIN);
   m_acc.server    = AccountInfoString(ACCOUNT_SERVER);
   m_acc.company   = AccountInfoString(ACCOUNT_COMPANY);
   m_acc.currency  = AccountInfoString(ACCOUNT_CURRENCY);
   m_acc.leverage  = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   m_acc.balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   m_acc.equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   m_acc.margin    = AccountInfoDouble(ACCOUNT_MARGIN);
   m_acc.freeMargin= AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   m_acc.marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   m_acc.credit    = AccountInfoDouble(ACCOUNT_CREDIT);
   m_acc.profit    = AccountInfoDouble(ACCOUNT_PROFIT);

   m_acc.accountTradeAllowed = CTradingPermissions::AccountTradeAllowed();
   m_acc.expertTradeAllowed  = CTradingPermissions::AccountExpertAllowed();
   m_acc.terminalTradeAllowed= CTradingPermissions::TerminalTradingAllowed();
   m_acc.mqlTradeAllowed     = CTradingPermissions::MqlTradingAllowed();
   m_acc.connected  = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   m_acc.updated    = now;

   m_acc.valid = (m_acc.login > 0 && m_acc.equity > 0.0 && QmeIsFinite(m_acc.equity));

   m_state.Update(m_acc);
   m_state.RollDay(TimeTradeServer(), m_acc);
   m_lastRefresh = now;

   if(!m_acc.valid)
     {
      QmeLogMsg(QME_LOG_WARN, "Account", "account snapshot invalid (login=" +
                IntegerToString(m_acc.login) + " equity=" + QmeFmtMoney(m_acc.equity) + ")");
      return(false);
     }
   return(true);
  }

//------------------------------------------------------------------//
bool CAccountContext::Authority(string &note)
  {
   note = "";
   if(!m_acc.valid)
     {
      note = "account snapshot invalid";
      return(false);
     }
   if(!m_acc.connected)
     {
      note = "terminal not connected to the trade server";
      return(false);
     }
   if(!CAccountModeDetector::IsTradableMode(m_acc.mode))
     {
      note = "account mode cannot be traded";
      return(false);
     }
   if(!m_acc.terminalTradeAllowed)
     {
      note = "terminal AutoTrading disabled";
      return(false);
     }
   if(!m_acc.mqlTradeAllowed)
     {
      note = "algo trading disabled for this EA";
      return(false);
     }
   return(true);
  }

#endif // __QME_ACCOUNT_CONTEXT_MQH__
//+------------------------------------------------------------------+
