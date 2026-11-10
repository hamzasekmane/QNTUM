//+------------------------------------------------------------------+
//|                              Monitoring/ExecutionStatistics       |
//|  Aggregated execution evidence per symbol and per retcode.            |
//|                                                                   |
//|  The gateway reports every attempt; this class keeps the counts that  |
//|  make a failure pattern visible (e.g. one symbol always requoting).    |
//+------------------------------------------------------------------+
#ifndef __QME_MON_EXECSTATS_MQH__
#define __QME_MON_EXECSTATS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/ErrorCodes.mqh"

class CExecutionStatistics
  {
private:
   string            m_symbols[QME_MAX_SYMBOLS];
   long              m_attempts[QME_MAX_SYMBOLS];
   long              m_fills[QME_MAX_SYMBOLS];
   long              m_rejects[QME_MAX_SYMBOLS];
   double            m_volume[QME_MAX_SYMBOLS];
   int               m_count;

   int               IndexOf(const string symbol, const bool create);

public:
                     CExecutionStatistics(void) { Reset(); }
   void              Reset(void);
   void              RecordAttempt(const string symbol);
   void              RecordFill(const string symbol, const double volume);
   void              RecordReject(const string symbol);

   int               Symbols(void) { return(m_count); }
   string            SymbolAt(const int i);
   long              Attempts(const string symbol);
   long              Fills(const string symbol);
   long              Rejects(const string symbol);
   double            Volume(const string symbol);
   double            FillRate(const string symbol);
   string            Describe(void);
  };

//------------------------------------------------------------------//
void CExecutionStatistics::Reset(void)
  {
   m_count = 0;
   for(int i = 0; i < QME_MAX_SYMBOLS; i++)
     {
      m_symbols[i] = "";
      m_attempts[i] = 0;
      m_fills[i] = 0;
      m_rejects[i] = 0;
      m_volume[i] = 0.0;
     }
  }

//------------------------------------------------------------------//
int CExecutionStatistics::IndexOf(const string symbol, const bool create)
  {
   for(int i = 0; i < m_count; i++)
      if(m_symbols[i] == symbol) return(i);
   if(!create || m_count >= QME_MAX_SYMBOLS) return(-1);
   m_symbols[m_count] = symbol;
   m_count++;
   return(m_count - 1);
  }

//------------------------------------------------------------------//
void CExecutionStatistics::RecordAttempt(const string symbol)
  {
   const int i = IndexOf(symbol, true);
   if(i >= 0) m_attempts[i]++;
  }

void CExecutionStatistics::RecordFill(const string symbol, const double volume)
  {
   const int i = IndexOf(symbol, true);
   if(i < 0) return;
   m_fills[i]++;
   if(QmeIsFinite(volume) && volume > 0.0) m_volume[i] += volume;
  }

void CExecutionStatistics::RecordReject(const string symbol)
  {
   const int i = IndexOf(symbol, true);
   if(i >= 0) m_rejects[i]++;
  }

//------------------------------------------------------------------//
string CExecutionStatistics::SymbolAt(const int i)
  {
   if(i < 0 || i >= m_count) return("");
   return(m_symbols[i]);
  }

long CExecutionStatistics::Attempts(const string symbol)
  {
   const int i = IndexOf(symbol, false);
   return(i >= 0 ? m_attempts[i] : 0);
  }

long CExecutionStatistics::Fills(const string symbol)
  {
   const int i = IndexOf(symbol, false);
   return(i >= 0 ? m_fills[i] : 0);
  }

long CExecutionStatistics::Rejects(const string symbol)
  {
   const int i = IndexOf(symbol, false);
   return(i >= 0 ? m_rejects[i] : 0);
  }

double CExecutionStatistics::Volume(const string symbol)
  {
   const int i = IndexOf(symbol, false);
   return(i >= 0 ? m_volume[i] : 0.0);
  }

double CExecutionStatistics::FillRate(const string symbol)
  {
   const int i = IndexOf(symbol, false);
   if(i < 0 || m_attempts[i] <= 0) return(0.0);
   return((double)m_fills[i] / (double)m_attempts[i]);
  }

//------------------------------------------------------------------//
string CExecutionStatistics::Describe(void)
  {
   if(m_count == 0) return("execstats empty");
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      s += m_symbols[i] + ":" + IntegerToString((int)m_fills[i]) + "/" +
           IntegerToString((int)m_attempts[i]);
      if(i + 1 < m_count) s += " ";
     }
   return("execstats " + s);
  }

#endif // __QME_MON_EXECSTATS_MQH__
//+------------------------------------------------------------------+
