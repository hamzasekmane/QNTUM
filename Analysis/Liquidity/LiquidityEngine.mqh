//+------------------------------------------------------------------+
//|                               Analysis/Liquidity/LiquidityEngine  |
//|  Orchestrates PdhPdl + session levels + the liquidity map into one   |
//|  validated result per symbol/timeframe.                             |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_LIQUIDITYENGINE_MQH__
#define __QME_ANALYSIS_LIQUIDITYENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Data/TimeframeContext.mqh"
#include "../../Data/MarketClock.mqh"
#include "PdhPdlEngine.mqh"
#include "SessionLiquidity.mqh"
#include "LiquidityMap.mqh"

struct SLiquidityAnalysis
  {
   SLiquidityMap     map;
   SPdhPdl           dayWeek;
   SSessionLevels    session;
   ENUM_QME_SESSION  sessionTag;
   bool              valid;
  };

class CLiquidityEngine
  {
public:
   static bool       Evaluate(CTimeframeContext &ctx, const SStructureState &state,
                              const datetime gmtNow, const long serverGmtOffsetSec,
                              const ENUM_QME_SESSION sessionTag,
                              SLiquidityAnalysis &out);
  };

//------------------------------------------------------------------//
bool CLiquidityEngine::Evaluate(CTimeframeContext &ctx, const SStructureState &state,
                                const datetime gmtNow, const long serverGmtOffsetSec,
                                const ENUM_QME_SESSION sessionTag,
                                SLiquidityAnalysis &out)
  {
   QmeLiquidityReset(out.map);
   out.valid = false;
   out.sessionTag = sessionTag;

   CBarSeries *series = ctx.Series();
   if(series == NULL || !series.IsValid()) return(false);

   const string symbol = series.Symbol();
   CPdhPdlEngine::Evaluate(symbol, out.dayWeek);
   out.session = CSessionLiquidity::Evaluate(*series, sessionTag, gmtNow, serverGmtOffsetSec);

   const double price = series.Close(0);
   const double atr = MathMax(ctx.Atr(), QME_EPSILON);

   out.valid = CLiquidityMapBuilder::Build(*series, state, out.dayWeek, out.session,
                                           atr, price, out.map);
   return(out.valid);
  }

#endif // __QME_ANALYSIS_LIQUIDITYENGINE_MQH__
//+------------------------------------------------------------------+
