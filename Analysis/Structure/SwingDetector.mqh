//+------------------------------------------------------------------+
//|                                 Analysis/Structure/SwingDetector  |
//|  Pivot (swing) detection on CLOSED bars only.                       |
//|                                                                   |
//|  DEFINITION (explicit and testable):                              |
//|   bar i is a swing high when                                          |
//|     high[i] > high[i-k] for k=1..left  AND                            |
//|     high[i] >= high[i+k] for k=1..right                               |
//|   (mirror rule for swing lows with the low series).                  |
//|                                                                   |
//|  Because `right` newer bars must already exist, a swing is only      |
//|  reported once it is CONFIRMED — confirmed structure never repaints. |
//+------------------------------------------------------------------+
#ifndef __QME_ANALYSIS_SWINGDETECTOR_MQH__
#define __QME_ANALYSIS_SWINGDETECTOR_MQH__

#include "../../Core/Types.mqh"
#include "../../Core/Utils.mqh"
#include "../../Data/BarSeries.mqh"

class CSwingDetector
  {
public:
   //--- out[] = confirmed swings, newest first. Returns the number found.
   static int        Detect(CBarSeries &series, const int scanBars,
                            const int left, const int right,
                            SStructurePoint &out[]);

   //--- prominence of a pivot inside its window, 0..1
   static double     Strength(CBarSeries &series, const int index,
                              const int left, const int right, const bool isHigh);
  };

//------------------------------------------------------------------//
int CSwingDetector::Detect(CBarSeries &series, const int scanBars,
                           const int left, const int right,
                           SStructurePoint &out[])
  {
   ArrayResize(out, 0);
   if(!series.IsValid()) return(0);
   if(left < 1 || right < 1) return(0);

   const int count = series.Count();
   const int limit = MathMin(scanBars, count - right);
   if(limit <= left) return(0);

   int found = 0;
   for(int i = right; i < limit; i++)   // i is the candidate index (0 = newest)
     {
      const double h = series.High(i);
      const double l = series.Low(i);
      if(h <= 0.0 || l <= 0.0) continue;

      bool isHigh = true;
      bool isLow = true;
      for(int k = 1; k <= left && (isHigh || isLow); k++)
        {
         if(i - k < 0) { isHigh = false; isLow = false; break; }
         if(series.High(i - k) >= h) isHigh = false;
         if(series.Low(i - k)  <= l) isLow = false;
        }
      for(int k = 1; k <= right && (isHigh || isLow); k++)
        {
         if(i + k >= count) { isHigh = false; isLow = false; break; }
         if(series.High(i + k) > h) isHigh = false;
         if(series.Low(i + k)  < l) isLow = false;
        }

      if(!isHigh && !isLow) continue;

      SStructurePoint p;
      p.time = series.TimeAt(i);
      p.price = isHigh ? h : l;
      p.isHigh = isHigh;
      p.barIndex = i;
      p.strength = Strength(series, i, left, right, isHigh);

      if(found >= QME_MAX_SWINGS) break;
      const int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = p;
      found++;
     }
   return(found);
  }

//------------------------------------------------------------------//
double CSwingDetector::Strength(CBarSeries &series, const int index,
                                const int left, const int right, const bool isHigh)
  {
   const int count = series.Count();
   const int from = MathMax(0, index - left);
   const int to = MathMin(count - 1, index + right);
   double other = isHigh ? -DBL_MAX : DBL_MAX;
   for(int i = from; i <= to; i++)
     {
      if(i == index) continue;
      if(isHigh) { const double v = series.High(i); if(v > other) other = v; }
      else       { const double v = series.Low(i);  if(v < other) other = v; }
     }
   if(other == -DBL_MAX || other == DBL_MAX) return(0.5);

   const double pivot = isHigh ? series.High(index) : series.Low(index);
   const double range = series.Highest(from, to - from + 1) - series.Lowest(from, to - from + 1);
   if(range <= QME_EPSILON) return(0.5);

   const double prominence = isHigh ? (pivot - other) / range : (other - pivot) / range;
   return(QmeClamp(prominence, 0.0, 1.0));
  }

#endif // __QME_ANALYSIS_SWINGDETECTOR_MQH__
//+------------------------------------------------------------------+
