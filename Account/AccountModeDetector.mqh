//+------------------------------------------------------------------+
//|                                      Account/AccountModeDetector |
//|  QuantumMarketEngine — automatic DEMO / CONTEST / REAL detection.  |
//|                                                                   |
//|  Detection NEVER authorizes trading. Unknown modes stay UNKNOWN    |
//|  and can never be traded.                                          |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_MODEDETECTOR_MQH__
#define __QME_ACCOUNT_MODEDETECTOR_MQH__

#include "../Core/Enums.mqh"
#include "../Core/Utils.mqh"

class CAccountModeDetector
  {
public:
   //--- primary detector based on the native account property
   static ENUM_QME_ACCOUNT_MODE Detect(void);

   //--- consistency cross-check used for logging only.
   //--- Some brokers expose a company/server name that hints the mode; that
   //--- hint is NEVER used to override ACCOUNT_TRADE_MODE.
   static string     Describe(void);

   //--- can this mode ever be traded?
   static bool       IsTradableMode(const ENUM_QME_ACCOUNT_MODE m)
     { return(m == QME_ACC_DEMO || m == QME_ACC_REAL || m == QME_ACC_CONTEST); }
  };

//------------------------------------------------------------------//
ENUM_QME_ACCOUNT_MODE CAccountModeDetector::Detect(void)
  {
   const long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   switch(mode)
     {
      case ACCOUNT_TRADE_MODE_DEMO:    return(QME_ACC_DEMO);
      case ACCOUNT_TRADE_MODE_CONTEST: return(QME_ACC_CONTEST);
      case ACCOUNT_TRADE_MODE_REAL:    return(QME_ACC_REAL);
     }
   return(QME_ACC_UNKNOWN);
  }

//------------------------------------------------------------------//
string CAccountModeDetector::Describe(void)
  {
   const ENUM_QME_ACCOUNT_MODE m = Detect();
   const long login = AccountInfoInteger(ACCOUNT_LOGIN);
   const string server = AccountInfoString(ACCOUNT_SERVER);
   const string company = AccountInfoString(ACCOUNT_COMPANY);
   return(QmeAccountModeName(m) + " login=" + IntegerToString(login) +
          " server=" + server + " company=" + company);
  }

#endif // __QME_ACCOUNT_MODEDETECTOR_MQH__
//+------------------------------------------------------------------+
