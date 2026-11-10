//+------------------------------------------------------------------+
//|                                                      Utils.mqh   |
//|  QuantumMarketEngine — dependency-free helpers.                   |
//|  OWNERSHIP: header only. Every function is stateless and pure     |
//|  except the deterministic id/time helpers.                        |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_UTILS_MQH__
#define __QME_CORE_UTILS_MQH__

#include "Constants.mqh"
#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Numeric helpers                                                  |
//+------------------------------------------------------------------+
//--- true when the string is a plain decimal number ("-12.5", "0", "3")
bool QmeIsNumeric(const string v)
  {
   const int n = StringLen(v);
   if(n == 0 || n > 32) return(false);
   int dots = 0;
   int digits = 0;
   for(int i = 0; i < n; i++)
     {
      const ushort c = StringGetCharacter(v, i);
      if(c == '-' || c == '+')
        {
         if(i != 0) return(false);
         continue;
        }
      if(c == '.')
        {
         dots++;
         if(dots > 1) return(false);
         continue;
        }
      if(c < '0' || c > '9') return(false);
      digits++;
     }
   return(digits > 0);
  }

bool QmeIsFinite(const double v)
  {
   return (MathIsValidNumber(v) != 0);   // rejects NaN and +-Inf
  }

double QmeClamp(const double v, const double lo, const double hi)
  {
   if(v < lo) return(lo);
   if(v > hi) return(hi);
   return(v);
  }

//--- safe division: returns fallback when the denominator is ~0
double QmeSafeDiv(const double num, const double den, const double fallback = 0.0)
  {
   if(MathAbs(den) < QME_EPSILON) return(fallback);
   return(num / den);
  }

double QmeSafePct(const double part, const double whole, const double fallback = 0.0)
  {
   if(MathAbs(whole) < QME_EPSILON) return(fallback);
   return(100.0 * part / whole);
  }

//--- normalised 0..1 position of v inside [lo,hi]
double QmeNormRange(const double v, const double lo, const double hi)
  {
   if(hi - lo < QME_EPSILON) return(0.5);
   return(QmeClamp((v - lo) / (hi - lo), 0.0, 1.0));
  }

bool QmeAlmostEqual(const double a, const double b, const double tol)
  {
   return(MathAbs(a - b) <= tol);
  }

double QmeRoundToDigits(const double price, const int digits)
  {
   if(digits < 0 || digits > 8) return(price);
   return(NormalizeDouble(price, digits));
  }

//--- digits-aware rounding of a price derived from point math
double QmePriceFromPoints(const string symbol, const double points)
  {
   const double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(pt <= 0.0) return(0.0);
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return(NormalizeDouble(points * pt, digits));
  }

double QmePriceToPoints(const string symbol, const double distance)
  {
   const double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(pt <= 0.0) return(0.0);
   return(distance / pt);
  }

//+------------------------------------------------------------------+
//| Time helpers                                                     |
//+------------------------------------------------------------------+
int QmeTimeframeMinutes(const ENUM_TIMEFRAMES tf)
  {
   return(PeriodSeconds(tf) / 60);
  }

string QmeTimeframeName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("TF?");
  }

//--- true when the last bar of `tf` belongs to a new period versus `lastBarTime`
bool QmeIsNewBar(const ENUM_TIMEFRAMES tf, datetime &lastBarTime)
  {
   const datetime t = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   if(t == 0) return(false);
   if(t == lastBarTime) return(false);
   lastBarTime = t;
   return(true);
  }

string QmeStamp(const datetime t)
  {
   if(t == 0) return("--");
   return(TimeToString(t, TIME_DATE | TIME_MINUTES | TIME_SECONDS));
  }

//--- hour of day in GMT; session logic must not depend on broker offset
int QmeGmtHour()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return(dt.hour);
  }

//+------------------------------------------------------------------+
//| Deterministic hashing (fingerprints, signal ids)                 |
//+------------------------------------------------------------------+
//--- FNV-1a 32 bit, widened to ulong. Stable across runs/terminals.
ulong QmeHashString(const string s)
  {
   ulong h = 2166136261;
   const int n = StringLen(s);
   for(int i = 0; i < n; i++)
     {
      h ^= (ulong)(StringGetCharacter(s, i) & 0xFFFF);
      h *= 16777619;
      h &= 0xFFFFFFFF;
     }
   return(h);
  }

//--- build a fingerprint: same market fact => same key => no duplicate order
string QmeFingerprint(const string symbol, const ENUM_QME_SIDE side,
                      const ENUM_TIMEFRAMES tf, const long zoneId,
                      const datetime barTime)
  {
   return(symbol + "|" + IntegerToString((int)side) + "|" +
          QmeTimeframeName(tf) + "|" + IntegerToString(zoneId) + "|" +
          IntegerToString((long)barTime));
  }

//+------------------------------------------------------------------+
//| Enum -> human readable tables (dashboard, logs, explanations)    |
//+------------------------------------------------------------------+
string QmeSideName(const ENUM_QME_SIDE side)
  {
   switch(side)
     {
      case QME_SIDE_BUY:  return("BUY");
      case QME_SIDE_SELL: return("SELL");
     }
   return("-");
  }

string QmeAccountModeName(const ENUM_QME_ACCOUNT_MODE m)
  {
   switch(m)
     {
      case QME_ACC_DEMO:    return("DEMO");
      case QME_ACC_CONTEST: return("CONTEST");
      case QME_ACC_REAL:    return("REAL");
     }
   return("UNKNOWN");
  }

string QmeRegimeName(const ENUM_QME_REGIME r)
  {
   switch(r)
     {
      case QME_REGIME_TREND_UP:    return("TREND_UP");
      case QME_REGIME_TREND_DOWN:  return("TREND_DOWN");
      case QME_REGIME_RANGE:       return("RANGE");
      case QME_REGIME_EXPANSION:   return("EXPANSION");
      case QME_REGIME_CONTRACTION: return("CONTRACTION");
     }
   return("UNKNOWN");
  }

string QmeTrendName(const ENUM_QME_TREND t)
  {
   switch(t)
     {
      case QME_TREND_UP:   return("UP");
      case QME_TREND_DOWN: return("DOWN");
      case QME_TREND_FLAT: return("FLAT");
     }
   return("UNKNOWN");
  }

string QmeVolatilityName(const ENUM_QME_VOLATILITY v)
  {
   switch(v)
     {
      case QME_VOL_LOW:     return("LOW");
      case QME_VOL_NORMAL:  return("NORMAL");
      case QME_VOL_HIGH:    return("HIGH");
      case QME_VOL_EXTREME: return("EXTREME");
     }
   return("UNKNOWN");
  }

string QmeTfName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
      case PERIOD_CURRENT: return("CUR");
     }
   return("TF?");
  }

string QmeSessionName(const ENUM_QME_SESSION s)
  {
   switch(s)
     {
      case QME_SESSION_ASIA:    return("ASIA");
      case QME_SESSION_LONDON:  return("LONDON");
      case QME_SESSION_NEWYORK: return("NEWYORK");
      case QME_SESSION_OVERLAP: return("LDN+NY");
      case QME_SESSION_OFFHOURS:return("OFF");
     }
   return("UNKNOWN");
  }

string QmeZoneSourceName(const ENUM_QME_ZONE_SOURCE s)
  {
   switch(s)
     {
      case QME_ZONE_SRC_ORDER_BLOCK:          return("OB");
      case QME_ZONE_SRC_FVG:                  return("FVG");
      case QME_ZONE_SRC_LIQUIDITY:            return("LIQ");
      case QME_ZONE_SRC_SUPPORT_RESISTANCE:   return("S/R");
      case QME_ZONE_SRC_PREMIUM_DISCOUNT:     return("P/D");
      case QME_ZONE_SRC_SESSION_RANGE:        return("SESSION");
      case QME_ZONE_SRC_VOLUME_PROFILE:       return("VP");
      case QME_ZONE_SRC_PDH_PDL:              return("PDH/PDL");
     }
   return("-");
  }

string QmeZoneStateName(const ENUM_QME_ZONE_STATE s)
  {
   switch(s)
     {
      case QME_ZSTAT_FRESH:       return("FRESH");
      case QME_ZSTAT_TESTED:      return("TESTED");
      case QME_ZSTAT_MITIGATED:   return("MITIGATED");
      case QME_ZSTAT_INVALIDATED: return("INVALIDATED");
      case QME_ZSTAT_EXPIRED:     return("EXPIRED");
     }
   return("-");
  }

string QmeSignalStateName(const ENUM_QME_SIGNAL_STATE s)
  {
   switch(s)
     {
      case QME_SIG_DETECTED:          return("DETECTED");
      case QME_SIG_EVALUATING:        return("EVALUATING");
      case QME_SIG_APPROVED:          return("APPROVED");
      case QME_SIG_EXECUTION_PENDING: return("EXEC_PENDING");
      case QME_SIG_EXECUTED:          return("EXECUTED");
      case QME_SIG_MONITORING:        return("MONITORING");
      case QME_SIG_CLOSED:            return("CLOSED");
      case QME_SIG_REJECTED:          return("REJECTED");
      case QME_SIG_EXPIRED:           return("EXPIRED");
      case QME_SIG_INVALIDATED:       return("INVALIDATED");
      case QME_SIG_EXECUTION_FAILED:  return("EXEC_FAILED");
      case QME_SIG_CANCELLED:         return("CANCELLED");
     }
   return("NONE");
  }

string QmeRejectName(const ENUM_QME_REJECT r)
  {
   switch(r)
     {
      case QME_REJ_NONE:                  return("NONE");
      case QME_REJ_NOT_TRADABLE:          return("NOT_TRADABLE");
      case QME_REJ_NO_DATA:               return("NO_DATA");
      case QME_REJ_STALE_DATA:            return("STALE_DATA");
      case QME_REJ_DATA_QUALITY:          return("DATA_QUALITY");
      case QME_REJ_SYMBOL_DISABLED:       return("SYMBOL_DISABLED");
      case QME_REJ_LOW_SCORE:             return("LOW_SCORE");
      case QME_REJ_NO_CONFLUENCE:         return("NO_CONFLUENCE");
      case QME_REJ_NO_STRUCTURE:          return("NO_STRUCTURE");
      case QME_REJ_SPREAD:                return("SPREAD");
      case QME_REJ_SESSION:               return("SESSION");
      case QME_REJ_NEWS_WINDOW:           return("NEWS_WINDOW");
      case QME_REJ_DISABLED_BY_CONFIG:    return("DISABLED_BY_CONFIG");
      case QME_REJ_RISK_PER_TRADE:        return("RISK_PER_TRADE");
      case QME_REJ_DAILY_LOSS:            return("DAILY_LOSS");
      case QME_REJ_DRAWDOWN:              return("DRAWDOWN");
      case QME_REJ_MAX_POSITIONS:         return("MAX_POSITIONS");
      case QME_REJ_SYMBOL_EXPOSURE:       return("SYMBOL_EXPOSURE");
      case QME_REJ_PORTFOLIO_EXPOSURE:    return("PORTFOLIO_EXPOSURE");
      case QME_REJ_CORRELATION:           return("CORRELATION");
      case QME_REJ_CONSECUTIVE_LOSSES:    return("CONSEC_LOSSES");
      case QME_REJ_RR:                    return("RR_TOO_LOW");
      case QME_REJ_SL_INVALID:            return("SL_INVALID");
      case QME_REJ_TP_INVALID:            return("TP_INVALID");
      case QME_REJ_VOLUME_INVALID:        return("VOLUME_INVALID");
      case QME_REJ_MARGIN:                return("MARGIN");
      case QME_REJ_MARKET_CLOSED:         return("MARKET_CLOSED");
      case QME_REJ_DUPLICATE_SIGNAL:      return("DUPLICATE_SIGNAL");
      case QME_REJ_DUPLICATE_POSITION:    return("DUPLICATE_POSITION");
      case QME_REJ_ACCOUNT_MODE:          return("ACCOUNT_MODE");
      case QME_REJ_TRADING_NOT_AUTHORIZED:return("NOT_AUTHORIZED");
      case QME_REJ_PERMISSION_TERMINAL:   return("TERMINAL_DISABLED");
      case QME_REJ_PERMISSION_EXPERT:     return("EXPERT_DISABLED");
      case QME_REJ_PERMISSION_SYMBOL:     return("SYMBOL_DISABLED");
      case QME_REJ_ACCOUNT_PERMISSION:    return("ACCOUNT_DISABLED");
      case QME_REJ_LOGIN_MISMATCH:        return("LOGIN_MISMATCH");
      case QME_REJ_EXECUTION_FAILED:      return("EXECUTION_FAILED");
      case QME_REJ_BROKER_REJECTED:       return("BROKER_REJECTED");
      case QME_REJ_EXPIRED:               return("EXPIRED");
      case QME_REJ_INVALIDATED:           return("INVALIDATED");
      case QME_REJ_INTERNAL:              return("INTERNAL");
     }
   return("UNKNOWN");
  }

string QmeFactorName(const ENUM_QME_FACTOR f)
  {
   switch(f)
     {
      case QME_F_HTF_BIAS:         return("HTF_BIAS");
      case QME_F_STRUCTURE:        return("STRUCTURE");
      case QME_F_LIQUIDITY:        return("LIQUIDITY");
      case QME_F_SWEEP:            return("SWEEP");
      case QME_F_DISPLACEMENT:     return("DISPLACEMENT");
      case QME_F_BOS:              return("BOS");
      case QME_F_MSS:              return("MSS");
      case QME_F_ORDER_BLOCK:      return("ORDER_BLOCK");
      case QME_F_FVG:              return("FVG");
      case QME_F_PREMIUM_DISCOUNT: return("PREM_DISC");
      case QME_F_MOMENTUM:         return("MOMENTUM");
      case QME_F_VOLATILITY:       return("VOLATILITY");
      case QME_F_SESSION:          return("SESSION");
      case QME_F_ENTRY_CONFIRM:    return("ENTRY_CONFIRM");
     }
   return("?");
  }

string QmeFamilyName(const ENUM_QME_FACTOR_FAMILY f)
  {
   switch(f)
     {
      case QME_FAM_DIRECTION:  return("DIRECTION");
      case QME_FAM_STRUCTURE:  return("STRUCTURE");
      case QME_FAM_LIQUIDITY: return("LIQUIDITY");
      case QME_FAM_IMBALANCE: return("IMBALANCE");
      case QME_FAM_MOMENTUM:  return("MOMENTUM");
      case QME_FAM_CONTEXT:   return("CONTEXT");
     }
   return("?");
  }

string QmeEntryTypeName(const ENUM_QME_ENTRY_TYPE e)
  {
   switch(e)
     {
      case QME_ENTRY_MARKET: return("MARKET");
      case QME_ENTRY_LIMIT:  return("LIMIT");
      case QME_ENTRY_STOP:   return("STOP");
     }
   return("?");
  }

string QmeSeverityName(const ENUM_QME_SEVERITY s)
  {
   switch(s)
     {
      case QME_LOG_TRACE:    return("TRACE");
      case QME_LOG_DEBUG:    return("DEBUG");
      case QME_LOG_INFO:     return("INFO");
      case QME_LOG_WARN:     return("WARN");
      case QME_LOG_ERROR:    return("ERROR");
      case QME_LOG_CRITICAL: return("CRIT");
     }
   return("?");
  }

string QmeEventName(const ENUM_QME_EVENT e)
  {
   switch(e)
     {
      case QME_EVT_INIT:               return("INIT");
      case QME_EVT_TICK:               return("TICK");
      case QME_EVT_TIMER:              return("TIMER");
      case QME_EVT_BAR_CLOSE:          return("BAR_CLOSE");
      case QME_EVT_SCAN_START:         return("SCAN_START");
      case QME_EVT_SCAN_END:           return("SCAN_END");
      case QME_EVT_SIGNAL_DETECTED:    return("SIG_DETECTED");
      case QME_EVT_SIGNAL_APPROVED:    return("SIG_APPROVED");
      case QME_EVT_SIGNAL_REJECTED:    return("SIG_REJECTED");
      case QME_EVT_SIGNAL_EXPIRED:     return("SIG_EXPIRED");
      case QME_EVT_RISK_BREACH:        return("RISK_BREACH");
      case QME_EVT_ORDER_SENT:         return("ORDER_SENT");
      case QME_EVT_TRADE_TRANSACTION:  return("TXN");
      case QME_EVT_POSITION_UPDATE:    return("POS_UPDATE");
      case QME_EVT_HEALTH:             return("HEALTH");
      case QME_EVT_ERROR:              return("ERROR");
      case QME_EVT_SHUTDOWN:           return("SHUTDOWN");
     }
   return("NONE");
  }

//+------------------------------------------------------------------+
//| Formatting helpers                                               |
//+------------------------------------------------------------------+
string QmeFmt(const double v, const int digits = 2)
  {
   if(!QmeIsFinite(v)) return("n/a");
   return(DoubleToString(v, digits));
  }

string QmeFmtMoney(const double v, const int digits = 2)
  {
   if(!QmeIsFinite(v)) return("n/a");
   return(DoubleToString(v, digits));
  }

string QmeBoolStr(const bool b)
  {
   return(b ? "YES" : "NO");
  }

//--- split a comma/semicolon/space separated symbol list (no StringSplit on MQL5)
int QmeSplitList(const string src, string &out[], const int maxItems)
  {
   ArrayResize(out, 0);
   string cur = "";
   const int n = StringLen(src);
   for(int i = 0; i <= n; i++)
     {
      const int ch = (i < n) ? StringGetCharacter(src, i) : ';';
      const bool sep = (ch == ',' || ch == ';' || ch == ' ' || ch == '\t' || ch == '|');
      if(sep)
        {
         StringTrimLeft(cur);
         StringTrimRight(cur);
         if(StringLen(cur) > 0)
           {
            const int k = ArraySize(out);
            if(k >= maxItems) break;
            ArrayResize(out, k + 1);
            out[k] = cur;
           }
         cur = "";
        }
      else
         cur += ShortToString((ushort)ch);
     }
   return(ArraySize(out));
  }

//--- upper-case copy
string QmeUpper(const string s)
  {
   string u = s;
   StringToUpper(u);
   return(u);
  }

#endif // __QME_CORE_UTILS_MQH__
//+------------------------------------------------------------------+
