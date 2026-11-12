//+------------------------------------------------------------------+
//|                                         Risk/PortfolioRisk        |
//|  Snapshot of open positions with their monetary risk.                |
//|                                                                   |
//|  SOURCE OF TRUTH: the broker. The snapshot is rebuilt from           |
//|  PositionsTotal() on every evaluation; nothing is remembered from     |
//|  the previous cycle.                                                 |
//+------------------------------------------------------------------+
#ifndef __QME_RISK_PORTFOLIO_MQH__
#define __QME_RISK_PORTFOLIO_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

struct SPositionRisk
  {
   ulong             ticket;
   string            symbol;
   ENUM_QME_SIDE     side;
   double            volume;
   double            openPrice;
   double            sl;
   double            tp;
   double            riskMoney;    // 0 when the position has no stop
   double            notional;
   ulong             magic;
   bool              hasStop;
  };

class CPortfolioSnapshot
  {
private:
   SPositionRisk     m_items[];
   double            m_equity;
   ulong             m_magic;
   long              m_scanErrors;

public:
                     CPortfolioSnapshot(void) { Clear(); }
   void              Clear(void);
   //--- rebuild from the terminal; magic == 0 accepts every position
   void              Build(const ulong magic, const double equity);

   int               Count(void) { return(ArraySize(m_items)); }
   bool              At(const int i, SPositionRisk &out);
   double            TotalNotional(void);
   double            TotalRiskMoney(void);
   double            NotionalFor(const string symbol);
   double            RiskFor(const string symbol);
   int               CountFor(const string symbol);
   int               CountFor(const string symbol, const ENUM_QME_SIDE side);
   int               SameDirection(const ENUM_QME_SIDE side);
   int               WithoutStop(void);
   long              ScanErrors(void) { return(m_scanErrors); }
  };

//------------------------------------------------------------------//
void CPortfolioSnapshot::Clear(void)
  {
   ArrayResize(m_items, 0);
   m_equity = 0.0;
   m_magic = 0;
   m_scanErrors = 0;
  }

//------------------------------------------------------------------//
void CPortfolioSnapshot::Build(const ulong magic, const double equity)
  {
   Clear();
   m_magic = magic;
   m_equity = equity;

   const int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
        {
         m_scanErrors++;
         continue;
        }
      if(!PositionSelectByTicket(ticket))
        {
         m_scanErrors++;
         continue;
        }

      const ulong posMagic = (ulong)PositionGetInteger(POSITION_MAGIC);
      //--- magic 0 means "all positions"; otherwise only ours
      if(magic != 0 && posMagic != magic) continue;

      const string symbol = PositionGetString(POSITION_SYMBOL);
      if(StringLen(symbol) == 0) continue;

      SPositionRisk r;
      r.ticket = ticket;
      r.symbol = symbol;
      r.side = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
               QME_SIDE_BUY : QME_SIDE_SELL;
      r.volume = PositionGetDouble(POSITION_VOLUME);
      r.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      r.sl = PositionGetDouble(POSITION_SL);
      r.tp = PositionGetDouble(POSITION_TP);
      r.magic = posMagic;
      r.hasStop = (r.sl > 0.0);

      const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      const double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      const double perUnit = (tickSize > 0.0) ? tickValue / tickSize : 0.0;
      const double markPrice = MathMax(r.openPrice, SymbolInfoDouble(symbol, SYMBOL_BID));
      r.notional = QmeAccountCurrencyNotional(symbol, r.volume, markPrice);
      if(r.notional <= 0.0)
        {
         m_scanErrors++;
         QmeLogMsg(QME_LOG_WARN, "Portfolio", "account-currency notional unavailable for " + symbol);
        }
      r.riskMoney = r.hasStop ? MathAbs(r.openPrice - r.sl) * perUnit * r.volume : 0.0;

      const int n = ArraySize(m_items);
      ArrayResize(m_items, n + 1);
      m_items[n] = r;
     }

   if(m_scanErrors > 0)
      QmeLogMsg(QME_LOG_WARN, "Portfolio", IntegerToString((int)m_scanErrors) +
                " position(s) could not be read");
  }

//------------------------------------------------------------------//
bool CPortfolioSnapshot::At(const int i, SPositionRisk &out)
  {
   if(i < 0 || i >= ArraySize(m_items)) return(false);
   out = m_items[i];
   return(true);
  }

double CPortfolioSnapshot::TotalNotional(void)
  {
   double s = 0.0;
   for(int i = 0; i < ArraySize(m_items); i++) s += m_items[i].notional;
   return(s);
  }

double CPortfolioSnapshot::TotalRiskMoney(void)
  {
   double s = 0.0;
   for(int i = 0; i < ArraySize(m_items); i++) s += m_items[i].riskMoney;
   return(s);
  }

double CPortfolioSnapshot::NotionalFor(const string symbol)
  {
   double s = 0.0;
   for(int i = 0; i < ArraySize(m_items); i++)
      if(m_items[i].symbol == symbol) s += m_items[i].notional;
   return(s);
  }

double CPortfolioSnapshot::RiskFor(const string symbol)
  {
   double s = 0.0;
   for(int i = 0; i < ArraySize(m_items); i++)
      if(m_items[i].symbol == symbol) s += m_items[i].riskMoney;
   return(s);
  }

int CPortfolioSnapshot::CountFor(const string symbol)
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_items); i++)
      if(m_items[i].symbol == symbol) n++;
   return(n);
  }

int CPortfolioSnapshot::CountFor(const string symbol, const ENUM_QME_SIDE side)
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_items); i++)
      if(m_items[i].symbol == symbol && m_items[i].side == side) n++;
   return(n);
  }

int CPortfolioSnapshot::SameDirection(const ENUM_QME_SIDE side)
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_items); i++)
      if(m_items[i].side == side) n++;
   return(n);
  }

int CPortfolioSnapshot::WithoutStop(void)
  {
   int n = 0;
   for(int i = 0; i < ArraySize(m_items); i++)
      if(!m_items[i].hasStop) n++;
   return(n);
  }

#endif // __QME_RISK_PORTFOLIO_MQH__
//+------------------------------------------------------------------+
