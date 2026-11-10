//+------------------------------------------------------------------+
//|                                                     Logger.mqh   |
//|  QuantumMarketEngine — structured logging with severity filter,   |
//|  in-memory ring buffer (dashboard), file sink and counters.        |
//|                                                                   |
//|  OWNERSHIP: single instance owned by CEngine, published as g_log.  |
//|  Interfaces:                                                      |
//|    bool Init(const SInputs&, string &err)                         |
//|    void Shutdown()                                                |
//|    void Log(ENUM_QME_SEVERITY, string module, string message)     |
//|  Outputs: console, optional common-folder log file, ring buffer.   |
//|  NOTE: logging never throws and never blocks a decision. It may    |
//|  fail to open the file; that failure is reported once to console.  |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_LOGGER_MQH__
#define __QME_CORE_LOGGER_MQH__

#include "Constants.mqh"
#include "Enums.mqh"
#include "Utils.mqh"
#include "Config.mqh"

class CLogger
  {
private:
   ENUM_QME_SEVERITY m_minLevel;
   bool              m_toConsole;
   bool              m_toFile;
   bool              m_fileOk;
   bool              m_fileWarned;
   int               m_handle;
   int               m_written;
   int               m_counts[QME_LOG_COUNT];
   string            m_lastError;
   datetime          m_lastErrorTime;

   //--- ring buffer (parallel arrays: MQL5 cannot hold strings in fixed
   //--- arrays of structures reliably)
   string            m_ringModule[QME_MAX_LOG_RING];
   string            m_ringText[QME_MAX_LOG_RING];
   datetime          m_ringTime[QME_MAX_LOG_RING];
   int               m_ringSev[QME_MAX_LOG_RING];
   int               m_ringCount;
   int               m_ringHead;

   bool              OpenFile();
   string            Compose(const ENUM_QME_SEVERITY sev, const string module, const string msg);

public:
                     CLogger(void);
   bool              Init(const SInputs &in, string &err);
   void              Shutdown(void);

   void              Log(const ENUM_QME_SEVERITY sev, const string module, const string msg);
   void              Trace(const string m, const string t) { Log(QME_LOG_TRACE, m, t); }
   void              Debug(const string m, const string t) { Log(QME_LOG_DEBUG, m, t); }
   void              Info (const string m, const string t) { Log(QME_LOG_INFO,  m, t); }
   void              Warn (const string m, const string t) { Log(QME_LOG_WARN,  m, t); }
   void              Error(const string m, const string t) { Log(QME_LOG_ERROR, m, t); }
   void              Critical(const string m, const string t){ Log(QME_LOG_CRITICAL, m, t); }

   //--- diagnostics accessors (dashboard / health monitor)
   int               Count(const ENUM_QME_SEVERITY sev);
   int               ErrorCount(void) { return(Count(QME_LOG_ERROR) + Count(QME_LOG_CRITICAL)); }
   string            LastError(void)  { return(m_lastError); }
   datetime          LastErrorTime(void) { return(m_lastErrorTime); }
   int               RingCount(void)  { return(m_ringCount); }
   //--- i = 0 -> newest entry; returns false when out of range
   bool              RingAt(const int i, string &module, string &text,
                            datetime &time, int &severity);
   void              Flush(void);
  };

CLogger *g_log = NULL;

//--- convenience helpers: safe when the logger is not yet initialised
void QmeLogMsg(const ENUM_QME_SEVERITY sev, const string module, const string msg)
  {
   if(g_log != NULL)
      g_log.Log(sev, module, msg);
   else
      Print(QME_TAG, " ", QmeSeverityName(sev), " | ", module, " | ", msg);
  }

void QmeLogInfo(const string module, const string msg) { QmeLogMsg(QME_LOG_INFO,  module, msg); }
void QmeLogWarn(const string module, const string msg) { QmeLogMsg(QME_LOG_WARN,  module, msg); }
void QmeLogError(const string module, const string msg){ QmeLogMsg(QME_LOG_ERROR, module, msg); }
void QmeLogDebug(const string module, const string msg){ QmeLogMsg(QME_LOG_DEBUG, module, msg); }

//------------------------------------------------------------------//
CLogger::CLogger(void)
  {
   m_minLevel = QME_LOG_INFO;
   m_toConsole = true;
   m_toFile = true;
   m_fileOk = false;
   m_fileWarned = false;
   m_handle = INVALID_HANDLE;
   m_written = 0;
   m_lastError = "";
   m_lastErrorTime = 0;
   m_ringCount = 0;
   m_ringHead = 0;
   for(int i = 0; i < QME_LOG_COUNT; i++) m_counts[i] = 0;
   for(int i = 0; i < QME_MAX_LOG_RING; i++)
     {
      m_ringModule[i] = "";
      m_ringText[i] = "";
      m_ringTime[i] = 0;
      m_ringSev[i] = QME_LOG_INFO;
     }
  }

//------------------------------------------------------------------//
bool CLogger::OpenFile()
  {
   //--- common folder so the file is shared with the Strategy Tester
   m_handle = FileOpen(QME_LOG_FILE,
                       FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ,
                       ';');
   if(m_handle == INVALID_HANDLE)
      return(false);
   FileSeek(m_handle, 0, SEEK_END);
   m_fileOk = true;
   return(true);
  }

//------------------------------------------------------------------//
bool CLogger::Init(const SInputs &in, string &err)
  {
   err = "";
   m_minLevel  = in.logLevel;
   m_toConsole = true;
   m_toFile    = in.logToFile;

   if(m_toFile)
     {
      if(!OpenFile())
        {
         //--- non fatal: keep running with console only, but say so explicitly
         err = "log file could not be opened (" + QME_LOG_FILE + "), console logging only";
         Print(QME_TAG, " WARN Logger: ", err);
         m_toFile = false;
        }
     }
   Log(QME_LOG_INFO, "Logger", "logging started, level=" + QmeSeverityName(m_minLevel));
   return(true);
  }

//------------------------------------------------------------------//
void CLogger::Shutdown(void)
  {
   Log(QME_LOG_INFO, "Logger", "logging stopped");
   Flush();
   if(m_fileOk && m_handle != INVALID_HANDLE)
     {
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
      m_fileOk = false;
     }
  }

//------------------------------------------------------------------//
string CLogger::Compose(const ENUM_QME_SEVERITY sev, const string module, const string msg)
  {
   return(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " +
          QmeSeverityName(sev) + " | " + module + " | " + msg);
  }

//------------------------------------------------------------------//
void CLogger::Log(const ENUM_QME_SEVERITY sev, const string module, const string msg)
  {
   m_counts[(int)sev]++;

   //--- remember the last error-level message for the dashboard
   if(sev >= QME_LOG_WARN)
     {
      m_lastError = module + ": " + msg;
      m_lastErrorTime = TimeCurrent();
     }

   //--- ring buffer (always, regardless of the console filter)
   m_ringModule[m_ringHead] = module;
   m_ringText[m_ringHead]   = msg;
   m_ringTime[m_ringHead]   = TimeCurrent();
   m_ringSev[m_ringHead]    = (int)sev;
   m_ringHead = (m_ringHead + 1) % QME_MAX_LOG_RING;
   if(m_ringCount < QME_MAX_LOG_RING) m_ringCount++;

   if(sev < m_minLevel)
      return;

   const string line = Compose(sev, module, msg);
   if(m_toConsole)
      Print(QME_TAG, " ", line);

   if(m_toFile && m_fileOk && m_handle != INVALID_HANDLE)
     {
      FileWrite(m_handle, line);
      m_written++;
      if((m_written % 20) == 0)
         FileFlush(m_handle);
     }
  }

//------------------------------------------------------------------//
void CLogger::Flush(void)
  {
   if(m_fileOk && m_handle != INVALID_HANDLE)
      FileFlush(m_handle);
  }

//------------------------------------------------------------------//
int CLogger::Count(const ENUM_QME_SEVERITY sev)
  {
   if(sev < 0 || sev >= QME_LOG_COUNT) return(0);
   return(m_counts[(int)sev]);
  }

//------------------------------------------------------------------//
bool CLogger::RingAt(const int i, string &module, string &text, datetime &time, int &severity)
  {
   module = ""; text = ""; time = 0; severity = QME_LOG_INFO;
   if(i < 0 || i >= m_ringCount) return(false);
   const int idx = (m_ringHead - 1 - i + QME_MAX_LOG_RING * 2) % QME_MAX_LOG_RING;
   module   = m_ringModule[idx];
   text     = m_ringText[idx];
   time     = m_ringTime[idx];
   severity = m_ringSev[idx];
   return(true);
  }

#endif // __QME_CORE_LOGGER_MQH__
//+------------------------------------------------------------------+
