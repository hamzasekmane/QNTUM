//+------------------------------------------------------------------+
//|                                    Intelligence/ProbabilityModel  |
//|  A probability estimate is ONLY produced when it is supported by     |
//|  observed outcomes and a calibration table with enough samples.        |
//|                                                                   |
//|  Otherwise `available` is false and the caller must use the heuristic |
//|  score (explicitly NOT a probability) instead. This is the guard       |
//|  against presenting a made-up "win probability".                     |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_PROBABILITY_MQH__
#define __QME_INTEL_PROBABILITY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "ClassPrior.mqh"

struct SProbabilityEstimate
  {
   bool              available;
   double            probability;    // 0..1, calibrated
   double            lower;          // 95% Wilson lower bound
   double            upper;
   int               samples;
   string            basis;          // what the estimate is based on
  };

class CProbabilityModel
  {
private:
   int               m_minSamples;

public:
                     CProbabilityModel(void) { m_minSamples = 50; }
   void              Init(const int minSamples) { m_minSamples = (minSamples < 30) ? 30 : minSamples; }

   //--- from raw counts; refuses to answer without enough evidence
   SProbabilityEstimate FromCounts(const int wins, const int total, const string basis);

   //--- from a prior class
   SProbabilityEstimate FromPrior(CClassPrior &prior, const string key);

   static double     WilsonLower(const double p, const int n, const double z = 1.96);
   static double     WilsonUpper(const double p, const int n, const double z = 1.96);
  };

//------------------------------------------------------------------//
double CProbabilityModel::WilsonLower(const double p, const int n, const double z)
  {
   if(n <= 0) return(0.0);
   const double denom = 1.0 + z * z / n;
   const double centre = p + z * z / (2.0 * n);
   const double margin = z * MathSqrt((p * (1.0 - p) + z * z / (4.0 * n)) / n);
   return(QmeClamp((centre - margin) / denom, 0.0, 1.0));
  }

//------------------------------------------------------------------//
double CProbabilityModel::WilsonUpper(const double p, const int n, const double z)
  {
   if(n <= 0) return(1.0);
   const double denom = 1.0 + z * z / n;
   const double centre = p + z * z / (2.0 * n);
   const double margin = z * MathSqrt((p * (1.0 - p) + z * z / (4.0 * n)) / n);
   return(QmeClamp((centre + margin) / denom, 0.0, 1.0));
  }

//------------------------------------------------------------------//
SProbabilityEstimate CProbabilityModel::FromCounts(const int wins, const int total,
                                                   const string basis)
  {
   SProbabilityEstimate r;
   r.available = false;
   r.probability = 0.0;
   r.lower = 0.0;
   r.upper = 1.0;
   r.samples = total;
   r.basis = basis;

   if(total < m_minSamples || wins < 0 || wins > total)
      return(r);   // not enough evidence: refuse to invent a number

   r.probability = (double)wins / (double)total;
   r.lower = WilsonLower(r.probability, total);
   r.upper = WilsonUpper(r.probability, total);
   r.available = true;
   return(r);
  }

//------------------------------------------------------------------//
SProbabilityEstimate CProbabilityModel::FromPrior(CClassPrior &prior, const string key)
  {
   SClassPrior p;
   const bool supported = prior.Get(key, p);
   if(!supported)
     {
      SProbabilityEstimate none;
      none.available = false;
      none.probability = 0.0;
      none.lower = 0.0;
      none.upper = 1.0;
      none.samples = p.samples;
      none.basis = "class prior below minimum samples";
      return(none);
     }
   return(FromCounts(p.wins, p.samples, "class prior " + key));
  }

#endif // __QME_INTEL_PROBABILITY_MQH__
//+------------------------------------------------------------------+
