//+------------------------------------------------------------------+
//|                                        Monitoring/ErrorTracker    |
//|  Counts and classifies failures instead of only printing them.        |
//|                                                                   |
//|  Every component reports failures here with a category. The watchdog  |
//|  and the dashboard read the counts; the health check reacts to        |
//|  repeated failures in the same category, which is what actually        |
//|  indicates a broken environment (a single requote does not).           |
//+------------------------------------------------------------------+
#ifndef __QME_MON_ERRORTRACKER_MQH__
#define __QME_MON_ERRORTRACKER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

#define QME_ERR_CAT_COUNT 10

enum ENUM_QME_ERR_CAT
  {
   QME_ERRC_DATA = 0,
   QME_ERRC_ACCOUNT,
   QME_ERRC_PERMISSION,
   QME_ERRC_RISK,
   QME_ERRC_EXECUTION,
   QME_ERRC_BROKER,
   QME_ERRC_PERSISTENCE,
   QME_ERRC_CONFIG,
   QME_ERRC_TIME,
   QME_ERRC_INTERNAL
  };

class CErrorTracker
  {
private:
   long              m_counts[QME_ERR_CAT_COUNT];
   string            m_last[QME_ERR_CAT_COUNT];
   datetime          m_lastTime[QME_ERR_CAT_COUNT];
   long              m_total;

public:
                     CErrorTracker(void) { Reset(); }
   void              Reset(void);
   void              Report(const ENUM_QME_ERR_CAT cat, const string detail);
   long              Count(const ENUM_QME_ERR_CAT cat);
   long              Total(void) { return(m_total); }
   string            LastDetail(const ENUM_QME_ERR_CAT cat);
   datetime          LastTime(const ENUM_QME_ERR_CAT cat);
   bool              Repeated(const ENUM_QME_ERR_CAT cat, const long threshold);
   int               CategoriesWithErrors(void);
   string            Describe(void);
  };

//------------------------------------------------------------------//
void CErrorTracker::Reset(void)
  {
   for(int i = 0; i < QME_ERR_CAT_COUNT; i++)
     {
      m_counts[i] = 0;
      m_last[i] = "";
      m_lastTime[i] = 0;
     }
   m_total = 0;
  }

//------------------------------------------------------------------//
void CErrorTracker::Report(const ENUM_QME_ERR_CAT cat, const string detail)
  {
   const int i = (int)cat;
   if(i < 0 || i >= QME_ERR_CAT_COUNT) return;
   m_counts[i]++;
   m_total++;
   m_last[i] = detail;
   m_lastTime[i] = TimeCurrent();
   QmeLogMsg(QME_LOG_WARN, "ErrorTracker", IntegerToString(i) + ": " + detail);
  }

//------------------------------------------------------------------//
long CErrorTracker::Count(const ENUM_QME_ERR_CAT cat)
  {
   const int i = (int)cat;
   if(i < 0 || i >= QME_ERR_CAT_COUNT) return(0);
   return(m_counts[i]);
  }

string CErrorTracker::LastDetail(const ENUM_QME_ERR_CAT cat)
  {
   const int i = (int)cat;
   if(i < 0 || i >= QME_ERR_CAT_COUNT) return("");
   return(m_last[i]);
  }

datetime CErrorTracker::LastTime(const ENUM_QME_ERR_CAT cat)
  {
   const int i = (int)cat;
   if(i < 0 || i >= QME_ERR_CAT_COUNT) return(0);
   return(m_lastTime[i]);
  }

bool CErrorTracker::Repeated(const ENUM_QME_ERR_CAT cat, const long threshold)
  {
   return(Count(cat) >= threshold);
  }

int CErrorTracker::CategoriesWithErrors(void)
  {
   int n = 0;
   for(int i = 0; i < QME_ERR_CAT_COUNT; i++)
      if(m_counts[i] > 0) n++;
   return(n);
  }

//------------------------------------------------------------------//
string CErrorTracker::Describe(void)
  {
   if(m_total == 0) return("errors none");
   string s = "errors total=" + IntegerToString((int)m_total);
   for(int i = 0; i < QME_ERR_CAT_COUNT; i++)
     {
      if(m_counts[i] == 0) continue;
      s += " [" + IntegerToString(i) + ":" + IntegerToString((int)m_counts[i]) + "]";
     }
   return(s);
  }

#endif // __QME_MON_ERRORTRACKER_MQH__
//+------------------------------------------------------------------+
