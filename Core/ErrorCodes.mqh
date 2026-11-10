//+------------------------------------------------------------------+
//|                                                  ErrorCodes.mqh  |
//|  QuantumMarketEngine — internal error codes + broker retcode      |
//|  classification. No operation may fail silently: every failed     |
//|  call is mapped to a code here and logged with its retcode.       |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_ERRORCODES_MQH__
#define __QME_CORE_ERRORCODES_MQH__

#include "Constants.mqh"
#include "Enums.mqh"
#include "Utils.mqh"

//--- engine-level error codes (distinct from broker retcodes)
enum ENUM_QME_ERROR
  {
   QME_OK = 0,
   QME_ERR_CONFIG,
   QME_ERR_NOT_INITIALIZED,
   QME_ERR_ALREADY_INITIALIZED,
   QME_ERR_ACCOUNT_DETECTION,
   QME_ERR_SYMBOL_SELECT,
   QME_ERR_SYMBOL_INFO,
   QME_ERR_SYMBOL_NOT_TRADABLE,
   QME_ERR_BAR_DATA,
   QME_ERR_TICK_DATA,
   QME_ERR_INDICATOR_HANDLE,
   QME_ERR_INDICATOR_DATA,
   QME_ERR_DATA_QUALITY,
   QME_ERR_STALE_DATA,
   QME_ERR_STATE_LOAD,
   QME_ERR_STATE_SAVE,
   QME_ERR_RECONCILE_MISMATCH,
   QME_ERR_RISK_REJECTED,
   QME_ERR_EXECUTION_REJECTED,
   QME_ERR_EXECUTION_FAILED,
   QME_ERR_ORDER_SEND,
   QME_ERR_ORDER_CHECK,
   QME_ERR_CAPACITY_EXCEEDED,
   QME_ERR_INVALID_PARAMETER,
   QME_ERR_INTERNAL
  };

string QmeErrorName(const ENUM_QME_ERROR e)
  {
   switch(e)
     {
      case QME_OK:                       return("OK");
      case QME_ERR_CONFIG:               return("CONFIG");
      case QME_ERR_NOT_INITIALIZED:      return("NOT_INITIALIZED");
      case QME_ERR_ALREADY_INITIALIZED:  return("ALREADY_INITIALIZED");
      case QME_ERR_ACCOUNT_DETECTION:    return("ACCOUNT_DETECTION");
      case QME_ERR_SYMBOL_SELECT:        return("SYMBOL_SELECT");
      case QME_ERR_SYMBOL_INFO:          return("SYMBOL_INFO");
      case QME_ERR_SYMBOL_NOT_TRADABLE:  return("SYMBOL_NOT_TRADABLE");
      case QME_ERR_BAR_DATA:             return("BAR_DATA");
      case QME_ERR_TICK_DATA:            return("TICK_DATA");
      case QME_ERR_INDICATOR_HANDLE:     return("INDICATOR_HANDLE");
      case QME_ERR_INDICATOR_DATA:       return("INDICATOR_DATA");
      case QME_ERR_DATA_QUALITY:         return("DATA_QUALITY");
      case QME_ERR_STALE_DATA:           return("STALE_DATA");
      case QME_ERR_STATE_LOAD:           return("STATE_LOAD");
      case QME_ERR_STATE_SAVE:           return("STATE_SAVE");
      case QME_ERR_RECONCILE_MISMATCH:   return("RECONCILE_MISMATCH");
      case QME_ERR_RISK_REJECTED:        return("RISK_REJECTED");
      case QME_ERR_EXECUTION_REJECTED:   return("EXECUTION_REJECTED");
      case QME_ERR_EXECUTION_FAILED:     return("EXECUTION_FAILED");
      case QME_ERR_ORDER_SEND:           return("ORDER_SEND");
      case QME_ERR_ORDER_CHECK:          return("ORDER_CHECK");
      case QME_ERR_CAPACITY_EXCEEDED:    return("CAPACITY_EXCEEDED");
      case QME_ERR_INVALID_PARAMETER:    return("INVALID_PARAMETER");
      case QME_ERR_INTERNAL:             return("INTERNAL");
     }
   return("UNDEFINED");
  }

//+------------------------------------------------------------------+
//| Broker retcode -> text                                           |
//+------------------------------------------------------------------+
string QmeRetcodeText(const uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_REQUOTE:            return("REQUOTE");
      case TRADE_RETCODE_REJECT:             return("REJECT");
      case TRADE_RETCODE_CANCEL:             return("CANCEL");
      case TRADE_RETCODE_PLACED:             return("PLACED");
      case TRADE_RETCODE_DONE:               return("DONE");
      case TRADE_RETCODE_DONE_PARTIAL:       return("DONE_PARTIAL");
      case TRADE_RETCODE_ERROR:              return("ERROR");
      case TRADE_RETCODE_TIMEOUT:            return("TIMEOUT");
      case TRADE_RETCODE_INVALID:            return("INVALID");
      case TRADE_RETCODE_INVALID_VOLUME:     return("INVALID_VOLUME");
      case TRADE_RETCODE_INVALID_PRICE:      return("INVALID_PRICE");
      case TRADE_RETCODE_INVALID_STOPS:      return("INVALID_STOPS");
      case TRADE_RETCODE_TRADE_DISABLED:     return("TRADE_DISABLED");
      case TRADE_RETCODE_MARKET_CLOSED:      return("MARKET_CLOSED");
      case TRADE_RETCODE_NO_MONEY:           return("NO_MONEY");
      case TRADE_RETCODE_PRICE_CHANGED:      return("PRICE_CHANGED");
      case TRADE_RETCODE_PRICE_OFF:          return("PRICE_OFF");
      case TRADE_RETCODE_INVALID_EXPIRATION: return("INVALID_EXPIRATION");
      case TRADE_RETCODE_ORDER_CHANGED:      return("ORDER_CHANGED");
      case TRADE_RETCODE_TOO_MANY_REQUESTS:  return("TOO_MANY_REQUESTS");
      case TRADE_RETCODE_NO_CHANGES:         return("NO_CHANGES");
      case TRADE_RETCODE_SERVER_DISABLES_AT: return("SERVER_DISABLES_AT");
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return("CLIENT_DISABLES_AT");
      case TRADE_RETCODE_LOCKED:             return("LOCKED");
      case TRADE_RETCODE_FROZEN:             return("FROZEN");
      case TRADE_RETCODE_INVALID_FILL:       return("INVALID_FILL");
      case TRADE_RETCODE_CONNECTION:         return("CONNECTION");
      case TRADE_RETCODE_ONLY_REAL:          return("ONLY_REAL");
      case TRADE_RETCODE_LIMIT_ORDERS:       return("LIMIT_ORDERS");
      case TRADE_RETCODE_LIMIT_VOLUME:       return("LIMIT_VOLUME");
      case TRADE_RETCODE_INVALID_ORDER:      return("INVALID_ORDER");
      case TRADE_RETCODE_POSITION_CLOSED:    return("POSITION_CLOSED");
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME: return("INVALID_CLOSE_VOLUME");
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:  return("CLOSE_ORDER_EXIST");
      case TRADE_RETCODE_LIMIT_POSITIONS:    return("LIMIT_POSITIONS");
      case TRADE_RETCODE_REJECT_CANCEL:      return("REJECT_CANCEL");
      case TRADE_RETCODE_LONG_ONLY:          return("LONG_ONLY");
      case TRADE_RETCODE_SHORT_ONLY:         return("SHORT_ONLY");
      case TRADE_RETCODE_CLOSE_ONLY:         return("CLOSE_ONLY");
      case TRADE_RETCODE_FIFO_CLOSE:         return("FIFO_CLOSE");
      case TRADE_RETCODE_HEDGE_PROHIBITED:   return("HEDGE_PROHIBITED");
     }
   return("RETCODE_" + IntegerToString((int)code));
  }

//--- was the order actually accepted (position/order may exist)?
bool QmeRetcodeIsSuccess(const uint code)
  {
   return(code == TRADE_RETCODE_DONE ||
          code == TRADE_RETCODE_DONE_PARTIAL ||
          code == TRADE_RETCODE_PLACED);
  }

//+------------------------------------------------------------------+
//| Retry classification.                                             |
//| A timeout or connection loss is NEVER retried blindly: the order  |
//| may have reached the server. The gateway must reconcile first.    |
//+------------------------------------------------------------------+
ENUM_QME_RETRY_CLASS QmeClassifyRetcode(const uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_FROZEN:
         return(QME_RETRY_TRANSIENT);

      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_ERROR:
         return(QME_RETRY_NEVER_IDEMPOTENT);

      //--- permanent: repeating the same request cannot succeed
      case TRADE_RETCODE_INVALID_VOLUME:
      case TRADE_RETCODE_INVALID_PRICE:
      case TRADE_RETCODE_INVALID_STOPS:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_NO_MONEY:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_LONG_ONLY:
      case TRADE_RETCODE_SHORT_ONLY:
      case TRADE_RETCODE_CLOSE_ONLY:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_LIMIT_ORDERS:
      case TRADE_RETCODE_LIMIT_POSITIONS:
      case TRADE_RETCODE_ONLY_REAL:
      case TRADE_RETCODE_REJECT:
      case TRADE_RETCODE_INVALID:
      case TRADE_RETCODE_INVALID_ORDER:
      case TRADE_RETCODE_HEDGE_PROHIBITED:
      case TRADE_RETCODE_FIFO_CLOSE:
         return(QME_RETRY_NO);
     }
   return(QME_RETRY_NO);
  }

//+------------------------------------------------------------------+
//| OrderCheck retcode -> explicit rejection reason                  |
//+------------------------------------------------------------------+
ENUM_QME_REJECT QmeRejectFromRetcode(const uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_INVALID_STOPS:   return(QME_REJ_SL_INVALID);
      case TRADE_RETCODE_INVALID_VOLUME:  return(QME_REJ_VOLUME_INVALID);
      case TRADE_RETCODE_LIMIT_VOLUME:    return(QME_REJ_VOLUME_INVALID);
      case TRADE_RETCODE_NO_MONEY:        return(QME_REJ_MARGIN);
      case TRADE_RETCODE_MARKET_CLOSED:   return(QME_REJ_MARKET_CLOSED);
      case TRADE_RETCODE_INVALID_FILL:    return(QME_REJ_BROKER_REJECTED);
      case TRADE_RETCODE_TRADE_DISABLED:  return(QME_REJ_PERMISSION_SYMBOL);
      case TRADE_RETCODE_LONG_ONLY:       return(QME_REJ_PERMISSION_SYMBOL);
      case TRADE_RETCODE_SHORT_ONLY:      return(QME_REJ_PERMISSION_SYMBOL);
      case TRADE_RETCODE_CLOSE_ONLY:      return(QME_REJ_PERMISSION_SYMBOL);
      case TRADE_RETCODE_TOO_MANY_REQUESTS:return(QME_REJ_EXECUTION_FAILED);
     }
   if(QmeRetcodeIsSuccess(code)) return(QME_REJ_NONE);
   return(QME_REJ_BROKER_REJECTED);
  }

//--- last terminal error as text (used when an API call returns false)
string QmeLastErrorText()
  {
   const int code = GetLastError();
   return("err=" + IntegerToString(code) + " (" + QmeErrorName(QME_ERR_INTERNAL) + ")");
  }

#endif // __QME_CORE_ERRORCODES_MQH__
//+------------------------------------------------------------------+
