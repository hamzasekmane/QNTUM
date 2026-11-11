//+------------------------------------------------------------------+
//|                                              Data/TickProcessor   |
//|  QuantumMarketEngine — live tick state and spread statistics.       |
//|                                                                   |
//|  Spread is tracked with an exponential moving average so the guard   |
//|  compares the current spread against recent behaviour, not against   |
//|  a hard-coded number that differs per broker and per session.        |
//+------------------------------------------------------------------+
#ifndef __QME_DATA_TICKPROCESSOR_MQH__
#define __QME_DATA_TICKPROCESSOR_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

class CTickProcessor
  {
private:
   string            m_symbol;
   MqlTick           m_tick;
   bool              m_valid;
   double            m_spreadAvgPoints;
   int               m_samples;
   double            m_spreadMaxPoints;
   datetime          m_lastUpdate;
   long              m_tickCount;

public:
                     CTickProcessor(void);
   bool              Init(const string symbol);
   bool              Update(void);

   bool              Valid(void) { return(m_valid); }
   string            Symbol(void) { return(m_symbol); }
   MqlTick           Tick(void) { return(m_tick); }
   double            Bid(void) { return(m_tick.bid); }
   double            Ask(void) { return(m_tick.ask); }
   datetime          TickTime(void) { return(m_tick.time); }
   long              TickCount(void) { return(m_tickCount); }

   double            SpreadPrice(void) { return(m_tick.ask - m_tick.bid); }
   double            SpreadPoints(void);
   double            SpreadAvgPoints(void) { return(m_spreadAvgPoints); }
   double            SpreadMaxPoints(void) { return(m_spreadMaxPoints); }
   double            SpreadRatio(void);

   static bool       IsTickTimeFresh(const datetime tickTime, const datetime now, const int maxAgeSec);
   bool              IsFresh(const int maxAgeSec);
   void              Reset(void);
  };

//------------------------------------------------------------------//
CTickProcessor::CTickProcessor(void)
  {
   m_symbol = "";
   m_valid = false;
   m_spreadAvgPoints = 0.0;
   m_samples = 0;
   m_spreadMaxPoints = 0.0;
   m_lastUpdate = 0;
   m_tickCount = 0;
  }

//------------------------------------------------------------------//
bool CTickProcessor::Init(const string symbol)
  {
   Reset();
   m_symbol = symbol;
   return(Update());
  }

//------------------------------------------------------------------//
void CTickProcessor::Reset(void)
  {
   m_valid = false;
   m_spreadAvgPoints = 0.0;
   m_samples = 0;
   m_spreadMaxPoints = 0.0;
   m_lastUpdate = 0;
   m_tickCount = 0;
   ZeroMemory(m_tick);
  }

//------------------------------------------------------------------//
bool CTickProcessor::Update(void)
  {
   if(StringLen(m_symbol) == 0) return(false);
   MqlTick t;
   if(!SymbolInfoTick(m_symbol, t))
     {
      m_valid = false;
      return(false);
     }
   if(t.bid <= 0.0 || t.ask <= 0.0 || t.ask < t.bid)
     {
      m_valid = false;
      return(false);
     }
   //--- a tick older than the previous one is not an update
   if(m_valid && t.time_msc < m_tick.time_msc)
     {
      m_valid = false;
      return(false);
     }

   m_tick = t;
   m_valid = true;
   m_lastUpdate = TimeCurrent();
   m_tickCount++;

   const double sp = SpreadPoints();
   if(sp > 0.0 && QmeIsFinite(sp))
     {
      if(m_samples == 0)
         m_spreadAvgPoints = sp;
      else
         m_spreadAvgPoints = m_spreadAvgPoints + 0.02 * (sp - m_spreadAvgPoints);
      if(sp > m_spreadMaxPoints) m_spreadMaxPoints = sp;
      m_samples++;
     }
   return(true);
  }

//------------------------------------------------------------------//
double CTickProcessor::SpreadPoints(void)
  {
   const double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   if(point <= 0.0) return(0.0);
   return((m_tick.ask - m_tick.bid) / point);
  }

//------------------------------------------------------------------//
double CTickProcessor::SpreadRatio(void)
  {
   if(m_spreadAvgPoints <= 0.0) return(1.0);
   return(QmeSafeDiv(SpreadPoints(), m_spreadAvgPoints, 1.0));
  }

//------------------------------------------------------------------//
bool CTickProcessor::IsTickTimeFresh(const datetime tickTime, const datetime now, const int maxAgeSec)
  {
   if(now <= 0 || tickTime <= 0 || now < tickTime) return(false);
   return(maxAgeSec <= 0 || now - tickTime <= maxAgeSec);
  }

bool CTickProcessor::IsFresh(const int maxAgeSec)
  {
   if(!m_valid) return(false);
   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED) && !(bool)MQLInfoInteger(MQL_TESTER))
      return(false);
   return(IsTickTimeFresh(m_tick.time, TimeTradeServer(), maxAgeSec));
  }

#endif // __QME_DATA_TICKPROCESSOR_MQH__
//+------------------------------------------------------------------+
