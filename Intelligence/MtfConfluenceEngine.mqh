//+------------------------------------------------------------------+
//|                                Intelligence/MtfConfluenceEngine   |
//|  Multi-timeframe agreement.                                        |
//|                                                                   |
//|  Each timeframe contributes a direction and a strength; higher        |
//|  timeframes carry more weight. Confluence = weighted fraction of      |
//|  timeframes that agree with the candidate direction.                  |
//|                                                                   |
//|  A missing/undecided timeframe is counted with weight but no          |
//|  agreement — silence never counts as confirmation.                    |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_MTFCONFLUENCE_MQH__
#define __QME_INTEL_MTFCONFLUENCE_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

struct STfView
  {
   ENUM_TIMEFRAMES   tf;
   ENUM_QME_SIDE     direction;
   double            strength;   // 0..1
  };

struct SConfluenceResult
  {
   double            score;      // 0..1 weighted agreement
   int               aligned;
   int               total;
   bool              htfAligned; // the highest timeframe agrees
   ENUM_QME_SIDE     side;
   bool              valid;
  };

class CMtfConfluenceEngine
  {
public:
   static double     TimeframeWeight(const ENUM_TIMEFRAMES tf);
   static SConfluenceResult Evaluate(const ENUM_QME_SIDE candidateSide,
                                     const STfView &views[], const int count);
  };

//------------------------------------------------------------------//
double CMtfConfluenceEngine::TimeframeWeight(const ENUM_TIMEFRAMES tf)
  {
   //--- weights roughly proportional to sqrt of the timeframe length,
   //--- normalised so M5 = 1.0
   const int minutes = QmeTimeframeMinutes(tf);
   if(minutes <= 0) return(1.0);
   const double w = MathSqrt((double)minutes / 5.0);
   return(QmeClamp(w, 1.0, 12.0));
  }

//------------------------------------------------------------------//
SConfluenceResult CMtfConfluenceEngine::Evaluate(const ENUM_QME_SIDE candidateSide,
                                                 const STfView &views[], const int count)
  {
   SConfluenceResult r;
   r.score = 0.0;
   r.aligned = 0;
   r.total = 0;
   r.htfAligned = false;
   r.side = candidateSide;
   r.valid = false;

   if(candidateSide == QME_SIDE_NONE || count <= 0) return(r);

   double totalWeight = 0.0;
   double agreeWeight = 0.0;
   int htfIndex = -1;
   int htfMinutes = -1;

   for(int i = 0; i < count; i++)
     {
      const double w = TimeframeWeight(views[i].tf) * QmeClamp(views[i].strength, 0.0, 1.0);
      totalWeight += TimeframeWeight(views[i].tf);
      if(views[i].direction == candidateSide)
        {
         agreeWeight += w;
         r.aligned++;
        }
      r.total++;

      const int m = QmeTimeframeMinutes(views[i].tf);
      if(m > htfMinutes)
        {
         htfMinutes = m;
         htfIndex = i;
        }
     }

   if(totalWeight <= QME_EPSILON) return(r);

   r.score = QmeClamp(agreeWeight / totalWeight, 0.0, 1.0);
   if(htfIndex >= 0)
      r.htfAligned = (views[htfIndex].direction == candidateSide);
   r.valid = true;
   return(r);
  }

#endif // __QME_INTEL_MTFCONFLUENCE_MQH__
//+------------------------------------------------------------------+
