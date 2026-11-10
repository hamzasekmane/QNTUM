//+------------------------------------------------------------------+
//|                                                Data/MarketClock   |
//|  QuantumMarketEngine — time, sessions, market hours.                |
//|                                                                   |
//|  All session logic uses GMT, never the broker's server offset, so    |
//|  the same rules apply on every broker. Server time is only used for  |
//|  bar-close arithmetic.                                             |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_MARKETCLOCK_MQH__
#define __QME_DATA_MARKETCLOCK_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

class CMarketClock
  {
private:
   long              m_gmtOffsetSec;
   datetime          m_offsetComputed;

public:
                     CMarketClock(void) { m_gmtOffsetSec = 0; m_offsetComputed = 0; }

   void              Refresh(void);

   datetime          ServerTime(void) { return(TimeTradeServer()); }
   datetime          GmtTime(void)    { return(TimeGMT()); }
   datetime          LocalTime(void)  { return(TimeLocal()); }
   //--- server clock minus GMT, in seconds (broker daylight saving included)
   long              ServerGmtOffset(void) { return(m_gmtOffsetSec); }

   static ENUM_QME_SESSION SessionOf(const datetime gmtTime);
   static string     SessionDescription(const datetime gmtTime);
   static bool       IsWeekend(const datetime gmtTime);
   static bool       IsTradingDay(const datetime gmtTime);

   //--- seconds until the next bar closes on this timeframe (>= 0)
   static int        SecondsToBarClose(const ENUM_TIMEFRAMES tf, const datetime serverTime);

   //--- seconds since the newest closed bar opened
   static int        SecondsSinceBarClose(const ENUM_TIMEFRAMES tf, const datetime serverTime);
  };

//------------------------------------------------------------------//
void CMarketClock::Refresh(void)
  {
   const datetime srv = TimeTradeServer();
   const datetime gmt = TimeGMT();
   if(srv == 0 || gmt == 0) return;
   m_gmtOffsetSec = (long)srv - (long)gmt;
   m_offsetComputed = srv;
  }

//------------------------------------------------------------------//
//| Session map (GMT):                                                |
//|   ASIA      00:00 - 07:00                                        |
//|   LONDON    07:00 - 12:00                                        |
//|   OVERLAP   12:00 - 16:00  (London + New York)                   |
//|   NEWYORK   16:00 - 21:00                                        |
//|   OFF       21:00 - 00:00                                        |
//+------------------------------------------------------------------//
ENUM_QME_SESSION CMarketClock::SessionOf(const datetime gmtTime)
  {
   if(gmtTime <= 0) return(QME_SESSION_UNKNOWN);
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return(QME_SESSION_OFFHOURS);

   const int h = dt.hour;
   if(h >= 12 && h < 16) return(QME_SESSION_OVERLAP);
   if(h >= 7 && h < 12)  return(QME_SESSION_LONDON);
   if(h >= 16 && h < 21) return(QME_SESSION_NEWYORK);
   if(h >= 0 && h < 7)   return(QME_SESSION_ASIA);
   return(QME_SESSION_OFFHOURS);
  }

//------------------------------------------------------------------//
string CMarketClock::SessionDescription(const datetime gmtTime)
  {
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   return(QmeSessionName(SessionOf(gmtTime)) +
          " gmt=" + IntegerToString(dt.hour) + ":" +
          (dt.min < 10 ? "0" : "") + IntegerToString(dt.min));
  }

//------------------------------------------------------------------//
bool CMarketClock::IsWeekend(const datetime gmtTime)
  {
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   return(dt.day_of_week == 0 || dt.day_of_week == 6);
  }

bool CMarketClock::IsTradingDay(const datetime gmtTime)
  {
   return(!IsWeekend(gmtTime));
  }

//------------------------------------------------------------------//
int CMarketClock::SecondsToBarClose(const ENUM_TIMEFRAMES tf, const datetime serverTime)
  {
   const int period = PeriodSeconds(tf);
   if(period <= 0 || serverTime <= 0) return(0);
   const long rem = (long)serverTime % (long)period;
   return((int)(period - rem));
  }

//------------------------------------------------------------------//
int CMarketClock::SecondsSinceBarClose(const ENUM_TIMEFRAMES tf, const datetime serverTime)
  {
   const int period = PeriodSeconds(tf);
   if(period <= 0 || serverTime <= 0) return(0);
   return((int)((long)serverTime % (long)period));
  }

#endif // __QME_DATA_MARKETCLOCK_MQH__
//+------------------------------------------------------------------+
