//+------------------------------------------------------------------+
//|                                    Persistence/StateSerializer    |
//|  Tiny, versioned, human-readable state format.                       |
//|                                                                   |
//|  One record per line:   KEY|TYPE|VALUE                               |
//|  TYPE is one of s (string), i (integer), f (float), b (bool), t (time).|
//|  Values are escaped so a symbol name or comment can never break the    |
//|  format. Missing keys return defaults, never garbage.                 |
//+------------------------------------------------------------------+
#ifndef __QME_PERSIST_SERIALIZER_MQH__
#define __QME_PERSIST_SERIALIZER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

class CStateSerializer
  {
public:
   static string     Escape(const string v);
   static string     Unescape(const string v);

   static string     Str(const string key, const string v);
   static string     Int(const string key, const long v);
   static string     Dbl(const string key, const double v, const int digits = 8);
   static string     Bool(const string key, const bool v);
   static string     Time(const string key, const datetime v);

   static bool       Find(const string blob, const string key, string &value);
   static long       GetInt(const string blob, const string key, const long def);
   static double     GetDbl(const string blob, const string key, const double def);
   static bool       GetBool(const string blob, const string key, const bool def);
   static datetime   GetTime(const string blob, const string key, const datetime def);
   static string     GetStr(const string blob, const string key, const string def);

   static bool       Header(string &out);          // "QME|STATE|version|time"
   static bool       CheckVersion(const string blob, string &why);
  };

//------------------------------------------------------------------//
string CStateSerializer::Escape(const string v)
  {
   string s = v;
   StringReplace(s, "%", "%25");
   StringReplace(s, "|", "%7C");
   StringReplace(s, "\n", "%0A");
   StringReplace(s, "\r", "%0D");
   return(s);
  }

string CStateSerializer::Unescape(const string v)
  {
   string s = v;
   StringReplace(s, "%0D", "\r");
   StringReplace(s, "%0A", "\n");
   StringReplace(s, "%7C", "|");
   StringReplace(s, "%25", "%");
   return(s);
  }

//------------------------------------------------------------------//
string CStateSerializer::Str(const string key, const string v)
  { return(key + "|s|" + Escape(v)); }
string CStateSerializer::Int(const string key, const long v)
  { return(key + "|i|" + IntegerToString(v)); }
string CStateSerializer::Dbl(const string key, const double v, const int digits)
  {
   if(!QmeIsFinite(v)) return(key + "|f|0");
   return(key + "|f|" + DoubleToString(v, digits));
  }
string CStateSerializer::Bool(const string key, const bool v)
  { return(key + "|b|" + (v ? "1" : "0")); }
string CStateSerializer::Time(const string key, const datetime v)
  { return(key + "|t|" + IntegerToString((long)v)); }

//------------------------------------------------------------------//
bool CStateSerializer::Find(const string blob, const string key, string &value)
  {
   value = "";
   if(StringLen(blob) == 0 || StringLen(key) == 0) return(false);

   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], '|', f) < 3) continue;
      if(f[0] != key) continue;
      value = Unescape(f[2]);
      return(true);
     }
   return(false);
  }

long CStateSerializer::GetInt(const string blob, const string key, const long def)
  {
   string v = "";
   if(!Find(blob, key, v)) return(def);
   if(!QmeIsNumeric(v)) return(def);
   return(StringToInteger(v));
  }

double CStateSerializer::GetDbl(const string blob, const string key, const double def)
  {
   string v = "";
   if(!Find(blob, key, v)) return(def);
   if(!QmeIsNumeric(v)) return(def);
   return(StringToDouble(v));
  }

bool CStateSerializer::GetBool(const string blob, const string key, const bool def)
  {
   string v = "";
   if(!Find(blob, key, v)) return(def);
   return(v == "1" || v == "true");
  }

datetime CStateSerializer::GetTime(const string blob, const string key, const datetime def)
  {
   string v = "";
   if(!Find(blob, key, v)) return(def);
   if(!QmeIsNumeric(v)) return(def);
   return((datetime)StringToInteger(v));
  }

string CStateSerializer::GetStr(const string blob, const string key, const string def)
  {
   string v = "";
   if(!Find(blob, key, v)) return(def);
   return(v);
  }

//------------------------------------------------------------------//
bool CStateSerializer::Header(string &out)
  {
   out = "QME|STATE|" + IntegerToString(QME_STATE_VERSION) + "|" +
         IntegerToString((long)TimeCurrent());
   return(true);
  }

//------------------------------------------------------------------//
bool CStateSerializer::CheckVersion(const string blob, string &why)
  {
   why = "";
   const int nl = StringFind(blob, "\n");
   const string first = (nl < 0) ? blob : StringSubstr(blob, 0, nl);
   string f[];
   if(StringSplit(first, '|', f) < 3)
     {
      why = "state file has no header";
      return(false);
     }
   if(f[0] != "QME" || f[1] != "STATE")
     {
      why = "state file is not a QME state file";
      return(false);
     }
   const int ver = (int)StringToInteger(f[2]);
   if(ver != QME_STATE_VERSION)
     {
      why = "state version " + IntegerToString(ver) + " != " +
            IntegerToString(QME_STATE_VERSION) + " (starting clean)";
      return(false);
     }
   return(true);
  }

#endif // __QME_PERSIST_SERIALIZER_MQH__
//+------------------------------------------------------------------+
