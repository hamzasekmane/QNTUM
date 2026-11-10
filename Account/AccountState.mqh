//+------------------------------------------------------------------+
//|                                          Account/AccountState.mqh |
//|  QuantumMarketEngine — rolling account metrics used by the risk     |
//|  guards: daily P/L, peak equity drawdown, consecutive losses.       |
//|                                                                   |
//|  AUTHORITY: these values are RE-DERIVED from broker history on      |
//|  start and after every closed deal. Local counters are a cache.     |
//+------------------------------------------------------------------+
#ifndef __QME_ACCOUNT_ACCOUNTSTATE_MQH__
#define __QME_ACCOUNT_ACCOUNTSTATE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

class CAccountState
  {
private:
   double            m_dayStartEquity;
   double            m_dayStartBalance;
   datetime          m_dayStart;
   double            m_peakEquity;
   double            m_realizedToday;
   int               m_closedTradesToday;
   int               m_consecutiveLosses;
   int               m_maxConsecutiveLosses;
   double            m_worstDailyLossPct;
   bool              m_initialized;

public:
                     CAccountState(void) { Reset(); }

   void              Reset(void);
   //--- initialise baselines from the current account snapshot
   void              Init(const SAccountContext &acc);
   //--- roll the daily baseline when the server date changes
   bool              RollDay(const datetime serverTime, const SAccountContext &acc);
   //--- update running extremes (call after each refresh)
   void              Update(const SAccountContext &acc);

   //--- authoritative re-derivation from broker deal history
   void              SyncFromHistory(const ulong magic, const datetime serverTime);

   //--- metrics (percentages, always >= 0)
   double            DailyPlPct(const SAccountContext &acc);
   double            DrawdownPct(const SAccountContext &acc);

   double            DayStartEquity(void) { return(m_dayStartEquity); }
   double            PeakEquity(void) { return(m_peakEquity); }
   double            RealizedToday(void) { return(m_realizedToday); }
   int               ClosedTradesToday(void) { return(m_closedTradesToday); }
   int               ConsecutiveLosses(void) { return(m_consecutiveLosses); }
   int               MaxConsecutiveLosses(void) { return(m_maxConsecutiveLosses); }
   datetime          DayStart(void) { return(m_dayStart); }
   bool              Initialized(void) { return(m_initialized); }

   void              OnClosedTrade(const double profit);
   void              OnNewDay(const datetime serverTime, const SAccountContext &acc);

   //--- persistence (text, one record)
   string            Serialize(void);
   bool              Deserialize(const string line);
  };

//------------------------------------------------------------------//
void CAccountState::Reset(void)
  {
   m_dayStartEquity = 0.0;
   m_dayStartBalance = 0.0;
   m_dayStart = 0;
   m_peakEquity = 0.0;
   m_realizedToday = 0.0;
   m_closedTradesToday = 0;
   m_consecutiveLosses = 0;
   m_maxConsecutiveLosses = 0;
   m_worstDailyLossPct = 0.0;
   m_initialized = false;
  }

void CAccountState::Init(const SAccountContext &acc)
  {
   m_dayStartEquity = acc.equity;
   m_dayStartBalance = acc.balance;
   m_dayStart = TimeCurrent();
   m_peakEquity = acc.equity;
   m_initialized = (acc.equity > 0.0);
  }

//------------------------------------------------------------------//
bool CAccountState::RollDay(const datetime serverTime, const SAccountContext &acc)
  {
   if(!m_initialized)
     {
      Init(acc);
      return(true);
     }
   MqlDateTime a, b;
   TimeToStruct(serverTime, a);
   TimeToStruct(m_dayStart, b);
   if(a.day == b.day && a.mon == b.mon && a.year == b.year)
      return(false);
   OnNewDay(serverTime, acc);
   return(true);
  }

//------------------------------------------------------------------//
void CAccountState::OnNewDay(const datetime serverTime, const SAccountContext &acc)
  {
   //--- remember the worst daily loss observed (informational)
   const double dpl = DailyPlPct(acc);
   if(dpl < -m_worstDailyLossPct) m_worstDailyLossPct = -dpl;
   m_dayStartEquity = acc.equity;
   m_dayStartBalance = acc.balance;
   m_dayStart = serverTime;
   m_realizedToday = 0.0;
   m_closedTradesToday = 0;
  }

//------------------------------------------------------------------//
void CAccountState::Update(const SAccountContext &acc)
  {
   if(!m_initialized && acc.equity > 0.0)
      Init(acc);
   if(acc.equity > m_peakEquity) m_peakEquity = acc.equity;
  }

//------------------------------------------------------------------//
double CAccountState::DailyPlPct(const SAccountContext &acc)
  {
   if(m_dayStartEquity <= 0.0) return(0.0);
   return(100.0 * (acc.equity - m_dayStartEquity) / m_dayStartEquity);
  }

//------------------------------------------------------------------//
double CAccountState::DrawdownPct(const SAccountContext &acc)
  {
   if(m_peakEquity <= 0.0) return(0.0);
   const double dd = 100.0 * (m_peakEquity - acc.equity) / m_peakEquity;
   return(MathMax(0.0, dd));
  }

//------------------------------------------------------------------//
void CAccountState::OnClosedTrade(const double profit)
  {
   m_realizedToday += profit;
   m_closedTradesToday++;
   if(profit < 0.0)
     {
      m_consecutiveLosses++;
      if(m_consecutiveLosses > m_maxConsecutiveLosses)
         m_maxConsecutiveLosses = m_consecutiveLosses;
     }
   else if(profit > 0.0)
      m_consecutiveLosses = 0;
  }

//------------------------------------------------------------------//
//| Re-derive today's realised P/L and the consecutive-loss streak from |
//| the broker's deal history (authoritative). Positions opened by other |
//| EAs are ignored by filtering on our magic number.                    |
//+------------------------------------------------------------------//
void CAccountState::SyncFromHistory(const ulong magic, const datetime serverTime)
  {
   if(!m_initialized) return;

   //--- streak window: 30 days is enough for any sane guard
   const datetime streakFrom = serverTime - 30 * 86400;
   if(!HistorySelect(streakFrom, serverTime))
      return;

   const int deals = HistoryDealsTotal();
   m_consecutiveLosses = 0;
   m_realizedToday = 0.0;
   m_closedTradesToday = 0;

   MqlDateTime dayDt;
   TimeToStruct(m_dayStart, dayDt);

   for(int i = 0; i < deals; i++)
     {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic) continue;

      const long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
         continue;

      const double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      //--- daily accumulation
      const datetime dt = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      MqlDateTime d;
      TimeToStruct(dt, d);
      if(d.day == dayDt.day && d.mon == dayDt.mon && d.year == dayDt.year)
        {
         m_realizedToday += profit;
         m_closedTradesToday++;
        }
     }

   //--- recompute streak walking backwards (deals are chronological)
   int streak = 0;
   for(int i = deals - 1; i >= 0; i--)
     {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic) continue;
      const long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
         continue;
      const double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(profit < 0.0) streak++;
      else if(profit > 0.0) break;
      //--- profit == 0 (break-even) does not break the streak
     }
   m_consecutiveLosses = streak;
   if(streak > m_maxConsecutiveLosses) m_maxConsecutiveLosses = streak;
  }

//------------------------------------------------------------------//
string CAccountState::Serialize(void)
  {
   return("state;" +
          IntegerToString((long)m_dayStart) + ";" +
          DoubleToString(m_dayStartEquity, 2) + ";" +
          DoubleToString(m_dayStartBalance, 2) + ";" +
          DoubleToString(m_peakEquity, 2) + ";" +
          IntegerToString(m_consecutiveLosses) + ";" +
          IntegerToString(m_maxConsecutiveLosses) + ";" +
          DoubleToString(m_realizedToday, 2) + ";" +
          IntegerToString(m_closedTradesToday));
  }

//------------------------------------------------------------------//
bool CAccountState::Deserialize(const string line)
  {
   string parts[];
   const int n = StringSplit(line, ';', parts);
   if(n < 9) return(false);
   if(parts[0] != "state") return(false);
   m_dayStart = (datetime)StringToInteger(parts[1]);
   m_dayStartEquity = StringToDouble(parts[2]);
   m_dayStartBalance = StringToDouble(parts[3]);
   m_peakEquity = StringToDouble(parts[4]);
   m_consecutiveLosses = (int)StringToInteger(parts[5]);
   m_maxConsecutiveLosses = (int)StringToInteger(parts[6]);
   m_realizedToday = StringToDouble(parts[7]);
   m_closedTradesToday = (int)StringToInteger(parts[8]);
   m_initialized = (m_dayStartEquity > 0.0);
   return(m_initialized);
  }

#endif // __QME_ACCOUNT_ACCOUNTSTATE_MQH__
//+------------------------------------------------------------------+
