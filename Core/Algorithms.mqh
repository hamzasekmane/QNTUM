//+------------------------------------------------------------------+
//| Core/Algorithms: bounded deterministic primitives for QME         |
//+------------------------------------------------------------------+
#ifndef __QME_CORE_ALGORITHMS_MQH__
#define __QME_CORE_ALGORITHMS_MQH__

#define QME_ALGO_MAX_STREAM_VALUES 65536
#define QME_ALGO_MAX_SWEEP_INTERVALS 32768
#include "Types.mqh"
#include "Utils.mqh"

struct SQmeSweepEvent
  {
   double position;
   int    delta;
  };

class CQmeAlgorithms
  {
public:
   // Bars are newest-first (strictly descending timestamps). Returns the exact
   // closed-bar shift; never returns an insertion point or approximate match.
   static bool FindBarTimeDescending(const SCandle &bars[], const int count,
                                     const datetime target, int &shift);
   // Numerically stable online population/sample statistics (Welford).
   static bool WelfordPush(const double value, long &count, double &mean, double &m2);
   static bool WelfordVariance(const long count, const double m2,
                               const bool sample, double &variance);
   static bool Quickselect(double &values[], const int count, const int k, double &selected);
   static bool StableMergeSort(double &values[], const int count);
   static bool BuildPrefixSum(const double &values[], const int count, double &prefix[]);
   static bool PrefixRangeSum(const double &prefix[], const int count,
                              const int begin, const int end, double &sum);
   static bool EwmaPush(const double value, const double alpha, bool &initialized,
                        double &state);
   static bool WilderPush(const double value, const int period, int &count,
                          double &seedSum, double &state, bool &ready);
   static bool CusumPush(const double observation, const double baseline,
                         const double allowance, const double threshold,
                         double &positive, double &negative, bool &change);
   static int IntersectSorted(const double &left[], const int leftCount,
                              const double &right[], const int rightCount,
                              double &out[]);
   static bool TopologicalSort(const int &adjacency[], const int nodes, int &order[]);
   static bool KWayMerge(const double &streams[], const int &offsets[],
                         const int &lengths[], const int streamCount, double &merged[]);
   static bool SweepMaxOverlap(const double &lower[], const double &upper[],
                               const int count, int &maximum);
  };

class CQmeSlidingWindow
  {
private:
   double m_values[128];
   int    m_capacity, m_count, m_next;
   double m_sum;
public:
   CQmeSlidingWindow(void) { Init(128); }
   void Init(const int capacity);
   void Clear(void) { m_count=0; m_next=0; m_sum=0.0; }
   bool Push(const double value);
   int Count(void) { return(m_count); }
   double Mean(const double fallback=0.0) { return(m_count>0 ? m_sum/m_count : fallback); }
  };

class CQmeMonotonicDeque
  {
private:
   double m_values[512];
   int    m_indices[512];
   int    m_capacity, m_head, m_count, m_lastIndex;
   bool   m_maximum;
public:
   CQmeMonotonicDeque(void) { Init(512, true); }
   void Init(const int capacity, const bool maximum);
   void Clear(void) { m_head=0; m_count=0; m_lastIndex=-1; }
   bool Push(const int index, const double value);
   void ExpireBefore(const int firstValidIndex);
   bool Front(int &index, double &value);
   int Count(void) { return(m_count); }
  };

class CQmeIntervalTree
  {
private:
   double m_lower[512], m_upper[512], m_maxUpper[512];
   int    m_payload[512], m_left[512], m_right[512];
   int    m_count, m_root;
   int BuildRange(const int first, const int last);
   bool QueryNode(const int node, const double lower, const double upper, int &out[]);
public:
   CQmeIntervalTree(void) { Clear(); }
   void Clear(void) { m_count=0; m_root=-1; }
   bool Build(const double &lower[], const double &upper[], const int &payload[], const int count);
   int Query(const double lower, const double upper, int &out[]);
   int Count(void) { return(m_count); }
  };

class CQmeLRUCache
  {
private:
   string m_keys[128];
   double m_values[128];
   long   m_age[128], m_tmpAge[128];
   int    m_capacity, m_count;
   long   m_clock;
   void NormalizeClock(void);
   void Touch(const int slot);
public:
   CQmeLRUCache(void) { Init(128); }
   void Init(const int capacity);
   void Clear(void);
   bool Get(const string key, double &value);
   bool Put(const string key, const double value);
   bool Invalidate(const string key);
   int Count(void) { return(m_count); }
  };

class CQmeUnionFind
  {
private:
   int m_parent[512], m_rank[512], m_size[512];
   int m_count;
public:
   CQmeUnionFind(void) { Init(0); }
   bool Init(const int elements);
   int Find(const int element);
   bool Union(const int left, const int right);
   int ComponentSize(const int element);
   int Count(void) { return(m_count); }
  };

class CQmeMinHeap
  {
private:
   double m_values[512];
   int    m_capacity;
   int    m_count;
public:
   CQmeMinHeap(void) { Init(512); }
   void Init(const int capacity);
   void Clear(void) { m_count = 0; }
   int Count(void) { return(m_count); }
   bool Push(const double value);
   bool Pop(double &minimum);
  };

bool CQmeAlgorithms::FindBarTimeDescending(const SCandle &bars[], const int count,
                                            const datetime target, int &shift)
  {
   shift = -1;
   if(target <= 0 || count <= 0 || count > ArraySize(bars)) return(false);
   int lo = 0;
   int hi = count - 1;
   while(lo <= hi)
     {
      const int mid = lo + (hi - lo) / 2;
      const datetime t = bars[mid].time;
      if(t == target) { shift = mid; return(true); }
      if(t > target) lo = mid + 1;  // newer timestamps are at lower indexes
      else hi = mid - 1;
     }
   return(false);
  }

bool CQmeAlgorithms::WelfordPush(const double value, long &count, double &mean, double &m2)
  {
   if(!QmeIsFinite(value) || count < 0 || !QmeIsFinite(mean) || !QmeIsFinite(m2)) return(false);
   // Guard signed count overflow without depending on platform-specific constants.
   if(count >= 9223372036854775806) return(false);
   const long next = count + 1;
   const double delta = value - mean;
   const double nextMean = mean + delta / (double)next;
   const double delta2 = value - nextMean;
   const double nextM2 = m2 + delta * delta2;
   if(!QmeIsFinite(nextMean) || !QmeIsFinite(nextM2)) return(false);
   count = next;
   mean = nextMean;
   m2 = nextM2;
   return(true);
  }

bool CQmeAlgorithms::WelfordVariance(const long count, const double m2,
                                      const bool sample, double &variance)
  {
   variance = 0.0;
   if(count < 0 || !QmeIsFinite(m2)) return(false);
   if(sample)
     {
      if(count < 2) return(false);
      variance = m2 / (double)(count - 1);
     }
   else
     {
      if(count < 1) return(false);
      variance = m2 / (double)count;
     }
   if(!QmeIsFinite(variance)) { variance = 0.0; return(false); }
   // Round-off may leave a tiny negative M2 for constant/nearly-constant data.
   if(variance < 0.0 && variance > -1.0e-12) variance = 0.0;
   if(variance < 0.0) { variance = 0.0; return(false); }
   return(true);
  }

bool CQmeAlgorithms::Quickselect(double &values[], const int count, const int k, double &selected)
  {
   selected = 0.0;
   if(count <= 0 || count > ArraySize(values) || k < 0 || k >= count) return(false);
   for(int i = 0; i < count; i++) if(!QmeIsFinite(values[i])) return(false);
   int left = 0, right = count - 1;
   while(left <= right)
     {
      const double pivot = values[left + (right - left) / 2];
      int lt = left, i = left, gt = right;
      while(i <= gt)
        {
         if(values[i] < pivot)
           { const double t=values[lt]; values[lt]=values[i]; values[i]=t; lt++; i++; }
         else if(values[i] > pivot)
           { const double t=values[gt]; values[gt]=values[i]; values[i]=t; gt--; }
         else i++;
        }
      if(k < lt) right = lt - 1;
      else if(k > gt) left = gt + 1;
      else { selected = values[k]; return(true); }
     }
   return(false);
  }

bool CQmeAlgorithms::StableMergeSort(double &values[], const int count)
  {
   if(count < 0 || count > ArraySize(values)) return(false);
   for(int i = 0; i < count; i++) if(!QmeIsFinite(values[i])) return(false);
   if(count < 2) return(true);
   double scratch[];
   if(ArrayResize(scratch, count) != count) return(false);
   int width = 1;
   while(width < count)
     {
      int base = 0;
      while(base < count)
        {
         const int mid = (int)MathMin((long)count, (long)base + width);
         const int end = (int)MathMin((long)count, (long)mid + width);
         int i = base, j = mid, out = base;
         while(i < mid && j < end)
           {
            if(values[i] <= values[j]) scratch[out++] = values[i++];
            else scratch[out++] = values[j++];
           }
         while(i < mid) scratch[out++] = values[i++];
         while(j < end) scratch[out++] = values[j++];
         base = end;
        }
      for(int i = 0; i < count; i++) values[i] = scratch[i];
      if(width > count / 2) break;
      width *= 2;
     }
   return(true);
  }

bool CQmeAlgorithms::BuildPrefixSum(const double &values[], const int count, double &prefix[])
  {
   ArrayResize(prefix, 0);
   if(count < 0 || count > ArraySize(values)) return(false);
   if(ArrayResize(prefix, count + 1) != count + 1) return(false);
   prefix[0] = 0.0;
   for(int i = 0; i < count; i++)
     {
      if(!QmeIsFinite(values[i])) { ArrayResize(prefix, 0); return(false); }
      prefix[i + 1] = prefix[i] + values[i];
      if(!QmeIsFinite(prefix[i + 1])) { ArrayResize(prefix, 0); return(false); }
     }
   return(true);
  }

bool CQmeAlgorithms::PrefixRangeSum(const double &prefix[], const int count,
                                    const int begin, const int end, double &sum)
  {
   sum = 0.0;
   if(count < 0 || ArraySize(prefix) != count + 1 || begin < 0 || end < begin || end > count)
      return(false);
   sum = prefix[end] - prefix[begin];
   return(QmeIsFinite(sum));
  }

bool CQmeAlgorithms::EwmaPush(const double value, const double alpha, bool &initialized,
                              double &state)
  {
   if(!QmeIsFinite(value) || !QmeIsFinite(alpha) || alpha <= 0.0 || alpha > 1.0) return(false);
   const double next = initialized ? alpha*value + (1.0-alpha)*state : value;
   if(!QmeIsFinite(next)) return(false);
   state = next;
   initialized = true;
   return(true);
  }

bool CQmeAlgorithms::WilderPush(const double value, const int period, int &count,
                                 double &seedSum, double &state, bool &ready)
  {
   if(!QmeIsFinite(value) || period <= 0 || count < 0 || count > period) return(false);
   if(ready)
     {
      const double next = state + (value - state) / period;
      if(!QmeIsFinite(next)) return(false);
      state = next;
      return(true);
     }
   if(count >= period) return(false);
   const double nextSum = seedSum + value;
   if(!QmeIsFinite(nextSum)) return(false);
   seedSum = nextSum;
   count++;
   if(count == period)
     {
      state = seedSum / period;
      if(!QmeIsFinite(state)) return(false);
      ready = true;
     }
   return(true);
  }

bool CQmeAlgorithms::CusumPush(const double observation, const double baseline,
                                const double allowance, const double threshold,
                                double &positive, double &negative, bool &change)
  {
   change = false;
   if(!QmeIsFinite(observation) || !QmeIsFinite(baseline) ||
      !QmeIsFinite(allowance) || !QmeIsFinite(threshold) ||
      allowance < 0.0 || threshold <= 0.0 ||
      !QmeIsFinite(positive) || !QmeIsFinite(negative)) return(false);
   const double residual = observation - baseline;
   const double nextPositive = MathMax(0.0, positive + residual - allowance);
   const double nextNegative = MathMin(0.0, negative + residual + allowance);
   if(!QmeIsFinite(nextPositive) || !QmeIsFinite(nextNegative)) return(false);
   positive = nextPositive;
   negative = nextNegative;
   change = (positive >= threshold || negative <= -threshold);
   if(change) { positive = 0.0; negative = 0.0; }
   return(true);
  }

int CQmeAlgorithms::IntersectSorted(const double &left[], const int leftCount,
                                    const double &right[], const int rightCount,
                                    double &out[])
  {
   ArrayResize(out, 0);
   if(leftCount < 0 || rightCount < 0 || leftCount > ArraySize(left) ||
      rightCount > ArraySize(right)) return(-1);
   for(int i=0; i<leftCount; i++)
     { if(!QmeIsFinite(left[i]) || (i>0 && left[i]<left[i-1])) return(-1); }
   for(int i=0; i<rightCount; i++)
     { if(!QmeIsFinite(right[i]) || (i>0 && right[i]<right[i-1])) return(-1); }
   int i=0, j=0;
   while(i<leftCount && j<rightCount)
     {
      if(left[i]<right[j]) i++;
      else if(right[j]<left[i]) j++;
      else
        {
         const int n=ArraySize(out);
         if(ArrayResize(out,n+1)!=n+1) { ArrayResize(out,0); return(-1); }
         out[n]=left[i]; i++; j++;
        }
     }
   return(ArraySize(out));
  }

void CQmeSlidingWindow::Init(const int capacity)
  {
   m_capacity=MathMin(MathMax(capacity,1),ArraySize(m_values));
   Clear();
  }

bool CQmeSlidingWindow::Push(const double value)
  {
   if(!QmeIsFinite(value) || m_capacity<=0) return(false);
   const double old=(m_count>=m_capacity ? m_values[m_next] : 0.0);
   const double nextSum=m_sum-old+value;
   if(!QmeIsFinite(nextSum)) return(false);
   m_values[m_next]=value;
   m_sum=nextSum;
   m_next=(m_next+1)%m_capacity;
   if(m_count<m_capacity) m_count++;
   return(true);
  }

void CQmeMonotonicDeque::Init(const int capacity, const bool maximum)
  {
   m_capacity=MathMin(MathMax(capacity,1),ArraySize(m_values));
   m_maximum=maximum;
   Clear();
  }

bool CQmeMonotonicDeque::Push(const int index, const double value)
  {
   if(index<0 || index<=m_lastIndex || !QmeIsFinite(value)) return(false);
   while(m_count>0)
     {
      const int last=(m_head+m_count-1)%m_capacity;
      const bool dominated=(m_maximum ? m_values[last]<=value : m_values[last]>=value);
      if(!dominated) break;
      m_count--;
     }
   if(m_count>=m_capacity) return(false);
   const int tail=(m_head+m_count)%m_capacity;
   m_indices[tail]=index;
   m_values[tail]=value;
   m_count++;
   m_lastIndex=index;
   return(true);
  }

void CQmeMonotonicDeque::ExpireBefore(const int firstValidIndex)
  {
   while(m_count>0 && m_indices[m_head]<firstValidIndex)
     { m_head=(m_head+1)%m_capacity; m_count--; }
  }

bool CQmeMonotonicDeque::Front(int &index, double &value)
  {
   index=-1; value=0.0;
   if(m_count<=0) return(false);
   index=m_indices[m_head]; value=m_values[m_head];
   return(true);
  }

bool CQmeIntervalTree::Build(const double &lower[], const double &upper[],
                              const int &payload[], const int count)
  {
   Clear();
   if(count<0 || count>ArraySize(m_lower) || count>ArraySize(lower) ||
      count>ArraySize(upper) || count>ArraySize(payload)) return(false);
   m_count=count;
   for(int i=0;i<count;i++)
     {
      if(!QmeIsFinite(lower[i]) || !QmeIsFinite(upper[i]) || lower[i]>upper[i])
        { Clear(); return(false); }
      m_lower[i]=lower[i]; m_upper[i]=upper[i]; m_payload[i]=payload[i];
     }
   // Stable deterministic ordering by lower, then upper, then payload.
   for(int i=1;i<count;i++)
     {
      const double lo=m_lower[i], hi=m_upper[i]; const int id=m_payload[i];
      int j=i-1;
      while(j>=0 && (m_lower[j]>lo || (m_lower[j]==lo &&
            (m_upper[j]>hi || (m_upper[j]==hi && m_payload[j]>id)))))
        {
         m_lower[j+1]=m_lower[j]; m_upper[j+1]=m_upper[j];
         m_payload[j+1]=m_payload[j]; j--;
        }
      m_lower[j+1]=lo; m_upper[j+1]=hi; m_payload[j+1]=id;
     }
   m_root=(count>0 ? BuildRange(0,count-1) : -1);
   return(true);
  }

int CQmeIntervalTree::BuildRange(const int first, const int last)
  {
   if(first>last) return(-1);
   const int mid=first+(last-first)/2;
   m_left[mid]=BuildRange(first,mid-1);
   m_right[mid]=BuildRange(mid+1,last);
   double maxUpper=m_upper[mid];
   if(m_left[mid]>=0) maxUpper=MathMax(maxUpper,m_maxUpper[m_left[mid]]);
   if(m_right[mid]>=0) maxUpper=MathMax(maxUpper,m_maxUpper[m_right[mid]]);
   m_maxUpper[mid]=maxUpper;
   return(mid);
  }

bool CQmeIntervalTree::QueryNode(const int node, const double lower, const double upper,
                                  int &out[])
  {
   if(node<0) return(true);
   const int left=m_left[node];
   if(left>=0 && m_maxUpper[left]>=lower)
      if(!QueryNode(left,lower,upper,out)) return(false);
   if(m_lower[node]<=upper && m_upper[node]>=lower)
     {
      const int n=ArraySize(out);
      if(ArrayResize(out,n+1)!=n+1) return(false);
      out[n]=m_payload[node];
     }
   const int right=m_right[node];
   if(right>=0 && m_lower[node]<=upper && m_maxUpper[right]>=lower)
      if(!QueryNode(right,lower,upper,out)) return(false);
   return(true);
  }

int CQmeIntervalTree::Query(const double lower, const double upper, int &out[])
  {
   ArrayResize(out,0);
   if(!QmeIsFinite(lower) || !QmeIsFinite(upper) || lower>upper) return(-1);
   if(!QueryNode(m_root,lower,upper,out)) { ArrayResize(out,0); return(-1); }
   return(ArraySize(out));
  }

void CQmeLRUCache::Init(const int capacity)
  {
   m_capacity=MathMin(MathMax(capacity,1),ArraySize(m_keys));
   Clear();
  }

void CQmeLRUCache::Clear(void)
  {
   m_count=0; m_clock=0;
   for(int i=0;i<ArraySize(m_keys);i++) { m_keys[i]=""; m_values[i]=0.0; m_age[i]=0; }
  }

void CQmeLRUCache::NormalizeClock(void)
  {
   // Access ages are unique. Replace them by their relative ranks, preserving LRU order.
   for(int i=0;i<m_count;i++)
     {
      long rank=1;
      for(int j=0;j<m_count;j++) if(m_age[j]<m_age[i]) rank++;
      // Store ranks in a scratch age vector to avoid rank updates affecting later comparisons.
      m_tmpAge[i]=rank;
     }
   for(int i=0;i<m_count;i++) m_age[i]=m_tmpAge[i];
   m_clock=m_count;
  }

void CQmeLRUCache::Touch(const int slot)
  {
   if(m_clock>=9000000000000000000) NormalizeClock();
   m_clock++;
   m_age[slot]=m_clock;
  }

bool CQmeLRUCache::Get(const string key, double &value)
  {
   value=0.0;
   if(StringLen(key)==0 || StringLen(key)>128) return(false);
   for(int i=0;i<m_count;i++)
      if(m_keys[i]==key) { value=m_values[i]; Touch(i); return(true); }
   return(false);
  }

bool CQmeLRUCache::Put(const string key, const double value)
  {
   if(StringLen(key)==0 || StringLen(key)>128 || !QmeIsFinite(value) || m_capacity<=0) return(false);
   for(int i=0;i<m_count;i++)
      if(m_keys[i]==key) { m_values[i]=value; Touch(i); return(true); }
   int slot=-1;
   if(m_count<m_capacity) slot=m_count++;
   else
     {
      slot=0;
      for(int i=1;i<m_count;i++) if(m_age[i]<m_age[slot]) slot=i;
     }
   m_keys[slot]=key; m_values[slot]=value; Touch(slot);
   return(true);
  }

bool CQmeLRUCache::Invalidate(const string key)
  {
   if(StringLen(key)==0 || StringLen(key)>128) return(false);
   for(int i=0;i<m_count;i++)
     if(m_keys[i]==key)
       {
        for(int j=i;j<m_count-1;j++)
          { m_keys[j]=m_keys[j+1]; m_values[j]=m_values[j+1]; m_age[j]=m_age[j+1]; }
        m_count--; m_keys[m_count]=""; m_values[m_count]=0.0; m_age[m_count]=0;
        return(true);
       }
   return(false);
  }

bool CQmeUnionFind::Init(const int elements)
  {
   if(elements<0 || elements>ArraySize(m_parent)) { m_count=0; return(false); }
   m_count=elements;
   for(int i=0;i<m_count;i++) { m_parent[i]=i; m_rank[i]=0; m_size[i]=1; }
   return(true);
  }

int CQmeUnionFind::Find(const int element)
  {
   if(element<0 || element>=m_count) return(-1);
   int root=element;
   while(m_parent[root]!=root) root=m_parent[root];
   int node=element;
   while(m_parent[node]!=node)
     { const int next=m_parent[node]; m_parent[node]=root; node=next; }
   return(root);
  }

bool CQmeUnionFind::Union(const int left, const int right)
  {
   int a=Find(left), b=Find(right);
   if(a<0 || b<0) return(false);
   if(a==b) return(false);
   if(m_rank[a]<m_rank[b]) { const int t=a; a=b; b=t; }
   m_parent[b]=a; m_size[a]+=m_size[b];
   if(m_rank[a]==m_rank[b]) m_rank[a]++;
   return(true);
  }

int CQmeUnionFind::ComponentSize(const int element)
  {
   const int root=Find(element);
   return(root<0 ? 0 : m_size[root]);
  }

bool CQmeAlgorithms::TopologicalSort(const int &adjacency[], const int nodes, int &order[])
  {
   ArrayResize(order,0);
   if(nodes<0 || nodes>64 || ArraySize(adjacency)<nodes*nodes) return(false);
   int indegree[64], queue[64];
   for(int i=0;i<nodes;i++) indegree[i]=0;
   for(int u=0;u<nodes;u++)
     for(int v=0;v<nodes;v++)
       {
        const int edge=adjacency[u*nodes+v];
        if(edge!=0 && edge!=1) return(false);
        if(edge==1) indegree[v]++;
       }
   int head=0, tail=0;
   for(int i=0;i<nodes;i++) if(indegree[i]==0) queue[tail++]=i;
   if(ArrayResize(order,nodes)!=nodes) return(false);
   int produced=0;
   while(head<tail)
     {
      const int u=queue[head++]; order[produced++]=u;
      for(int v=0;v<nodes;v++)
        if(adjacency[u*nodes+v]==1)
          { indegree[v]--; if(indegree[v]==0) queue[tail++]=v; }
     }
   if(produced!=nodes) { ArrayResize(order,0); return(false); }
   return(true);
  }

bool CQmeAlgorithms::KWayMerge(const double &streams[], const int &offsets[],
                                const int &lengths[], const int streamCount, double &merged[])
  {
   ArrayResize(merged,0);
   if(streamCount<0 || streamCount>512 || streamCount>ArraySize(offsets) ||
      streamCount>ArraySize(lengths)) return(false);
   int total=0;
   for(int s=0;s<streamCount;s++)
     {
      if(offsets[s]<0 || lengths[s]<0 || offsets[s]>ArraySize(streams)-lengths[s]) return(false);
      if(lengths[s]>2147483647-total) return(false);
      total+=lengths[s];
      if(total>QME_ALGO_MAX_STREAM_VALUES) return(false);
      for(int j=0;j<lengths[s];j++)
        {
         const double v=streams[offsets[s]+j];
         if(!QmeIsFinite(v) || (j>0 && v<streams[offsets[s]+j-1])) return(false);
        }
     }
   if(ArrayResize(merged,total)!=total) return(false);
   if(streamCount==0 || total==0) return(true);
   int streamHeap[];
   int cursor[512];
   if(ArrayResize(streamHeap,streamCount)!=streamCount) { ArrayResize(merged,0); return(false); }
   int heapCount=0;
   for(int s=0;s<streamCount;s++)
     {
      cursor[s]=0;
      if(lengths[s]<=0) continue;
      int child=heapCount++;
      streamHeap[child]=s;
      while(child>0)
        {
         const int parent=(child-1)/2;
         const int ps=streamHeap[parent], cs=streamHeap[child];
         if(streams[offsets[ps]+cursor[ps]]<=streams[offsets[cs]+cursor[cs]]) break;
         const int t=streamHeap[parent]; streamHeap[parent]=streamHeap[child]; streamHeap[child]=t;
         child=parent;
        }
     }
   for(int out=0;out<total;out++)
     {
      if(heapCount<=0) { ArrayResize(merged,0); return(false); }
      const int s=streamHeap[0];
      merged[out]=streams[offsets[s]+cursor[s]];
      cursor[s]++;
      if(cursor[s]>=lengths[s])
        {
         heapCount--;
         if(heapCount>0) streamHeap[0]=streamHeap[heapCount];
        }
      if(heapCount>0)
        {
         int parent=0;
         while(true)
           {
            const int left=parent*2+1;
            if(left>=heapCount) break;
            const int right=left+1;
            int child=left;
            if(right<heapCount)
              {
               const int ls=streamHeap[left], rs=streamHeap[right];
               if(streams[offsets[rs]+cursor[rs]]<streams[offsets[ls]+cursor[ls]]) child=right;
              }
            const int ps=streamHeap[parent], cs=streamHeap[child];
            if(streams[offsets[ps]+cursor[ps]]<=streams[offsets[cs]+cursor[cs]]) break;
            const int t=streamHeap[parent]; streamHeap[parent]=streamHeap[child]; streamHeap[child]=t;
            parent=child;
           }
        }
     }
   return(true);
  }

bool CQmeAlgorithms::SweepMaxOverlap(const double &lower[], const double &upper[],
                                      const int count, int &maximum)
  {
   maximum=0;
   if(count<0 || count>QME_ALGO_MAX_SWEEP_INTERVALS ||
      count>ArraySize(lower) || count>ArraySize(upper)) return(false);
   SQmeSweepEvent events[];
   SQmeSweepEvent scratch[];
   const int eventCount=count*2;
   if(ArrayResize(events,eventCount)!=eventCount || ArrayResize(scratch,eventCount)!=eventCount) return(false);
   for(int i=0;i<count;i++)
     {
      if(!QmeIsFinite(lower[i]) || !QmeIsFinite(upper[i]) || lower[i]>upper[i]) return(false);
      events[2*i].position=lower[i]; events[2*i].delta=1;
      events[2*i+1].position=upper[i]; events[2*i+1].delta=-1;
     }
   int width=1;
   while(width<eventCount)
     {
      int base=0;
      while(base<eventCount)
        {
         const int mid=(int)MathMin((double)eventCount,(double)base+width);
         const int end=(int)MathMin((double)eventCount,(double)mid+width);
         int i=base,j=mid,o=base;
         while(i<mid && j<end)
           {
            const bool takeLeft=(events[i].position<events[j].position ||
              (events[i].position==events[j].position && events[i].delta>=events[j].delta));
            scratch[o++]=takeLeft ? events[i++] : events[j++];
           }
         while(i<mid) scratch[o++]=events[i++];
         while(j<end) scratch[o++]=events[j++];
         base=end;
        }
      for(int i=0;i<eventCount;i++) events[i]=scratch[i];
      if(width>eventCount/2) break;
      width*=2;
     }
   int active=0;
   for(int i=0;i<eventCount;i++)
     { active+=events[i].delta; if(active>maximum) maximum=active; }
   return(true);
  }

void CQmeMinHeap::Init(const int capacity)
  {
   m_capacity = MathMin(MathMax(capacity, 1), ArraySize(m_values));
   m_count = 0;
  }

bool CQmeMinHeap::Push(const double value)
  {
   if(!QmeIsFinite(value) || m_capacity <= 0 || m_count >= m_capacity) return(false);
   int child = m_count++;
   while(child > 0)
     {
      const int parent = (child - 1) / 2;
      if(m_values[parent] <= value) break;
      m_values[child] = m_values[parent];
      child = parent;
     }
   m_values[child] = value;
   return(true);
  }

bool CQmeMinHeap::Pop(double &minimum)
  {
   minimum = 0.0;
   if(m_count <= 0) return(false);
   minimum = m_values[0];
   const double tail = m_values[m_count - 1];
   m_count--;
   if(m_count <= 0) return(true);
   int parent = 0;
   while(true)
     {
      const int left = parent * 2 + 1;
      if(left >= m_count) break;
      const int right = left + 1;
      const int child = (right < m_count && m_values[right] < m_values[left]) ? right : left;
      if(m_values[child] >= tail) break;
      m_values[parent] = m_values[child];
      parent = child;
     }
   m_values[parent] = tail;
   return(true);
  }

#endif // __QME_CORE_ALGORITHMS_MQH__
