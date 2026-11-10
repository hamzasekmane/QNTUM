//+------------------------------------------------------------------+
//|                                      Analysis/Liquidity/PocEngine |
//|  Point-of-control and volume-node navigation helpers.               |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_POCENGINE_MQH__
#define __QME_ANALYSIS_POCENGINE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "VolumeProfile.mqh"

class CPocEngine
  {
public:
   //--- nearest high-volume node above / below a price; false when none
   static bool       NearestHighNode(const SVolumeProfile &p, const double price,
                                     const bool above, double &level);
   //--- nearest LOW-volume node (fast-travel gap)
   static bool       NearestLowNode(const SVolumeProfile &p, const double price,
                                    const bool above, double &level);
   //--- distance from the POC in ATR units (0 when ATR is invalid)
   static double     DistanceToPoc(const SVolumeProfile &p, const double price, const double atr);
   //--- is the price accepted (inside the value area)?
   static bool       Accepted(const SVolumeProfile &p, const double price);
  };

//------------------------------------------------------------------//
bool CPocEngine::NearestHighNode(const SVolumeProfile &p, const double price,
                                 const bool above, double &level)
  {
   level = 0.0;
   if(!p.valid) return(false);
   double best = 0.0;
   bool found = false;
   for(int i = 0; i < p.nodeCount; i++)
     {
      if(!p.nodes[i].highNode) continue;
      const double mid = p.nodes[i].mid;
      if(above)
        {
         if(mid <= price + QME_PRICE_EPS) continue;
         if(!found || mid < best) { best = mid; found = true; }
        }
      else
        {
         if(mid >= price - QME_PRICE_EPS) continue;
         if(!found || mid > best) { best = mid; found = true; }
        }
     }
   level = best;
   return(found);
  }

//------------------------------------------------------------------//
bool CPocEngine::NearestLowNode(const SVolumeProfile &p, const double price,
                                const bool above, double &level)
  {
   level = 0.0;
   if(!p.valid) return(false);
   double best = 0.0;
   bool found = false;
   for(int i = 0; i < p.nodeCount; i++)
     {
      if(!p.nodes[i].lowNode) continue;
      const double mid = p.nodes[i].mid;
      if(above)
        {
         if(mid <= price + QME_PRICE_EPS) continue;
         if(!found || mid < best) { best = mid; found = true; }
        }
      else
        {
         if(mid >= price - QME_PRICE_EPS) continue;
         if(!found || mid > best) { best = mid; found = true; }
        }
     }
   level = best;
   return(found);
  }

//------------------------------------------------------------------//
double CPocEngine::DistanceToPoc(const SVolumeProfile &p, const double price, const double atr)
  {
   if(!p.valid) return(0.0);
   if(atr <= QME_EPSILON) return(0.0);
   return(MathAbs(price - p.poc) / atr);
  }

//------------------------------------------------------------------//
bool CPocEngine::Accepted(const SVolumeProfile &p, const double price)
  {
   if(!p.valid) return(false);
   return(price >= p.valueAreaLow && price <= p.valueAreaHigh);
  }

#endif // __QME_ANALYSIS_POCENGINE_MQH__
//+------------------------------------------------------------------+
