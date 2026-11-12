//+------------------------------------------------------------------+
//| Offline microbenchmark: linear reference vs QME fingerprint index |
//| No market data, account access, or trade operations are performed. |
//+------------------------------------------------------------------+
#property strict
#include "../../QME.mqh"

#define QME_BENCH_CAPACITY 512
#define QME_BENCH_ROUNDS   50

class CLinearFingerprintReference
  {
private:
   string   m_keys[QME_BENCH_CAPACITY];
   datetime m_times[QME_BENCH_CAPACITY];
   int      m_count;
public:
   CLinearFingerprintReference(void) { m_count = 0; }
   bool Add(const string key, const datetime now)
     {
      if(m_count >= QME_BENCH_CAPACITY) return(false);
      m_keys[m_count] = key;
      m_times[m_count] = now;
      m_count++;
      return(true);
     }
   bool IsDuplicate(const string key, const int cooldownSeconds, const datetime now)
     {
      if(StringLen(key) == 0) return(false);
      int found = -1;
      for(int i = 0; i < m_count; i++)
         if(m_keys[i] == key) { found = i; break; }
      if(found < 0) return(false);
      if(cooldownSeconds <= 0 || m_times[found] <= 0) return(true);
      return((now - m_times[found]) < (datetime)cooldownSeconds);
     }
  };

int OnInit(void)
  {
   CSignalDeduplicator indexed;
   CLinearFingerprintReference linear;
   bool setup = true;
   for(int i = 0; i < QME_BENCH_CAPACITY; i++)
     {
      const string key = "benchmark-fingerprint-" + IntegerToString(i);
      if(!indexed.Register(key, (ulong)(i + 1), 1000) || !linear.Add(key, 1000))
        { setup = false; break; }
     }
   if(!setup)
     {
      Print("BENCH_ABORT setup failed");
      return(INIT_FAILED);
     }

   const int queries = QME_BENCH_CAPACITY * 2 * QME_BENCH_ROUNDS;
   int mismatches = 0;
   //--- establish result equivalence outside timed regions
   for(int i = 0; i < QME_BENCH_CAPACITY; i++)
     {
      const string key = "benchmark-fingerprint-" + IntegerToString(i);
      const string miss = "missing-fingerprint-" + IntegerToString(i);
      if(indexed.IsDuplicate(key, 3600, 1001) != linear.IsDuplicate(key, 3600, 1001)) mismatches++;
      if(indexed.IsDuplicate(miss, 3600, 1001) != linear.IsDuplicate(miss, 3600, 1001)) mismatches++;
     }
   ulong start = GetMicrosecondCount();
   for(int r = 0; r < QME_BENCH_ROUNDS; r++)
      for(int i = 0; i < QME_BENCH_CAPACITY; i++)
        {
         const string key = "benchmark-fingerprint-" + IntegerToString(i);
         const string miss = "missing-fingerprint-" + IntegerToString(i);
         if(!indexed.IsDuplicate(key, 3600, 1001)) mismatches++;
         if(indexed.IsDuplicate(miss, 3600, 1001)) mismatches++;
        }
   const ulong indexedUs = GetMicrosecondCount() - start;

   start = GetMicrosecondCount();
   for(int r = 0; r < QME_BENCH_ROUNDS; r++)
      for(int i = 0; i < QME_BENCH_CAPACITY; i++)
        {
         const string key = "benchmark-fingerprint-" + IntegerToString(i);
         const string miss = "missing-fingerprint-" + IntegerToString(i);
         if(!linear.IsDuplicate(key, 3600, 1001)) mismatches++;
         if(linear.IsDuplicate(miss, 3600, 1001)) mismatches++;
        }
   const ulong linearUs = GetMicrosecondCount() - start;

   Print("BENCH_SIGNAL_HASH capacity=", QME_BENCH_CAPACITY,
         " rounds=", QME_BENCH_ROUNDS,
         " queries_per_impl=", queries,
         " indexed_total_us=", indexedUs,
         " linear_total_us=", linearUs,
         " indexed_us_per_query=", DoubleToString((double)indexedUs / queries, 6),
         " linear_us_per_query=", DoubleToString((double)linearUs / queries, 6),
         " output_mismatches=", mismatches,
         " NOTE=single-run microbenchmark; repeat/warmup required");
   return(mismatches == 0 ? INIT_SUCCEEDED : INIT_FAILED);
  }

void OnTick(void) {}
void OnDeinit(const int reason) {}
