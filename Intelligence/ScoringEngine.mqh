//+------------------------------------------------------------------+
//|                                     Intelligence/ScoringEngine    |
//|  Explainable composite score in [0,100].                          |
//|                                                                   |
//|  ALGORITHM (documented, deterministic, testable):                   |
//|                                                                   |
//|   1. Each usable factor f has a raw evidence value r(f) in [0,1]     |
//|      and an effective weight w(f) (default or adapted).              |
//|   2. Factors are grouped into FAMILIES (direction, structure,          |
//|      liquidity, imbalance, momentum, context).                        |
//|   3. A family contributes at most the weight of its heaviest member.   |
//|      Within a family, evidence is weighted-averaged:                   |
//|         familyScore = SUM(w*r) / SUM(w)                                |
//|         familyCap   = MAX(w)                                          |
//|         contribution= familyScore * familyCap                         |
//|      This is what prevents BOS+MSS+structure (3 correlated facts)      |
//|      from being counted three times.                                  |
//|   4. score = 100 * SUM(contribution) / SUM(familyCap) - penalty        |
//|                                                                   |
//|  The per-factor contributions sum exactly to SUM(contribution), so the  |
//|  breakdown shown on the dashboard is arithmetically consistent.        |
//|                                                                   |
//|  The score is a HEURISTIC RANKING, NOT a probability.                  |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_SCORINGENGINE_MQH__
#define __QME_INTEL_SCORINGENGINE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "AdaptiveWeights.mqh"

struct SScoreInput
  {
   double            raw[QME_F_COUNT];
   bool              available[QME_F_COUNT];
   double            penalty;      // explicit 0..100 deduction
  };

void QmeScoreInputClear(SScoreInput &in)
  {
   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      in.raw[i] = 0.0;
      in.available[i] = false;
     }
   in.penalty = 0.0;
  }

void QmeScoreInputSet(SScoreInput &in, const ENUM_QME_FACTOR f, const double raw)
  {
   const int i = (int)f;
   if(i < 0 || i >= (int)QME_F_COUNT) return;
   if(!QmeIsFinite(raw)) return;
   in.raw[i] = QmeClamp(raw, 0.0, 1.0);
   in.available[i] = true;
  }

void QmeScoreInputPenalty(SScoreInput &in, const double points)
  {
   in.penalty = QmeClamp(in.penalty + points, 0.0, QME_SCORE_MAX);
  }

class CScoringEngine
  {
private:
   CAdaptiveWeights *m_weights;

public:
                     CScoringEngine(void) { m_weights = NULL; }
   void              AttachWeights(CAdaptiveWeights *w) { m_weights = w; }
   bool              HasWeights(void) { return(m_weights != NULL); }

   //--- fills `out` completely; returns the final score
   double            Score(const SScoreInput &in, SFactorBreakdown &out);
   double            Weight(const ENUM_QME_FACTOR f);
   string            Explain(const SFactorBreakdown &b);
  };

//------------------------------------------------------------------//
double CScoringEngine::Weight(const ENUM_QME_FACTOR f)
  {
   if(m_weights != NULL) return(m_weights.Weight(f));
   return(CFactorCatalog::DefaultWeight(f));
  }

//------------------------------------------------------------------//
double CScoringEngine::Score(const SScoreInput &in, SFactorBreakdown &out)
  {
   QmeBreakdownReset(out);

   //--- family accumulators
   double famWeightedRaw[QME_FAM_COUNT];
   double famSumWeight[QME_FAM_COUNT];
   double famCap[QME_FAM_COUNT];
   for(int f = 0; f < (int)QME_FAM_COUNT; f++)
     {
      famWeightedRaw[f] = 0.0;
      famSumWeight[f] = 0.0;
      famCap[f] = 0.0;
     }

   //--- pass 1: accumulate per family
   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      const ENUM_QME_FACTOR factor = (ENUM_QME_FACTOR)i;
      const bool avail = in.available[i];
      const double w = Weight(factor);
      out.items[i].factor = factor;
      out.items[i].raw = in.raw[i];
      out.items[i].available = avail;
      if(!avail || w <= 0.0) continue;

      const int fam = (int)CFactorCatalog::Family(factor);
      famWeightedRaw[fam] += w * QmeClamp(in.raw[i], 0.0, 1.0);
      famSumWeight[fam] += w;
      if(w > famCap[fam]) famCap[fam] = w;
     }

   //--- pass 2: family scores and effective factor weights
   double sumContrib = 0.0;
   double sumCap = 0.0;
   int familiesUsed = 0;

   for(int f = 0; f < (int)QME_FAM_COUNT; f++)
     {
      if(famSumWeight[f] <= QME_EPSILON) continue;
      familiesUsed++;
      sumCap += famCap[f];
     }

   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      if(!out.items[i].available) continue;
      const int fam = (int)CFactorCatalog::Family((ENUM_QME_FACTOR)i);
      if(famSumWeight[fam] <= QME_EPSILON) continue;

      const double shared = famCap[fam] * (Weight((ENUM_QME_FACTOR)i) / famSumWeight[fam]);
      out.items[i].weight = shared;
      out.items[i].contribution = shared * QmeClamp(out.items[i].raw, 0.0, 1.0);
      sumContrib += out.items[i].contribution;
      out.applied++;
     }

   out.sum = sumContrib;
   out.maxSum = sumCap;
   out.penalty = QmeClamp(in.penalty, 0.0, QME_SCORE_MAX);
   out.familiesUsed = familiesUsed;

   double score = 0.0;
   if(sumCap > QME_EPSILON)
      score = 100.0 * sumContrib / sumCap;
   score -= out.penalty;
   out.score = QmeClamp(score, 0.0, QME_SCORE_MAX);
   return(out.score);
  }

//------------------------------------------------------------------//
string CScoringEngine::Explain(const SFactorBreakdown &b)
  {
   string s = "";
   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      if(!b.items[i].available) continue;
      s += QmeFactorName(b.items[i].factor) + "=" +
           QmeFmt(100.0 * b.items[i].raw, 0) + "%" +
           "(w" + QmeFmt(b.items[i].weight, 2) + ",+" +
           QmeFmt(b.items[i].contribution, 2) + ") ";
     }
   s += "=> score=" + QmeFmt(b.score, 1);
   if(b.penalty > 0.0) s += " (penalty " + QmeFmt(b.penalty, 1) + ")";
   return(s);
  }

#endif // __QME_INTEL_SCORINGENGINE_MQH__
//+------------------------------------------------------------------+
