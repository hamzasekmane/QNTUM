//+------------------------------------------------------------------+
//|                                 Intelligence/SignalQualityEngine  |
//|  Final quality gate before a candidate becomes a signal.             |
//|                                                                   |
//|  quality = 0.45*score + 0.25*confluence + 0.20*RR adequacy           |
//|          + 0.10*data quality                                       |
//|  Every component is in [0,1]; the result is a ranking value, never   |
//|  presented as a probability.                                        |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_SIGNALQUALITY_MQH__
#define __QME_INTEL_SIGNALQUALITY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

struct SQualityResult
  {
   double            quality;      // 0..1
   bool              acceptable;
   ENUM_QME_REJECT   reason;
   double            rrComponent;
   double            dataComponent;
   string            note;
  };

class CSignalQualityEngine
  {
public:
   static SQualityResult Evaluate(const double score, const double confluence,
                                  const double rr, const double minRR,
                                  const double spreadPoints, const double spreadCap,
                                  const SDataQuality &dq, const double minQuality = 0.55);
  };

//------------------------------------------------------------------//
SQualityResult CSignalQualityEngine::Evaluate(const double score, const double confluence,
                                              const double rr, const double minRR,
                                              const double spreadPoints, const double spreadCap,
                                              const SDataQuality &dq, const double minQuality)
  {
   SQualityResult r;
   r.quality = 0.0;
   r.acceptable = false;
   r.reason = QME_REJ_NONE;
   r.rrComponent = 0.0;
   r.dataComponent = 0.0;
   r.note = "";

   //--- hard gates first: data and spread
   if(!dq.ok)
     {
      r.reason = dq.stale ? QME_REJ_STALE_DATA : QME_REJ_DATA_QUALITY;
      r.note = dq.note;
      return(r);
     }
   if(spreadCap > 0.0 && spreadPoints > spreadCap)
     {
      r.reason = QME_REJ_SPREAD;
      r.note = "spread " + QmeFmt(spreadPoints, 1) + " > cap " + QmeFmt(spreadCap, 1);
      return(r);
     }

   //--- RR adequacy: 1.0 at 2x the minimum RR
   r.rrComponent = (minRR > 0.0) ? QmeClamp(rr / (2.0 * minRR), 0.0, 1.0) : 1.0;

   //--- data component: penalise abnormal spread, reward clean quality
   r.dataComponent = dq.spreadAbnormal ? 0.4 : 0.9;
   if(dq.closedBars < QME_MIN_BARS_REQUIRED * 2) r.dataComponent *= 0.8;

   r.quality = QmeClamp(0.45 * (score / 100.0) +
                        0.25 * QmeClamp(confluence, 0.0, 1.0) +
                        0.20 * r.rrComponent +
                        0.10 * r.dataComponent, 0.0, 1.0);

   if(rr < minRR)
     {
      r.reason = QME_REJ_RR;
      r.note = "rr " + QmeFmt(rr, 2) + " < " + QmeFmt(minRR, 2);
      return(r);
     }
   if(r.quality < minQuality)
     {
      r.reason = QME_REJ_LOW_SCORE;
      r.note = "quality " + QmeFmt(r.quality, 3) + " < " + QmeFmt(minQuality, 2);
      return(r);
     }

   r.acceptable = true;
   return(r);
  }

#endif // __QME_INTEL_SIGNALQUALITY_MQH__
//+------------------------------------------------------------------+
