//+------------------------------------------------------------------+
//|                                    Output/ExplanationEngine       |
//|  Plain-language explanations of every decision.                       |
//|                                                                   |
//|  The system must be able to answer "why did you not take this trade?" |
//|  and "why did you take that one?" with numbers, not adjectives.        |
//+------------------------------------------------------------------+
#ifndef __QME_OUT_EXPLANATION_MQH__
#define __QME_OUT_EXPLANATION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Analysis/FactorCatalog.mqh"
#include "../Strategy/SignalTypes.mqh"
#include "../Strategy/DecisionEngine.mqh"

class CExplanationEngine
  {
public:
   static string     Signal(const STradingSignal &s);
   static string     Score(const SFactorBreakdown &b, const int maxFactors = 6);
   static string     Risk(const SRiskAssessment &r);
   static string     Decision(const SDecision &d, const STradingSignal &s);
   static string     OneLine(const SDecision &d);
  };

//------------------------------------------------------------------//
string CExplanationEngine::Signal(const STradingSignal &s)
  {
   string t = s.symbol + " " + QmeSideName(s.side) + " " + QmeTfName(s.tf) +
              " id=" + IntegerToString((long)s.id);
   t += "\n  entry " + DoubleToString(s.entry, 5) +
        "  stop " + DoubleToString(s.stopLoss, 5) +
        "  target " + DoubleToString(s.takeProfit1, 5) +
        "  rr " + QmeFmt(s.rr, 2);
   t += "\n  score " + QmeFmt(s.score, 1) +
        "  confluence " + QmeFmt(s.confidence, 2) +
        "  zone " + IntegerToString((long)s.zoneId) +
        "  source " + QmeZoneSourceName(s.source);
   t += "\n  state " + QmeSignalStateName(s.state) +
        "  fingerprint " + s.fingerprint;
   return(t);
  }

//------------------------------------------------------------------//
string CExplanationEngine::Score(const SFactorBreakdown &b, const int maxFactors)
  {
   string t = "score " + QmeFmt(b.score, 1) +
              " (sum " + QmeFmt(b.sum, 2) + " / cap " + QmeFmt(b.maxSum, 2) +
              " - penalty " + QmeFmt(b.penalty, 2) + ")";
   t += " factors=" + IntegerToString(b.applied) +
        " families=" + IntegerToString(b.familiesUsed);

   int shown = 0;
   for(int i = 0; i < QME_F_COUNT && shown < maxFactors; i++)
     {
      const SFactorScore f = b.items[i];
      if(!f.available || f.contribution <= 0.0) continue;
      t += "\n    " + QmeFactorName(f.factor) +
           " raw " + QmeFmt(f.raw, 2) +
           " w " + QmeFmt(f.weight, 2) +
           " -> " + QmeFmt(f.contribution, 2);
      shown++;
     }
   return(t);
  }

//------------------------------------------------------------------//
string CExplanationEngine::Risk(const SRiskAssessment &r)
  {
   if(r.passed)
      return("risk passed: volume " + DoubleToString(r.volume, 2) +
             " risk " + QmeFmtMoney(r.riskMoney) +
             " (" + QmeFmt(r.riskPct, 2) + "% of equity)" +
             " rr " + QmeFmt(r.rr, 2) +
             " stop " + QmeFmt(r.slPoints, 0) + " pts" +
             " checks " + IntegerToString(r.checksRun));

   return("risk refused: " + QmeRejectName(r.reason) +
          " (" + r.note + ")" +
          " after " + IntegerToString(r.checksRun) + " checks");
  }

//------------------------------------------------------------------//
string CExplanationEngine::Decision(const SDecision &d, const STradingSignal &s)
  {
   string t = "DECISION " + d.symbol + " " + QmeSideName(d.side) + ": ";
   t += (d.verdict == QME_DEC_APPROVED) ? "APPROVED" :
        (d.verdict == QME_DEC_REJECTED) ? "REJECTED" : "DEFERRED";
   if(d.reason != QME_REJ_NONE) t += " (" + QmeRejectName(d.reason) + ")";
   t += "\n  " + d.note;
   t += "\n" + Signal(s);
   t += "\n" + Risk(d.risk);
   if(d.verdict == QME_DEC_APPROVED)
      t += "\n  plan: volume " + DoubleToString(d.plan.volume, 2) +
           " entry " + DoubleToString(d.plan.entry, 5) +
           " sl " + DoubleToString(d.plan.stopLoss, 5) +
           " tp " + DoubleToString(d.plan.takeProfit, 5);
   return(t);
  }

//------------------------------------------------------------------//
string CExplanationEngine::OneLine(const SDecision &d)
  {
   string t = d.symbol + " " + QmeSideName(d.side) + " " +
              ((d.verdict == QME_DEC_APPROVED) ? "OK" :
               (d.verdict == QME_DEC_REJECTED) ? "NO" : "HOLD");
   if(d.reason != QME_REJ_NONE) t += " " + QmeRejectName(d.reason);
   t += " score=" + QmeFmt(d.score, 1);
   if(d.verdict == QME_DEC_APPROVED)
      t += " vol=" + DoubleToString(d.plan.volume, 2) + " rr=" + QmeFmt(d.plan.rr, 2);
   return(t);
  }

#endif // __QME_OUT_EXPLANATION_MQH__
//+------------------------------------------------------------------+
