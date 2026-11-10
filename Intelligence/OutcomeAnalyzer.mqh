//+------------------------------------------------------------------+
//|                                 Intelligence/OutcomeAnalyzer      |
//|  Statistics over realised outcomes, expressed in R multiples.        |
//|                                                                   |
//|  Nothing here predicts the future: it only summarises what actually    |
//|  happened, so the adaptive weights and the calibration table are       |
//|  driven by evidence rather than by optimism.                          |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_OUTCOMEANALYZER_MQH__
#define __QME_INTEL_OUTCOMEANALYZER_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

struct SOutcomeStats
  {
   int               samples;
   int               wins;
   int               losses;
   int               breakEven;
   double            winRate;
   double            avgWinR;
   double            avgLossR;
   double            expectancyR;   // winRate*avgWin - (1-winRate)*avgLoss
   double            profitFactor;  // gross win / gross loss
   double            totalR;
   bool              valid;         // false when samples == 0
  };

class COutcomeAnalyzer
  {
public:
   static SOutcomeStats Compute(const double &rMultiples[], const int count);
   static string     Describe(const SOutcomeStats &s);
   //--- R multiple of a closed trade relative to its planned risk
   static double     RMultiple(const double entry, const double stop,
                               const double exitPrice, const ENUM_QME_SIDE side);
  };

//------------------------------------------------------------------//
double COutcomeAnalyzer::RMultiple(const double entry, const double stop,
                                   const double exitPrice, const ENUM_QME_SIDE side)
  {
   if(side == QME_SIDE_NONE) return(0.0);
   const double risk = MathAbs(entry - stop);
   if(risk <= QME_PRICE_EPS) return(0.0);
   const double reward = (side == QME_SIDE_BUY) ? (exitPrice - entry) : (entry - exitPrice);
   return(reward / risk);
  }

//------------------------------------------------------------------//
SOutcomeStats COutcomeAnalyzer::Compute(const double &rMultiples[], const int count)
  {
   SOutcomeStats s;
   s.samples = 0;
   s.wins = 0;
   s.losses = 0;
   s.breakEven = 0;
   s.winRate = 0.0;
   s.avgWinR = 0.0;
   s.avgLossR = 0.0;
   s.expectancyR = 0.0;
   s.profitFactor = 0.0;
   s.totalR = 0.0;
   s.valid = false;

   if(count <= 0) return(s);

   double grossWin = 0.0;
   double grossLoss = 0.0;
   for(int i = 0; i < count; i++)
     {
      const double r = rMultiples[i];
      if(!QmeIsFinite(r)) continue;
      s.samples++;
      s.totalR += r;
      if(r > QME_EPSILON)       { s.wins++;   grossWin += r; }
      else if(r < -QME_EPSILON) { s.losses++; grossLoss += MathAbs(r); }
      else                       s.breakEven++;
     }

   if(s.samples <= 0) return(s);

   s.winRate = (double)s.wins / (double)s.samples;
   s.avgWinR = (s.wins > 0) ? grossWin / (double)s.wins : 0.0;
   s.avgLossR = (s.losses > 0) ? grossLoss / (double)s.losses : 0.0;
   s.expectancyR = (double)s.wins / (double)s.samples * s.avgWinR -
                   (double)s.losses / (double)s.samples * s.avgLossR;
   s.profitFactor = (grossLoss > QME_EPSILON) ? grossWin / grossLoss : 0.0;
   s.valid = true;
   return(s);
  }

//------------------------------------------------------------------//
string COutcomeAnalyzer::Describe(const SOutcomeStats &s)
  {
   if(!s.valid) return("no realised outcomes");
   return("n=" + IntegerToString(s.samples) +
          " win=" + QmeFmt(100.0 * s.winRate, 1) + "%" +
          " avgWin=" + QmeFmt(s.avgWinR, 2) + "R" +
          " avgLoss=" + QmeFmt(s.avgLossR, 2) + "R" +
          " expectancy=" + QmeFmt(s.expectancyR, 3) + "R" +
          " PF=" + QmeFmt(s.profitFactor, 2) +
          " total=" + QmeFmt(s.totalR, 1) + "R");
  }

#endif // __QME_INTEL_OUTCOMEANALYZER_MQH__
//+------------------------------------------------------------------+
