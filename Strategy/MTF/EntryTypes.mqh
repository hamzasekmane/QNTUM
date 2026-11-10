//+------------------------------------------------------------------+
//|                                     Strategy/MTF/EntryTypes       |
//|  Entry specification: the exact prices an order would use.           |
//|                                                                   |
//|  A specification is only valid when:                                |
//|   * the stop is on the correct side of the entry;                    |
//|   * the target is on the correct side of the entry;                  |
//|   * the stop distance respects the broker's stops level;              |
//|   * all prices are normalised to the symbol's digits.                 |
//+------------------------------------------------------------------+
#ifndef __QME_STRATEGY_ENTRYTYPES_MQH__
#define __QME_STRATEGY_ENTRYTYPES_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Account/SymbolSpecifications.mqh"

struct SEntrySpec
  {
   ENUM_QME_ENTRY_TYPE type;
   ENUM_QME_SIDE     side;
   double            entry;
   double            stop;
   double            target1;
   double            target2;
   double            stopDistance;
   double            rr;
   double            zoneUpper;
   double            zoneLower;
   ulong             zoneId;
   bool              valid;
   ENUM_QME_REJECT   reason;
   string            note;
  };

void QmeEntrySpecClear(SEntrySpec &e)
  {
   e.type = QME_ENTRY_MARKET;
   e.side = QME_SIDE_NONE;
   e.entry = 0.0;
   e.stop = 0.0;
   e.target1 = 0.0;
   e.target2 = 0.0;
   e.stopDistance = 0.0;
   e.rr = 0.0;
   e.zoneUpper = 0.0;
   e.zoneLower = 0.0;
   e.zoneId = 0;
   e.valid = false;
   e.reason = QME_REJ_NONE;
   e.note = "";
  }

class CEntryTypes
  {
public:
   //--- full validation against the symbol's real constraints
   static bool       Validate(SEntrySpec &e, const SSymbolSpec &spec,
                              const double minStopDistancePrice, string &why);
   //--- recompute RR from the current prices
   static double     RecomputeRR(SEntrySpec &e);
   static string     Describe(const SEntrySpec &e);
  };

//------------------------------------------------------------------//
bool CEntryTypes::Validate(SEntrySpec &e, const SSymbolSpec &spec,
                           const double minStopDistancePrice, string &why)
  {
   why = "";
   e.reason = QME_REJ_NONE;

   if(e.side == QME_SIDE_NONE) { e.reason = QME_REJ_INTERNAL; why = "no side"; return(false); }

   //--- normalise to the symbol's digits before any comparison
   e.entry  = CSymbolSpecifications::NormalizePrice(spec, e.entry);
   e.stop   = CSymbolSpecifications::NormalizePrice(spec, e.stop);
   e.target1 = CSymbolSpecifications::NormalizePrice(spec, e.target1);
   e.target2 = CSymbolSpecifications::NormalizePrice(spec, e.target2);

   if(e.entry <= 0.0) { e.reason = QME_REJ_INTERNAL; why = "entry price invalid"; return(false); }
   if(!QmeStopIsValid(e.side, e.entry, e.stop))
     {
      e.reason = QME_REJ_SL_INVALID;
      why = "stop " + DoubleToString(e.stop, spec.digits) + " is on the wrong side of entry " +
            DoubleToString(e.entry, spec.digits);
      return(false);
     }
   if(!QmeTargetIsValid(e.side, e.entry, e.target1))
     {
      e.reason = QME_REJ_TP_INVALID;
      why = "target " + DoubleToString(e.target1, spec.digits) + " is on the wrong side of entry";
      return(false);
     }

   e.stopDistance = MathAbs(e.entry - e.stop);
   if(e.stopDistance < minStopDistancePrice - QME_PRICE_EPS)
     {
      e.reason = QME_REJ_SL_INVALID;
      why = "stop distance " + DoubleToString(e.stopDistance, spec.digits) +
            " below minimum " + DoubleToString(minStopDistancePrice, spec.digits);
      return(false);
     }

   e.rr = QmeComputeRR(e.side, e.entry, e.stop, e.target1);
   if(e.rr <= 0.0)
     {
      e.reason = QME_REJ_RR;
      why = "reward:risk is not positive";
      return(false);
     }

   e.valid = true;
   return(true);
  }

//------------------------------------------------------------------//
double CEntryTypes::RecomputeRR(SEntrySpec &e)
  {
   e.rr = QmeComputeRR(e.side, e.entry, e.stop, e.target1);
   return(e.rr);
  }

string CEntryTypes::Describe(const SEntrySpec &e)
  {
   return(QmeSideName(e.side) + " " + QmeEntryTypeName(e.type) +
          " entry=" + DoubleToString(e.entry, 5) +
          " sl=" + DoubleToString(e.stop, 5) +
          " tp=" + DoubleToString(e.target1, 5) +
          " rr=" + QmeFmt(e.rr, 2) +
          (e.valid ? "" : " INVALID:" + QmeRejectName(e.reason) + " " + e.note));
  }

#endif // __QME_STRATEGY_ENTRYTYPES_MQH__
//+------------------------------------------------------------------+
