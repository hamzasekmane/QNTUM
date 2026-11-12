//+------------------------------------------------------------------+
//| Data/QuoteSessions.mqh — broker quote-session aware bar gaps      |
#ifndef __QME_QUOTE_SESSIONS_MQH__
#define __QME_QUOTE_SESSIONS_MQH__

#include "../Core/Utils.mqh"

struct SQuoteSessionWindow
  {
   int startSecond; // seconds from midnight; end may extend beyond 24h
   int endSecond;
  };

// Pure helper for deterministic tests. Tests whether any part of one bar
// interval overlaps any scheduled quote window on its weekday.
bool QmeBarOverlapsQuoteWindows(const datetime barOpen,const int periodSec,
                                const int weekday,SQuoteSessionWindow &windows[],
                                const int count)
  {
   if(barOpen<=0 || periodSec<=0 || weekday<0 || weekday>6 || count<=0) return(false);
   MqlDateTime dt; TimeToStruct(barOpen,dt);
   const int from=dt.hour*3600+dt.min*60+dt.sec;
   const int to=from+periodSec;
   for(int i=0;i<count;i++)
      if(from<windows[i].endSecond && to>windows[i].startSecond) return(true);
   return(false);
  }

// True only when every absent expected bar crosses no configured quote
// session. Missing/inaccessible broker schedule is an explicit failure.
bool QmeGapCoveredByClosedQuoteSessions(const string symbol,const datetime olderOpen,
                                         const datetime newerOpen,const int periodSec,
                                         string &reason)
  {
   reason="";
   if(symbol=="" || olderOpen<=0 || newerOpen<=olderOpen || periodSec<=0)
     { reason="invalid gap/session arguments"; return(false); }
   bool foundAnySchedule=false;
   for(datetime t=olderOpen+periodSec;t<newerOpen;t+=periodSec)
     {
      MqlDateTime dt; TimeToStruct(t,dt);
      bool barScheduled=false;
      // Query this day and the previous day's sessions to include overnight
      // windows (e.g. Sunday evening into Monday). API times are server time.
      for(int back=1;back>=0;back--)
        {
         MqlDateTime day=dt;
         day.hour=0; day.min=0; day.sec=0;
         datetime midnight=StructToTime(day)-(back*86400);
         MqlDateTime sessionDay; TimeToStruct(midnight,sessionDay);
         for(uint ix=0;ix<32;ix++)
           {
            datetime from=0,to=0;
            if(!SymbolInfoSessionQuote(symbol,(ENUM_DAY_OF_WEEK)sessionDay.day_of_week,ix,from,to)) break;
            foundAnySchedule=true;
            MqlDateTime f, e; TimeToStruct(from,f); TimeToStruct(to,e);
            int start=f.hour*3600+f.min*60+f.sec;
            int end=e.hour*3600+e.min*60+e.sec;
            if(end<=start) end+=86400;
            const datetime absStart=midnight+start;
            const datetime absEnd=midnight+end;
            if(t<absEnd && t+periodSec>absStart) { barScheduled=true; break; }
           }
         if(barScheduled) break;
        }
      if(barScheduled)
        {
         reason="missing expected bar inside broker quote session at "+TimeToString(t,TIME_DATE|TIME_MINUTES);
         return(false);
        }
     }
   if(!foundAnySchedule)
     { reason="broker quote-session schedule unavailable; fail closed"; return(false); }
   reason="gap covered by closed broker quote sessions";
   return(true);
  }

#endif
