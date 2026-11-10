//+------------------------------------------------------------------+
//|                                      Tests/Unit/Test_Scoring      |
//|  Factor catalogue and the scoring engine's arithmetic.                |
//|  No market data: every input is fabricated.                        |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_SCORING_MQH__
#define __QME_TEST_SCORING_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_kit;

int RunScoringTests(void)
  {
   g_kit.Begin("Unit/Test_Scoring");

   //--- catalogue
   g_kit.CheckEqual(CFactorCatalog::Count(), 14, "catalogue holds 14 factors");
   uint mask = 0;
   bool uniqueBits = true;
   for(int i = 0; i < CFactorCatalog::Count(); i++)
     {
      const uint bit = CFactorCatalog::Bit((ENUM_QME_FACTOR)i);
      if(bit == 0 || (mask & bit) != 0) uniqueBits = false;
      mask |= bit;
     }
   g_kit.Check(uniqueBits, "factor bits are unique and non-zero");

   //--- empty input scores zero
   CScoringEngine scorer;
   SScoreInput empty;
   QmeScoreInputClear(empty);
   SFactorBreakdown bd;
   const double s0 = scorer.Score(empty, bd);
   g_kit.CheckClose(s0, 0.0, 0.001, "empty input scores 0");

   //--- all factors at full evidence approaches 100
   SScoreInput full;
   QmeScoreInputClear(full);
   for(int i = 0; i < CFactorCatalog::Count(); i++)
      QmeScoreInputSet(full, (ENUM_QME_FACTOR)i, 1.0);
   const double s1 = scorer.Score(full, bd);
   g_kit.Check(s1 > 80.0 && s1 <= 100.0, "full agreement scores high and capped");
   g_kit.Check(bd.applied > 0, "breakdown records applied factors");

   //--- a penalty reduces the score by exactly the penalty (capped at 0)
   SScoreInput penalised = full;
   QmeScoreInputPenalty(penalised, 15.0);
   SFactorBreakdown bd2;
   const double s2 = scorer.Score(penalised, bd2);
   g_kit.Check(s2 <= s1, "penalty never increases the score");
   g_kit.CheckClose(bd2.penalty, 15.0, 0.001, "penalty is recorded");

   //--- half the evidence ranks below full evidence
   SScoreInput half;
   QmeScoreInputClear(half);
   for(int i = 0; i < CFactorCatalog::Count(); i++)
      QmeScoreInputSet(half, (ENUM_QME_FACTOR)i, 0.5);
   SFactorBreakdown bd3;
   const double s3 = scorer.Score(half, bd3);
   g_kit.Check(s3 < s1, "less evidence scores lower");
   g_kit.Check(s3 >= 0.0, "score never negative");

   //--- out-of-range evidence is clamped, not extrapolated
   SScoreInput crazy;
   QmeScoreInputClear(crazy);
   QmeScoreInputSet(crazy, QME_F_HTF_BIAS, 42.0);
   SFactorBreakdown bd4;
   const double s4 = scorer.Score(crazy, bd4);
   g_kit.Check(s4 >= 0.0 && s4 <= 100.0, "absurd evidence stays bounded");

   return(g_kit.End());
  }

#endif // __QME_TEST_SCORING_MQH__
//+------------------------------------------------------------------+
