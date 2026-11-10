//+------------------------------------------------------------------+
//|                                  Runtime/CanonicalSnapshot        |
//|  A deterministic fingerprint of one decision cycle.                   |
//|                                                                   |
//|  Two runs that saw the same market state must produce the same        |
//|  digest. It is used by the regression tests and by the log so a       |
//|  cycle can be compared across restarts or across DEMO/REAL without    |
//|  re-running the market.                                            |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_SNAPSHOT_MQH__
#define __QME_RUNTIME_SNAPSHOT_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

struct SCanonicalSnapshot
  {
   long              cycle;
   datetime          time;
   string            symbol;
   ENUM_TIMEFRAMES   tf;
   double            price;
   double            atr;
   ENUM_QME_SIDE     bias;
   double            biasScore;
   int               zoneCount;
   int               candidates;
   int               signals;
   int               approved;
   ENUM_QME_SESSION  session;
   string            digest;
  };

void QmeCanonicalClear(SCanonicalSnapshot &s)
  {
   s.cycle = 0; s.time = 0; s.symbol = ""; s.tf = PERIOD_CURRENT;
   s.price = 0.0; s.atr = 0.0; s.bias = QME_SIDE_NONE; s.biasScore = 0.0;
   s.zoneCount = 0; s.candidates = 0; s.signals = 0; s.approved = 0;
   s.session = QME_SESSION_UNKNOWN; s.digest = "";
  }

class CCanonicalSnapshot
  {
public:
   //--- order-independent digest of the numeric state
   static string     Digest(const SCanonicalSnapshot &s);
   static string     Serialize(const SCanonicalSnapshot &s);
   static bool       Deserialize(const string line, SCanonicalSnapshot &s);
   static bool       Equivalent(const SCanonicalSnapshot &a, const SCanonicalSnapshot &b,
                                const double priceTolerance = 0.0);
  };

//------------------------------------------------------------------//
string CCanonicalSnapshot::Digest(const SCanonicalSnapshot &s)
  {
   //--- FNV-1a over a fixed field order; integers only, so no float drift
   string key = s.symbol + "|" + QmeTfName(s.tf) + "|" +
                QmeSideName(s.bias) + "|" +
                IntegerToString((long)MathRound(s.price / QME_PRICE_EPS)) + "|" +
                IntegerToString((long)MathRound(s.atr / QME_PRICE_EPS)) + "|" +
                IntegerToString((long)MathRound(s.biasScore * 1000.0)) + "|" +
                IntegerToString(s.zoneCount) + "|" +
                IntegerToString(s.candidates) + "|" +
                IntegerToString(s.signals) + "|" +
                IntegerToString(s.approved) + "|" +
                IntegerToString((int)s.session);

   ulong hash = 2166136261;
   const int n = StringLen(key);
   for(int i = 0; i < n; i++)
     {
      hash ^= (ulong)StringGetCharacter(key, i);
      hash *= 16777619;
     }
   //--- manual hex so the digest never depends on printf specifier support
   const string digits = "0123456789ABCDEF";
   string hex = "";
   for(int i = 15; i >= 0; i--)
     {
      const int nibble = (int)((hash >> (i * 4)) & 0xF);
      hex += StringSubstr(digits, nibble, 1);
     }
   return(hex);
  }

//------------------------------------------------------------------//
string CCanonicalSnapshot::Serialize(const SCanonicalSnapshot &s)
  {
   return("snap|" + IntegerToString(s.cycle) + "|" +
          IntegerToString((long)s.time) + "|" + s.symbol + "|" +
          QmeTfName(s.tf) + "|" + DoubleToString(s.price, 8) + "|" +
          DoubleToString(s.atr, 8) + "|" + QmeSideName(s.bias) + "|" +
          DoubleToString(s.biasScore, 4) + "|" + IntegerToString(s.zoneCount) + "|" +
          IntegerToString(s.candidates) + "|" + IntegerToString(s.signals) + "|" +
          IntegerToString(s.approved) + "|" + IntegerToString((int)s.session) + "|" +
          s.digest);
  }

//------------------------------------------------------------------//
bool CCanonicalSnapshot::Deserialize(const string line, SCanonicalSnapshot &s)
  {
   QmeCanonicalClear(s);
   string f[];
   if(StringSplit(line, '|', f) < 15) return(false);
   if(f[0] != "snap") return(false);
   s.cycle = StringToInteger(f[1]);
   s.time = (datetime)StringToInteger(f[2]);
   s.symbol = f[3];
   s.price = StringToDouble(f[5]);
   s.atr = StringToDouble(f[6]);
   s.bias = (f[7] == "BUY") ? QME_SIDE_BUY : (f[7] == "SELL" ? QME_SIDE_SELL : QME_SIDE_NONE);
   s.biasScore = StringToDouble(f[8]);
   s.zoneCount = (int)StringToInteger(f[9]);
   s.candidates = (int)StringToInteger(f[10]);
   s.signals = (int)StringToInteger(f[11]);
   s.approved = (int)StringToInteger(f[12]);
   s.session = (ENUM_QME_SESSION)StringToInteger(f[13]);
   s.digest = f[14];
   return(StringLen(s.symbol) > 0);
  }

//------------------------------------------------------------------//
bool CCanonicalSnapshot::Equivalent(const SCanonicalSnapshot &a, const SCanonicalSnapshot &b,
                                    const double priceTolerance)
  {
   if(a.symbol != b.symbol) return(false);
   if(a.tf != b.tf) return(false);
   if(a.bias != b.bias) return(false);
   if(a.zoneCount != b.zoneCount) return(false);
   if(a.signals != b.signals) return(false);
   if(a.approved != b.approved) return(false);
   if(priceTolerance <= 0.0) return(a.digest == b.digest);
   if(MathAbs(a.price - b.price) > priceTolerance) return(false);
   if(MathAbs(a.atr - b.atr) > priceTolerance) return(false);
   return(true);
  }

#endif // __QME_RUNTIME_SNAPSHOT_MQH__
//+------------------------------------------------------------------+
