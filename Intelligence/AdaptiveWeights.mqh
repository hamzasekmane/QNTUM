//+------------------------------------------------------------------+
//|                                   Intelligence/AdaptiveWeights    |
//|  Controlled factor weights.                                        |
//|                                                                   |
//|  SAFETY RULES (why this cannot drift during live trading):            |
//|   1. every weight is clamped to [0.35*default, 2.5*default];          |
//|   2. an update requires >= minSamples accumulated observations for    |
//|      that factor;                                                   |
//|   3. a single update may move a weight by at most maxStepPct;         |
//|   4. updates are only applied when allowLiveUpdates is explicitly     |
//|      enabled (default OFF); otherwise observations are recorded and   |
//|      the weights stay at their defaults for the whole session;         |
//|   5. all changes are logged with before/after values.                 |
//+------------------------------------------------------------------+
#ifndef __QME_INTEL_ADAPTIVEWEIGHTS_MQH__
#define __QME_INTEL_ADAPTIVEWEIGHTS_MQH__

#include "../Core/Types.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"
#include "../Analysis/FactorCatalog.mqh"

struct SWeightStat
  {
   int               observations;
   int               successes;
   double            current;
   double            defaultWeight;
  };

class CAdaptiveWeights
  {
private:
   double            m_weight[QME_F_COUNT];
   int               m_obs[QME_F_COUNT];
   int               m_wins[QME_F_COUNT];
   bool              m_allowLiveUpdates;
   int               m_minSamples;
   double            m_maxStepPct;
   int               m_updates;

   double            LowerBound(const ENUM_QME_FACTOR f);
   double            UpperBound(const ENUM_QME_FACTOR f);

public:
                     CAdaptiveWeights(void) { Init(false); }
   void              Init(const bool allowLiveUpdates);
   void              Reset(void);

   double            Weight(const ENUM_QME_FACTOR f);
   void              Observe(const ENUM_QME_FACTOR f, const bool success);
   //--- apply controlled updates for factors with enough evidence
   int               Update(void);
   void              GetStat(const ENUM_QME_FACTOR f, SWeightStat &out);
   int               Updates(void) { return(m_updates); }
   string            Serialize(void);
   bool              Deserialize(const string blob);
   string            Report(void);
  };

//------------------------------------------------------------------//
void CAdaptiveWeights::Init(const bool allowLiveUpdates)
  {
   m_allowLiveUpdates = allowLiveUpdates;
   m_minSamples = 30;
   m_maxStepPct = 10.0;
   m_updates = 0;
   Reset();
  }

//------------------------------------------------------------------//
void CAdaptiveWeights::Reset(void)
  {
   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      m_weight[i] = CFactorCatalog::DefaultWeight((ENUM_QME_FACTOR)i);
      m_obs[i] = 0;
      m_wins[i] = 0;
     }
  }

//------------------------------------------------------------------//
double CAdaptiveWeights::LowerBound(const ENUM_QME_FACTOR f)
  { return(CFactorCatalog::DefaultWeight(f) * 0.35); }

double CAdaptiveWeights::UpperBound(const ENUM_QME_FACTOR f)
  { return(CFactorCatalog::DefaultWeight(f) * 2.50); }

//------------------------------------------------------------------//
double CAdaptiveWeights::Weight(const ENUM_QME_FACTOR f)
  {
   const int i = (int)f;
   if(i < 0 || i >= (int)QME_F_COUNT) return(1.0);
   return(m_weight[i]);
  }

//------------------------------------------------------------------//
void CAdaptiveWeights::Observe(const ENUM_QME_FACTOR f, const bool success)
  {
   const int i = (int)f;
   if(i < 0 || i >= (int)QME_F_COUNT) return;
   m_obs[i]++;
   if(success) m_wins[i]++;
  }

//------------------------------------------------------------------//
int CAdaptiveWeights::Update(void)
  {
   if(!m_allowLiveUpdates)
      return(0);   // observations are still recorded, weights stay fixed

   int changed = 0;
   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      if(m_obs[i] < m_minSamples) continue;

      const ENUM_QME_FACTOR f = (ENUM_QME_FACTOR)i;
      const double observed = (double)m_wins[i] / (double)m_obs[i];
      //--- target: a factor that predicts well should weigh more; 0.5 is neutral
      const double target = CFactorCatalog::DefaultWeight(f) * (0.5 + observed);
      const double clampedTarget = QmeClamp(target, LowerBound(f), UpperBound(f));

      const double step = m_weight[i] * m_maxStepPct / 100.0;
      double next = QmeClamp(clampedTarget, m_weight[i] - step, m_weight[i] + step);
      next = QmeClamp(next, LowerBound(f), UpperBound(f));

      if(MathAbs(next - m_weight[i]) < 0.001) continue;
      QmeLogMsg(QME_LOG_INFO, "AdaptiveWeights",
                QmeFactorName(f) + " weight " + QmeFmt(m_weight[i], 3) + " -> " +
                QmeFmt(next, 3) + " (n=" + IntegerToString(m_obs[i]) +
                " hit=" + QmeFmt(100.0 * observed, 1) + "%)");
      m_weight[i] = next;
      changed++;
      m_updates++;
     }
   return(changed);
  }

//------------------------------------------------------------------//
void CAdaptiveWeights::GetStat(const ENUM_QME_FACTOR f, SWeightStat &out)
  {
   const int i = (int)f;
   out.observations = (i >= 0 && i < (int)QME_F_COUNT) ? m_obs[i] : 0;
   out.successes = (i >= 0 && i < (int)QME_F_COUNT) ? m_wins[i] : 0;
   out.current = (i >= 0 && i < (int)QME_F_COUNT) ? m_weight[i] : 1.0;
   out.defaultWeight = (i >= 0 && i < (int)QME_F_COUNT) ? CFactorCatalog::DefaultWeight(f) : 1.0;
  }

//------------------------------------------------------------------//
string CAdaptiveWeights::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < (int)QME_F_COUNT; i++)
      s += "weight;" + IntegerToString(i) + ";" + DoubleToString(m_weight[i], 4) + ";" +
           IntegerToString(m_obs[i]) + ";" + IntegerToString(m_wins[i]) + "\n";
   return(s);
  }

//------------------------------------------------------------------//
bool CAdaptiveWeights::Deserialize(const string blob)
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
      if(StringSplit(lines[i], ';', f) < 5) continue;
      if(f[0] != "weight") continue;
      const int idx = (int)StringToInteger(f[1]);
      if(idx < 0 || idx >= (int)QME_F_COUNT) continue;
      m_weight[idx] = QmeClamp(StringToDouble(f[2]), LowerBound((ENUM_QME_FACTOR)idx),
                               UpperBound((ENUM_QME_FACTOR)idx));
      m_obs[idx] = (int)StringToInteger(f[3]);
      m_wins[idx] = (int)StringToInteger(f[4]);
      loaded++;
     }
   return(loaded > 0);
  }

//------------------------------------------------------------------//
string CAdaptiveWeights::Report(void)
  {
   string s = "";
   for(int i = 0; i < (int)QME_F_COUNT; i++)
     {
      if(m_obs[i] <= 0) continue;
      s += QmeFactorName((ENUM_QME_FACTOR)i) + "=" + QmeFmt(m_weight[i], 2) +
           "(" + IntegerToString(m_wins[i]) + "/" + IntegerToString(m_obs[i]) + ") ";
     }
   return(s);
  }

#endif // __QME_INTEL_ADAPTIVEWEIGHTS_MQH__
//+------------------------------------------------------------------+
