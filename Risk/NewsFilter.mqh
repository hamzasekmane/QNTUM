//+------------------------------------------------------------------+
//|                                               Risk/NewsFilter     |
//|  Trading blackout windows around scheduled events.                   |
//|                                                                   |
//|  HONEST SCOPE: this engine does NOT fabricate an economic calendar.   |
//|  It supports explicitly configured daily blackout windows in GMT       |
//|  ("HH:MM-HH:MM;HH:MM-HH:MM" in InpNewsBlackoutWindows) and reports     |
//|  any configured window as a hard block. If a real calendar feed is     |
//|  added later it must plug in here and keep this contract.              |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_NEWSFILTER_MQH__
#define __QME_RISK_NEWSFILTER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"

class CNewsFilter
  {
public:
   static bool       Blocked(const CConfig &cfg, const datetime gmtTime, string &why);
   static int        ConfiguredWindows(const CConfig &cfg);
  };

//------------------------------------------------------------------//
//| Parse "HH:MM-HH:MM" windows directly from the configuration string.  |
//| Windows may cross midnight (e.g. 22:00-02:00).                       |
//+------------------------------------------------------------------//
bool CNewsFilter::Blocked(const CConfig &cfg, const datetime gmtTime, string &why)
  {
   why = "";
   if(!cfg.In.newsFilterEnabled) return(false);
   if(gmtTime <= 0)
     {
      why = "GMT time unavailable while the news filter is enabled";
      return(true);
     }
   if(StringLen(cfg.In.newsBlackoutWindows) == 0) return(false);

   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   const int nowMin = dt.hour * 60 + dt.min;

   string parts[];
   const int n = QmeSplitList(cfg.In.newsBlackoutWindows, parts, QME_MAX_SYMBOLS);
   for(int i = 0; i < n; i++)
     {
      const int dash = StringFind(parts[i], "-");
      if(dash <= 0) continue;
      const string a = StringSubstr(parts[i], 0, dash);
      const string b = StringSubstr(parts[i], dash + 1);
      const int ca = StringFind(a, ":");
      const int cb = StringFind(b, ":");
      if(ca <= 0 || cb <= 0) continue;

      const int h1 = (int)StringToInteger(StringSubstr(a, 0, ca));
      const int m1 = (int)StringToInteger(StringSubstr(a, ca + 1));
      const int h2 = (int)StringToInteger(StringSubstr(b, 0, cb));
      const int m2 = (int)StringToInteger(StringSubstr(b, cb + 1));
      if(h1 < 0 || h1 > 23 || h2 < 0 || h2 > 23 || m1 < 0 || m1 > 59 || m2 < 0 || m2 > 59)
         continue;

      //--- widen the window by the configured blackout margin on both sides
      const int margin = (cfg.In.newsBlackoutMinutes > 0) ? cfg.In.newsBlackoutMinutes : 0;
      const int rawStart = h1 * 60 + m1;
      const int rawEnd   = h2 * 60 + m2;
      const int rawLen   = (rawEnd >= rawStart) ? (rawEnd - rawStart)
                                                : (rawEnd + 1440 - rawStart);
      if(rawLen + 2 * margin >= 1440)
        {
         why = "news blackout window " + parts[i] + " widened to a full day";
         return(true);
        }
      const int startMin = (rawStart - margin + 1440) % 1440;
      const int endMin   = (rawEnd + margin) % 1440;
      const bool inside = (startMin <= endMin) ? (nowMin >= startMin && nowMin <= endMin)
                                               : (nowMin >= startMin || nowMin <= endMin);
      if(inside)
        {
         why = "news blackout window " + parts[i] + " is active";
         return(true);
        }
     }
   return(false);
  }

//------------------------------------------------------------------//
int CNewsFilter::ConfiguredWindows(const CConfig &cfg)
  {
   if(StringLen(cfg.In.newsBlackoutWindows) == 0) return(0);
   string parts[];
   return(QmeSplitList(cfg.In.newsBlackoutWindows, parts, QME_MAX_SYMBOLS));
  }

#endif // __QME_RISK_NEWSFILTER_MQH__
//+------------------------------------------------------------------+
