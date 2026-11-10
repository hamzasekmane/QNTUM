//+------------------------------------------------------------------+
//|                                          Output/AlertPort         |
//|  Abstract destination for alerts + the three concrete ports.          |
//|                                                                   |
//|  MQL5 has no interfaces, so a port is a class with virtual methods     |
//|  and a safe default body. Adding a new channel (Telegram, webhook)      |
//|  means deriving from CAlertPort and registering it; no existing code    |
//|  changes.                                                          |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_ALERTPORT_MQH__
#define __QME_OUT_ALERTPORT_MQH__

#include "../Core/Constants.mqh"
#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

class CAlertPort
  {
protected:
   bool              m_enabled;
   long              m_sent;
   long              m_failed;
   string            m_name;

public:
                     CAlertPort(void) { m_enabled = false; m_sent = 0; m_failed = 0; m_name = "port"; }
   virtual          ~CAlertPort(void) {}

   virtual string    Name(void) { return(m_name); }
   virtual bool      Enabled(void) { return(m_enabled); }
   virtual void      Enable(const bool on) { m_enabled = on; }

   //--- returns true only when the alert actually left the terminal
   virtual bool      Send(const ENUM_QME_SEVERITY sev, const string title, const string text)
     {
      return(false);
     }
   long              Sent(void) { return(m_sent); }
   long              Failed(void) { return(m_failed); }
   string            Describe(void);
  };

string CAlertPort::Describe(void)
  {
   return(m_name + (m_enabled ? "" : " (off)") + " sent=" +
          IntegerToString((int)m_sent) + " failed=" + IntegerToString((int)m_failed));
  }

//+------------------------------------------------------------------+
class CConsoleAlertPort : public CAlertPort
  {
public:
                     CConsoleAlertPort(void) { m_name = "console"; m_enabled = true; }
   virtual bool      Send(const ENUM_QME_SEVERITY sev, const string title, const string text);
  };

bool CConsoleAlertPort::Send(const ENUM_QME_SEVERITY sev, const string title, const string text)
  {
   if(!m_enabled) return(false);
   Print(QME_TAG, " ALERT [", QmeSeverityName(sev), "] ", title, " - ", text);
   m_sent++;
   return(true);
  }

//+------------------------------------------------------------------+
class CFileAlertPort : public CAlertPort
  {
private:
   string            m_path;

public:
                     CFileAlertPort(void) { m_name = "file"; m_enabled = false; m_path = ""; }
   bool              Init(const string fileName);
   virtual bool      Send(const ENUM_QME_SEVERITY sev, const string title, const string text);
  };

//------------------------------------------------------------------//
bool CFileAlertPort::Init(const string fileName)
  {
   if(StringLen(fileName) == 0) return(false);
   m_path = QME_STATE_FOLDER + "\\" + fileName;
   m_enabled = true;
   return(true);
  }

bool CFileAlertPort::Send(const ENUM_QME_SEVERITY sev, const string title, const string text)
  {
   if(!m_enabled) return(false);
   const int h = FileOpen(m_path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI |
                                  FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
     {
      m_failed++;
      return(false);
     }
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + ";" +
             QmeSeverityName(sev) + ";" + title + ";" + text);
   FileClose(h);
   m_sent++;
   return(true);
  }

//+------------------------------------------------------------------+
class CPushAlertPort : public CAlertPort
  {
public:
                     CPushAlertPort(void) { m_name = "push"; m_enabled = false; }
   virtual bool      Send(const ENUM_QME_SEVERITY sev, const string title, const string text);
  };

bool CPushAlertPort::Send(const ENUM_QME_SEVERITY sev, const string title, const string text)
  {
   if(!m_enabled) return(false);
   //--- mobile push is rate limited by the terminal; failures are reported
   const string msg = title + ": " + text;
   if(!SendNotification(msg))
     {
      m_failed++;
      return(false);
     }
   m_sent++;
   return(true);
  }

#endif // __QME_OUT_ALERTPORT_MQH__
//+------------------------------------------------------------------+
