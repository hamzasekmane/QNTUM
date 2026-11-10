//+------------------------------------------------------------------+
//|                                          Execution/TradeJournal   |
//|  Append-only CSV record of every execution attempt.                  |
//|                                                                   |
//|  One line per event, never rewritten in place, written to the         |
//|  terminal's common folder so the strategy tester and the live         |
//|  terminal produce comparable evidence.                               |
//+------------------------------------------------------------------+
#ifndef __QME_EXECUTION_TRADEJOURNAL_MQH__
#define __QME_EXECUTION_TRADEJOURNAL_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

class CTradeJournal
  {
private:
   bool              m_enabled;
   bool              m_open;
   int               m_handle;
   string            m_path;
   int               m_records;
   long              m_login;

   bool              EnsureOpen(void);
   void              WriteLine(const string line);

public:
                     CTradeJournal(void) { m_enabled = false; m_open = false; m_handle = INVALID_HANDLE; m_path = ""; m_records = 0; m_login = 0; }
   bool              Init(const bool enabled, const long login, string &err);
   void              Shutdown(void);

   void              RecordIntent(const STradePlan &plan, const string stage, const string detail);
   void              RecordResult(const STradePlan &plan, const SExecutionResult &res);
   void              RecordEvent(const string kind, const string symbol, const string detail);
   int               Records(void) { return(m_records); }
   string            Path(void) { return(m_path); }
  };

//------------------------------------------------------------------//
bool CTradeJournal::Init(const bool enabled, const long login, string &err)
  {
   err = "";
   m_enabled = enabled;
   m_login = login;
   m_records = 0;
   if(!enabled) return(true);

   m_path = QME_STATE_FOLDER + "\\" + QME_JOURNAL_FILE_PREFIX +
            IntegerToString(login) + ".csv";
   //--- lazily opened on first write: a missing common folder is not fatal
   return(true);
  }

//------------------------------------------------------------------//
bool CTradeJournal::EnsureOpen(void)
  {
   if(!m_enabled) return(false);
   if(m_open && m_handle != INVALID_HANDLE) return(true);

   m_handle = FileOpen(m_path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI |
                              FILE_COMMON | FILE_SHARE_READ, ',');
   if(m_handle == INVALID_HANDLE)
     {
      QmeLogMsg(QME_LOG_WARN, "Journal", "cannot open " + m_path + " (" +
                QmeLastErrorText() + ")");
      m_enabled = false;
      return(false);
     }
   FileSeek(m_handle, 0, SEEK_END);
   m_open = true;

   if(FileTell(m_handle) == 0)
      FileWrite(m_handle, "time;event;signal;symbol;side;volume;entry;sl;tp;retcode;order;deal;position;price;comment");
   return(true);
  }

//------------------------------------------------------------------//
void CTradeJournal::WriteLine(const string line)
  {
   if(!EnsureOpen()) return;
   FileWrite(m_handle, line);
   FileFlush(m_handle);
   m_records++;
  }

//------------------------------------------------------------------//
void CTradeJournal::RecordIntent(const STradePlan &plan, const string stage, const string detail)
  {
   if(!m_enabled) return;
   const string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + ";" +
                       stage + ";" + IntegerToString((long)plan.signalId) + ";" +
                       plan.symbol + ";" + QmeSideName(plan.side) + ";" +
                       DoubleToString(plan.volume, 2) + ";" +
                       DoubleToString(plan.entry, 8) + ";" +
                       DoubleToString(plan.stopLoss, 8) + ";" +
                       DoubleToString(plan.takeProfit, 8) + ";;;;;;" + detail;
   WriteLine(line);
  }

//------------------------------------------------------------------//
void CTradeJournal::RecordResult(const STradePlan &plan, const SExecutionResult &res)
  {
   if(!m_enabled) return;
   const string line = TimeToString(res.time > 0 ? res.time : TimeCurrent(),
                                    TIME_DATE | TIME_SECONDS) + ";" +
                       "RESULT;" + IntegerToString((long)plan.signalId) + ";" +
                       plan.symbol + ";" + QmeSideName(plan.side) + ";" +
                       DoubleToString(res.requestedVolume, 2) + ";" +
                       DoubleToString(res.requestedPrice, 8) + ";" +
                       DoubleToString(plan.stopLoss, 8) + ";" +
                       DoubleToString(plan.takeProfit, 8) + ";" +
                       IntegerToString((int)res.retcode) + ";" +
                       IntegerToString((long)res.orderTicket) + ";" +
                       IntegerToString((long)res.dealTicket) + ";" +
                       IntegerToString((long)res.positionTicket) + ";" +
                       DoubleToString(res.filledPrice, 8) + ";" +
                       QmeRetcodeText(res.retcode) + " " + res.comment;
   WriteLine(line);
  }

//------------------------------------------------------------------//
void CTradeJournal::RecordEvent(const string kind, const string symbol, const string detail)
  {
   if(!m_enabled) return;
   const string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + ";" +
                       kind + ";0;" + symbol + ";;;;;;;;" + detail;
   WriteLine(line);
  }

//------------------------------------------------------------------//
void CTradeJournal::Shutdown(void)
  {
   if(m_open && m_handle != INVALID_HANDLE)
     {
      FileFlush(m_handle);
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
      m_open = false;
     }
   if(m_records > 0)
      QmeLogMsg(QME_LOG_INFO, "Journal", IntegerToString(m_records) + " records written to " + m_path);
  }

#endif // __QME_EXECUTION_TRADEJOURNAL_MQH__
//+------------------------------------------------------------------+
