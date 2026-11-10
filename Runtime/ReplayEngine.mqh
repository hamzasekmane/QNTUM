//+------------------------------------------------------------------+
//|                                         Runtime/ReplayEngine      |
//|  Records every decision and audits it for invariant violations.       |
//|                                                                   |
//|  HONEST SCOPE: this is not a market-data replay. It replays the        |
//|  *decisions* the engine actually made and checks the rules that must  |
//|  never be broken, which is what the regression tests need:             |
//|    * an approval always has a reason of NONE, rr >= minRR,            |
//|      score >= minScore, a valid fingerprint and an acceptable risk;   |
//|    * a refusal always states a reason;                                |
//|    * no fingerprint is ever approved twice.                          |
//+------------------------------------------------------------------+
#ifndef __QME_RUNTIME_REPLAY_MQH__
#define __QME_RUNTIME_REPLAY_MQH__

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utils.mqh"
#include "../Core/Logger.mqh"

struct SReplayFrame
  {
   long              cycle;
   datetime          time;
   string            symbol;
   ENUM_QME_SIDE     side;
   double            score;
   double            rr;
   double            riskPct;
   bool              approved;
   ENUM_QME_REJECT   reason;
   string            fingerprint;
  };

struct SReplayStats
  {
   int               frames;
   int               approvals;
   int               refusals;
   int               violations;
   int               duplicateApprovals;
   string            note;
  };

void QmeReplayFrameClear(SReplayFrame &f)
  {
   f.cycle = 0; f.time = 0; f.symbol = ""; f.side = QME_SIDE_NONE;
   f.score = 0.0; f.rr = 0.0; f.riskPct = 0.0;
   f.approved = false; f.reason = QME_REJ_NONE; f.fingerprint = "";
  }

class CReplayEngine
  {
private:
   SReplayFrame      m_frames[];
   int               m_capacity;
   int               m_count;
   long              m_dropped;

public:
                     CReplayEngine(void) { m_capacity = 512; m_count = 0; m_dropped = 0; }
   void              Init(const int capacity = 512);
   void              Reset(void);

   void              Record(const SReplayFrame &f);
   int               Count(void) { return(m_count); }
   bool              At(const int i, SReplayFrame &out);
   long              Dropped(void) { return(m_dropped); }

   SReplayStats      Audit(const CConfig &cfg);
   string            Serialize(void);
   bool              Deserialize(const string blob);
   string            Describe(void);
  };

//------------------------------------------------------------------//
void CReplayEngine::Init(const int capacity)
  {
   m_capacity = MathMax(16, capacity);
   Reset();
  }

void CReplayEngine::Reset(void)
  {
   ArrayResize(m_frames, 0);
   m_count = 0;
   m_dropped = 0;
  }

//------------------------------------------------------------------//
void CReplayEngine::Record(const SReplayFrame &f)
  {
   if(m_count >= m_capacity)
     {
      //--- keep the newest frames: shift left by one
      const int n = ArraySize(m_frames);
      for(int i = 0; i < n - 1; i++) m_frames[i] = m_frames[i + 1];
      m_frames[n - 1] = f;
      m_dropped++;
      return;
     }
   ArrayResize(m_frames, m_count + 1);
   m_frames[m_count] = f;
   m_count++;
  }

bool CReplayEngine::At(const int i, SReplayFrame &out)
  {
   if(i < 0 || i >= m_count) return(false);
   out = m_frames[i];
   return(true);
  }

//------------------------------------------------------------------//
SReplayStats CReplayEngine::Audit(const CConfig &cfg)
  {
   SReplayStats st;
   st.frames = m_count;
   st.approvals = 0;
   st.refusals = 0;
   st.violations = 0;
   st.duplicateApprovals = 0;
   st.note = "";

   string approvedFp[];
   const int cap = MathMax(m_count, 1);
   ArrayResize(approvedFp, cap);
   int approvedCount = 0;

   for(int i = 0; i < m_count; i++)
     {
      const SReplayFrame f = m_frames[i];
      if(f.approved)
        {
         st.approvals++;
         bool bad = false;
         string why = "";
         if(f.reason != QME_REJ_NONE) { bad = true; why = "approved with a reject reason"; }
         else if(f.rr < cfg.In.minRR) { bad = true; why = "rr below minimum"; }
         else if(f.score < cfg.In.minScore) { bad = true; why = "score below minimum"; }
         else if(StringLen(f.fingerprint) == 0) { bad = true; why = "approved without a fingerprint"; }
         else if(f.riskPct > cfg.In.riskPerTradePct + 1e-9) { bad = true; why = "risk above budget"; }

         if(bad)
           {
            st.violations++;
            st.note += "[" + IntegerToString((int)f.cycle) + " " + f.symbol + ": " + why + "] ";
            QmeLogMsg(QME_LOG_ERROR, "Replay", IntegerToString((int)f.cycle) + " " +
                      f.symbol + " violation: " + why);
           }

         for(int k = 0; k < approvedCount; k++)
           {
            if(approvedFp[k] != f.fingerprint) continue;
            st.duplicateApprovals++;
            st.violations++;
            st.note += "[" + IntegerToString((int)f.cycle) + " " + f.symbol +
                       ": duplicate approval] ";
            break;
           }
         if(approvedCount < cap)
           {
            approvedFp[approvedCount] = f.fingerprint;
            approvedCount++;
           }
        }
      else
        {
         st.refusals++;
         if(f.reason == QME_REJ_NONE)
           {
            st.violations++;
            st.note += "[" + IntegerToString((int)f.cycle) + " " + f.symbol +
                       ": refusal without a reason] ";
           }
        }
     }

   if(StringLen(st.note) == 0) st.note = "no violations";
   return(st);
  }

//------------------------------------------------------------------//
string CReplayEngine::Serialize(void)
  {
   string s = "";
   for(int i = 0; i < m_count; i++)
     {
      const SReplayFrame f = m_frames[i];
      s += "rep|" + IntegerToString(f.cycle) + "|" + IntegerToString((long)f.time) + "|" +
           f.symbol + "|" + QmeSideName(f.side) + "|" +
           DoubleToString(f.score, 2) + "|" + DoubleToString(f.rr, 2) + "|" +
           DoubleToString(f.riskPct, 3) + "|" + (f.approved ? "1" : "0") + "|" +
           IntegerToString((int)f.reason) + "|" + f.fingerprint + "\n";
     }
   return(s);
  }

//------------------------------------------------------------------//
bool CReplayEngine::Deserialize(const string blob)
  {
   Reset();
   if(StringLen(blob) == 0) return(false);
   string lines[];
   const int n = StringSplit(blob, '\n', lines);
   int loaded = 0;
   for(int i = 0; i < n; i++)
     {
      string f[];
      if(StringSplit(lines[i], '|', f) < 11) continue;
      if(f[0] != "rep") continue;
      SReplayFrame fr;
      QmeReplayFrameClear(fr);
      fr.cycle = StringToInteger(f[1]);
      fr.time = (datetime)StringToInteger(f[2]);
      fr.symbol = f[3];
      fr.side = (f[4] == "BUY") ? QME_SIDE_BUY : (f[4] == "SELL" ? QME_SIDE_SELL : QME_SIDE_NONE);
      fr.score = StringToDouble(f[5]);
      fr.rr = StringToDouble(f[6]);
      fr.riskPct = StringToDouble(f[7]);
      fr.approved = (f[8] == "1");
      fr.reason = (ENUM_QME_REJECT)StringToInteger(f[9]);
      fr.fingerprint = f[10];
      Record(fr);
      loaded++;
     }
   return(loaded > 0);
  }

//------------------------------------------------------------------//
string CReplayEngine::Describe(void)
  {
   return("replay frames=" + IntegerToString(m_count) +
          " dropped=" + IntegerToString((int)m_dropped));
  }

#endif // __QME_RUNTIME_REPLAY_MQH__
//+------------------------------------------------------------------+
