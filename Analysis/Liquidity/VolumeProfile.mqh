//+------------------------------------------------------------------+
//|                               Analysis/Liquidity/VolumeProfile     |
//|  Volume profile built from closed bars.                             |
//|                                                                   |
//|  Model (explicit, and honest about its assumption):                 |
//|   each bar's tick volume is spread UNIFORMLY across the price         |
//|   buckets its [low,high] range touches. This is a bar-based           |
//|   approximation of a tick profile, not a tick-level measurement.      |
//|                                                                   |
//|  Outputs: POC, value area (70% of volume, expanding from the POC),    |
//|  high-volume nodes (>= 1.5x mean bucket) and low-volume nodes        |
//|  (<= 0.5x mean bucket).                                             |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_VOLUMEPROFILE_MQH__
#define __QME_ANALYSIS_VOLUMEPROFILE_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

class CVolumeProfile
  {
public:
   //--- build a profile over the newest `bars` closed bars
   static bool       Build(CBarSeries &series, const int bars, const int buckets,
                           SVolumeProfile &out);
   //--- value-area position of a price: 0 = VAL, 1 = VAH, -1 = outside
   static double     ValueAreaPosition(const SVolumeProfile &profile, const double price);
   //--- does the price sit inside a low-volume node (fast movement zone)?
   static bool       InLowVolumeNode(const SVolumeProfile &profile, const double price);
  };

//------------------------------------------------------------------//
bool CVolumeProfile::Build(CBarSeries &series, const int bars, const int buckets,
                           SVolumeProfile &out)
  {
   out.nodeCount = 0;
   out.poc = 0.0;
   out.valueAreaHigh = 0.0;
   out.valueAreaLow = 0.0;
   out.totalVolume = 0.0;
   out.valid = false;

   if(!series.IsValid()) return(false);
   const int n = MathMin(bars, series.Count());
   if(n < 10) return(false);

   const int bucketsWanted = (buckets < 8) ? 8 : ((buckets > 63) ? 63 : buckets);
   const double hi = series.Highest(0, n);
   const double lo = series.Lowest(0, n);
   if(hi <= 0.0 || lo <= 0.0 || hi <= lo) return(false);

   const double bucketSize = (hi - lo) / bucketsWanted;
   if(bucketSize <= QME_PRICE_EPS) return(false);

   //--- initialise buckets
   long vol[];
   ArrayResize(vol, bucketsWanted);
   for(int i = 0; i < bucketsWanted; i++) vol[i] = 0;

   for(int i = 0; i < n; i++)
     {
      const double bLow = series.Low(i);
      const double bHigh = series.High(i);
      const long v = series.TickVolume(i);
      if(v <= 0 || bHigh <= 0.0) continue;

      int from = (int)MathFloor((bLow - lo) / bucketSize);
      int to   = (int)MathFloor((bHigh - lo) / bucketSize);
      from = (int)QmeClamp((double)from, 0, bucketsWanted - 1);
      to   = (int)QmeClamp((double)to,   0, bucketsWanted - 1);
      const int span = to - from + 1;
      if(span <= 0) continue;

      const long per = v / span;
      const long remainder = v - per * span;
      for(int b = from; b <= to; b++)
         vol[b] += per;
      //--- keep the rounding remainder on the closest bucket to the close
      int closest = (int)MathFloor((series.Close(i) - lo) / bucketSize);
      closest = (int)QmeClamp((double)closest, from, to);
      vol[closest] += remainder;
     }

   long total = 0;
   for(int i = 0; i < bucketsWanted; i++) total += vol[i];
   if(total <= 0) return(false);

   //--- nodes
   out.nodeCount = bucketsWanted;
   int pocIdx = 0;
   for(int i = 0; i < bucketsWanted; i++)
     {
      out.nodes[i].priceLow = lo + i * bucketSize;
      out.nodes[i].priceHigh = out.nodes[i].priceLow + bucketSize;
      out.nodes[i].mid = 0.5 * (out.nodes[i].priceLow + out.nodes[i].priceHigh);
      out.nodes[i].volume = vol[i];
      out.nodes[i].share = (double)vol[i] / (double)total;
      out.nodes[i].highNode = false;
      out.nodes[i].lowNode = false;
      if(vol[i] > vol[pocIdx]) pocIdx = i;
     }
   out.totalVolume = (double)total;
   out.poc = out.nodes[pocIdx].mid;

   const double meanShare = 1.0 / bucketsWanted;
   for(int i = 0; i < bucketsWanted; i++)
     {
      out.nodes[i].highNode = (out.nodes[i].share >= 1.5 * meanShare);
      out.nodes[i].lowNode  = (out.nodes[i].share <= 0.5 * meanShare);
     }

   //--- value area: expand from the POC until 70% of volume is covered
   double acc = out.nodes[pocIdx].share;
   int up = pocIdx;
   int down = pocIdx;
   while(acc < 0.70 && (up + 1 < bucketsWanted || down - 1 >= 0))
     {
      const double volUp   = (up + 1 < bucketsWanted) ? out.nodes[up + 1].share : -1.0;
      const double volDown = (down - 1 >= 0)          ? out.nodes[down - 1].share : -1.0;
      if(volUp >= volDown && volUp >= 0.0)
        {
         up++;
         acc += volUp;
        }
      else if(volDown >= 0.0)
        {
         down--;
         acc += volDown;
        }
      else
         break;
     }
   out.valueAreaLow = out.nodes[MathMax(0, down)].priceLow;
   out.valueAreaHigh = out.nodes[MathMin(bucketsWanted - 1, up)].priceHigh;
   out.valid = true;
   return(true);
  }

//------------------------------------------------------------------//
double CVolumeProfile::ValueAreaPosition(const SVolumeProfile &profile, const double price)
  {
   if(!profile.valid) return(-1.0);
   if(profile.valueAreaHigh <= profile.valueAreaLow) return(-1.0);
   if(price < profile.valueAreaLow || price > profile.valueAreaHigh) return(-1.0);
   return(QmeNormRange(price, profile.valueAreaLow, profile.valueAreaHigh));
  }

//------------------------------------------------------------------//
bool CVolumeProfile::InLowVolumeNode(const SVolumeProfile &profile, const double price)
  {
   if(!profile.valid) return(false);
   for(int i = 0; i < profile.nodeCount; i++)
     {
      if(price < profile.nodes[i].priceLow || price > profile.nodes[i].priceHigh) continue;
      return(profile.nodes[i].lowNode);
     }
   return(false);
  }

#endif // __QME_ANALYSIS_VOLUMEPROFILE_MQH__
//+------------------------------------------------------------------+
