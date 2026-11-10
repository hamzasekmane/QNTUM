//+------------------------------------------------------------------+
//|                               Intelligence/ConfidenceCalibration  |
//|  Maps a heuristic score band to a REALISED outcome rate.             |
//|                                                                   |
//|  This is the only place where a score may become a probability, and    |
//|  only when the band already contains `minSamples` realised outcomes.   |
//|  With insufficient data the calibration returns false and no            |
//|  probability is reported anywhere in the UI.                           |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_CALIBRATION_MQH__
#define __QME_INTEL_CALIBRATION_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"

#define QME_CALIB_BUCKETS 10          // 0-10, 10-20, ... 90-100

class CConfidenceCalibration
  {
private:
   int               m_samples[QME_CALIB_BUCKETS];
   int               m_wins[QME_CALIB_BUCKETS];
   int               m_minSamples;
   int               BucketOf(const double score);

public:
                     CConfidenceCalibration(void) { Init(20); }
   void              Init(const int minSamples);
   void              Reset(void);
   void              Add(const double score, const bool win);
   bool              Calibrate(const double score, double &winRate, int &samples);
   int               Total(void);
   string            Report(void);
   string            Serialize(void);
   bool              Deserialize(const string blob);
  };

//------------------------------------------------------------------//
void CConfidenceCalibration::Init(const int minSamples)
  {
   m_minSamples = (minSamples < 5) ? 5 : minSamples;
   Reset();
  }

void CConfidenceCalibration::Reset(void)
  {
   for(int i = 0; i < QME_CALIB_BUCKETS; i++)
     {
      m_samples[i] = 0;
      m_wins[i] = 0;
     }
  }

int CConfidenceCalibration::BucketOf(const double score)
  {
   int b = (int)(QmeClamp(score, 0.0, 99.999) / 10.0);
   if(b < 0) b = 0;
   if(b >= QME_CALIB_BUCKETS) b = QME_CALIB_BUCKETS - 1;
   return(b);
  }

//------------------------------------------------------------------//
void CConfidenceCalibration::Add(const double score, const bool win)
  {
   const int b = BucketOf(score);
   m_samples[b]++;
   if(win) m_wins[b]++;
  }

//------------------------------------------------------------------//
bool CConfidenceCalibration::Calibrate(const double score, double &winRate, int &samples)
  {
   const int b = BucketOf(score);
   samples = m_samples[b];
   winRate = 0.0;
   if(samples < m_minSamples) return(false);
   winRate = (double)m_wins[b] / (double)samples;
   return(true);
  }

//------------------------------------------------------------------//
int CConfidenceCalibration::Total(void)
  {
   int n = 0;
   for(int i = 0; i < QME_CALIB_BUCKETS; i++) n += m_samples[i];
   return(n);
  }

//------------------------------------------------------------------//
string CConfidenceCalibration::Report(void)
  {
   string s = "";
   for(int i = 0; i < QME_CALIB_BUCKETS; i++)
     {
      if(m_samples[i] <= 0) continue;
      s += IntegerToString(i * 10) + "-" + IntegerToString((i + 1) * 10) + ":" +
           IntegerToString(m_wins[i]) + "/" + IntegerToString(m_samples[i]) + " ";
     }
   return(s);
  }

//------------------------------------------------------------------//
string CConfidenceCalibration::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < QME_CALIB_BUCKETS; i++)
      s += "calib;" + IntegerToString(i) + ";" + IntegerToString(m_samples[i]) + ";" +
           IntegerToString(m_wins[i]) + "\n";
   return(s);
  }

//------------------------------------------------------------------//
bool CConfidenceCalibration::Deserialize(const string blob)
  {
   if(StringLen(blob) == 0) return(false);
   Reset();
   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n; i++)
     {
      if(StringLen(lines[i]) == 0) continue;
      string f[];
      if(StringSplit(lines[i], ';', f) < 4) continue;
      if(f[0] != "calib") continue;
      const int b = (int)StringToInteger(f[1]);
      if(b < 0 || b >= QME_CALIB_BUCKETS) continue;
      m_samples[b] = (int)StringToInteger(f[2]);
      m_wins[b] = (int)StringToInteger(f[3]);
      loaded++;
     }
   return(loaded > 0);
  }

#endif // __QME_INTEL_CALIBRATION_MQH__
//+------------------------------------------------------------------+
