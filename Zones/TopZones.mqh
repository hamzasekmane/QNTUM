//+------------------------------------------------------------------+
//|                                               Zones/TopZones      |
//|  Selects the best-ranked ACTIVE zones for a symbol, per side.        |
//|  Used by the strategy layer and the dashboard.                      |
//+------------------------------------------------------------------+
#ifndef __QME_ZONES_TOPZONES_MQH__
#define __QME_ZONES_TOPZONES_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "ZoneBoard.mqh"

struct SRankedZone
  {
   STradingZone      zone;
   double            score;
   double            distanceAtr;
  };

class CTopZones
  {
public:
   //--- top N active zones of one side, ranked descending
   static int        Select(CZoneBoard &board, const ENUM_QME_SIDE side,
                            const double price, const double atr, const datetime now,
                            const int maxCount, SRankedZone &out[]);
   //--- best score among active zones for a side (0 when none)
   static double     BestScore(CZoneBoard &board, const ENUM_QME_SIDE side,
                               const double price, const double atr, const datetime now);
  };

//------------------------------------------------------------------//
int CTopZones::Select(CZoneBoard &board, const ENUM_QME_SIDE side,
                      const double price, const double atr, const datetime now,
                      const int maxCount, SRankedZone &out[])
  {
   ArrayResize(out, 0);
   if(maxCount <= 0 || atr <= QME_EPSILON) return(0);

   const int total = board.Count();
   for(int i = 0; i < total; i++)
     {
      STradingZone z;
      if(!board.At(i, z)) continue;
      if(z.side != side) continue;
      if(!QmeZoneIsActive(z, now)) continue;

      SRankedZone r;
      r.zone = z;
      r.score = CZoneRanking::Score(z, price, atr, now);
      r.distanceAtr = CZoneValidator::DistanceAtr(z, price, atr);

      //--- keep the array sorted descending by score (small N)
      const int n = ArraySize(out);
      int pos = n;
      for(int k = 0; k < n; k++)
        {
         if(r.score > out[k].score) { pos = k; break; }
        }
      ArrayResize(out, n + 1);
      for(int k = n; k > pos; k--) out[k] = out[k - 1];
      out[pos] = r;
      if(ArraySize(out) > maxCount) ArrayResize(out, maxCount);
     }
   return(ArraySize(out));
  }

//------------------------------------------------------------------//
double CTopZones::BestScore(CZoneBoard &board, const ENUM_QME_SIDE side,
                            const double price, const double atr, const datetime now)
  {
   SRankedZone best[];
   if(Select(board, side, price, atr, now, 1, best) <= 0) return(0.0);
   return(best[0].score);
  }

#endif // __QME_ZONES_TOPZONES_MQH__
//+------------------------------------------------------------------+
