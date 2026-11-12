//+------------------------------------------------------------------+
//| Deterministic tests for implemented QME algorithm primitives      |
//+------------------------------------------------------------------+
#ifndef __QME_TEST_ADVANCED_ALGORITHMS_MQH__
#define __QME_TEST_ADVANCED_ALGORITHMS_MQH__

#include "../../QME.mqh"
#include "../TestKit.mqh"

CTestKit g_algoKit;

int RunAdvancedAlgorithmTests(void)
  {
   g_algoKit.Begin("Unit/Test_AdvancedAlgorithms");

   SCandle bars[5];
   for(int i = 0; i < 5; i++)
     {
      QmeCandleClear(bars[i]);
      bars[i].time = (datetime)(500 - 60 * i); // newest first, unique
      bars[i].valid = true;
     }
   int shift = 99;
   g_algoKit.Check(CQmeAlgorithms::FindBarTimeDescending(bars, 5, 380, shift) && shift == 2,
                   "binary search locates exact middle timestamp");
   g_algoKit.Check(CQmeAlgorithms::FindBarTimeDescending(bars, 5, 500, shift) && shift == 0,
                   "binary search locates newest boundary");
   g_algoKit.Check(CQmeAlgorithms::FindBarTimeDescending(bars, 5, 260, shift) && shift == 4,
                   "binary search locates oldest boundary");
   g_algoKit.Check(!CQmeAlgorithms::FindBarTimeDescending(bars, 5, 381, shift) && shift == -1,
                   "binary search requires exact timestamp");
   g_algoKit.Check(!CQmeAlgorithms::FindBarTimeDescending(bars, 0, 500, shift) && shift == -1,
                   "binary search handles empty input");
   g_algoKit.Check(!CQmeAlgorithms::FindBarTimeDescending(bars, 5, 0, shift),
                   "binary search rejects invalid timestamp");

   long count = 0;
   double mean = 0.0, m2 = 0.0, variance = -1.0;
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(1.0, count, mean, m2), "Welford accepts first value");
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(2.0, count, mean, m2), "Welford accepts second value");
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(3.0, count, mean, m2), "Welford accepts third value");
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(4.0, count, mean, m2), "Welford accepts fourth value");
   g_algoKit.CheckEqual(count, 4, "Welford count is exact");
   g_algoKit.CheckClose(mean, 2.5, 1.0e-12, "Welford mean matches reference");
   g_algoKit.Check(CQmeAlgorithms::WelfordVariance(count, m2, false, variance),
                   "population variance is available");
   g_algoKit.CheckClose(variance, 1.25, 1.0e-12, "population variance matches reference");
   g_algoKit.Check(CQmeAlgorithms::WelfordVariance(count, m2, true, variance),
                   "sample variance is available");
   g_algoKit.CheckClose(variance, 1.6666666666666667, 1.0e-12,
                        "sample variance matches reference");
   g_algoKit.Check(!CQmeAlgorithms::WelfordVariance(0, 0.0, false, variance),
                   "empty population variance rejected");
   g_algoKit.Check(!CQmeAlgorithms::WelfordVariance(1, 0.0, true, variance),
                   "sample variance requires two observations");
   g_algoKit.Check(!CQmeAlgorithms::WelfordPush(DBL_MAX, count, mean, m2),
                   "non-finite intermediate is rejected without corrupting state");
   g_algoKit.CheckEqual(count, 4, "rejected overflow leaves count unchanged");
   g_algoKit.CheckClose(mean, 2.5, 1.0e-12, "rejected overflow leaves mean unchanged");

   //--- a large offset verifies Welford's numerical stability against raw-sum variance
   count = 0; mean = 0.0; m2 = 0.0;
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(1000000001.0, count, mean, m2),
                   "large-offset sample value one");
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(1000000002.0, count, mean, m2),
                   "large-offset sample value two");
   g_algoKit.Check(CQmeAlgorithms::WelfordPush(1000000003.0, count, mean, m2),
                   "large-offset sample value three");
   g_algoKit.Check(CQmeAlgorithms::WelfordVariance(count, m2, false, variance),
                   "large-offset variance is available");
   g_algoKit.CheckClose(variance, 2.0 / 3.0, 1.0e-8,
                        "large-offset variance remains stable");

   //--- Quickselect: zero-based order statistic; mutation is confined to input
   double source[5] = {7.0, -2.0, 4.0, 4.0, 0.0};
   double expected[5] = {-2.0, 0.0, 4.0, 4.0, 7.0};
   for(int k = 0; k < 5; k++)
     {
      double work[5];
      for(int j = 0; j < 5; j++) work[j] = source[j];
      double selectedValue = 0.0;
      const bool found = CQmeAlgorithms::Quickselect(work, 5, k, selectedValue);
      g_algoKit.Check(found, "quickselect valid rank " + IntegerToString(k));
      if(found) g_algoKit.CheckClose(selectedValue, expected[k], 0.0,
                                     "quickselect reference value " + IntegerToString(k));
     }
   double invalidSelect[];
   ArrayResize(invalidSelect, 1); invalidSelect[0] = 3.0;
   double selectedValue = 0.0;
   g_algoKit.Check(!CQmeAlgorithms::Quickselect(invalidSelect, 1, 1, selectedValue),
                   "quickselect rejects out-of-range rank");

   //--- stable ascending merge sort, including duplicate values
   double sortable[5] = {7.0, -2.0, 4.0, 4.0, 0.0};
   g_algoKit.Check(CQmeAlgorithms::StableMergeSort(sortable, 5), "merge sort accepts finite input");
   for(int i = 0; i < 5; i++)
      g_algoKit.CheckClose(sortable[i], expected[i], 0.0,
                           "merge sort ascending index " + IntegerToString(i));
   double emptySort[];
   g_algoKit.Check(CQmeAlgorithms::StableMergeSort(emptySort, 0), "merge sort accepts empty input");

   //--- min heap ordering, duplicates, empty state, and capacity policy
   CQmeMinHeap heap;
   heap.Init(4);
   double popped = 0.0;
   g_algoKit.Check(!heap.Pop(popped), "empty heap pop is rejected");
   g_algoKit.Check(heap.Push(3.0) && heap.Push(-1.0) && heap.Push(3.0) && heap.Push(2.0),
                   "heap accepts entries through capacity");
   g_algoKit.Check(!heap.Push(0.0), "heap refuses capacity overflow");
   g_algoKit.Check(heap.Pop(popped) && popped == -1.0, "heap pops minimum first");
   g_algoKit.Check(heap.Pop(popped) && popped == 2.0, "heap maintains order after pop");
   g_algoKit.Check(heap.Pop(popped) && popped == 3.0, "heap handles duplicate values");
   g_algoKit.Check(heap.Pop(popped) && popped == 3.0, "heap returns each duplicate once");
   g_algoKit.Check(!heap.Pop(popped), "heap is empty after final pop");

   //--- Prefix sums use half-open [begin,end) ranges and guard bounds/overflow
   double aggregates[] = {1.5, -2.0, 4.5, 3.0};
   double prefix[];
   g_algoKit.Check(CQmeAlgorithms::BuildPrefixSum(aggregates, 4, prefix),
                   "prefix sums build for finite values");
   double range = 0.0;
   g_algoKit.Check(CQmeAlgorithms::PrefixRangeSum(prefix, 4, 1, 3, range),
                   "prefix sum accepts half-open range");
   g_algoKit.CheckClose(range, 2.5, 0.0, "prefix range matches direct sum");
   g_algoKit.Check(!CQmeAlgorithms::PrefixRangeSum(prefix, 4, -1, 2, range),
                   "prefix sum rejects negative index");
   double emptyValues[], emptyPrefix[];
   g_algoKit.Check(CQmeAlgorithms::BuildPrefixSum(emptyValues, 0, emptyPrefix),
                   "prefix sum accepts empty input");
   g_algoKit.CheckEqual(ArraySize(emptyPrefix), 1, "empty prefix contains origin only");
   double overflowValues[2] = {DBL_MAX, DBL_MAX};
   double overflowPrefix[];
   g_algoKit.Check(!CQmeAlgorithms::BuildPrefixSum(overflowValues, 2, overflowPrefix),
                   "prefix sum rejects floating overflow");

   //--- EWMA initialization, recurrence, and invalid alpha handling
   bool initialized = false; double ewma = 0.0;
   g_algoKit.Check(CQmeAlgorithms::EwmaPush(10.0, 0.25, initialized, ewma),
                   "EWMA accepts first value");
   g_algoKit.CheckClose(ewma, 10.0, 0.0, "EWMA initializes from first observation");
   g_algoKit.Check(CQmeAlgorithms::EwmaPush(14.0, 0.25, initialized, ewma),
                   "EWMA accepts next value");
   g_algoKit.CheckClose(ewma, 11.0, 1.0e-12, "EWMA recurrence matches reference");
   g_algoKit.Check(!CQmeAlgorithms::EwmaPush(1.0, 0.0, initialized, ewma),
                   "EWMA rejects invalid alpha");

   //--- Wilder smoothing seeds with an arithmetic mean then applies Wilder recurrence
   int wCount=0; double wSeed=0.0, wState=0.0; bool wReady=false;
   g_algoKit.Check(CQmeAlgorithms::WilderPush(2.0,3,wCount,wSeed,wState,wReady), "Wilder seed one");
   g_algoKit.Check(CQmeAlgorithms::WilderPush(4.0,3,wCount,wSeed,wState,wReady), "Wilder seed two");
   g_algoKit.Check(!wReady, "Wilder remains unready during seed");
   g_algoKit.Check(CQmeAlgorithms::WilderPush(6.0,3,wCount,wSeed,wState,wReady), "Wilder seed completes");
   g_algoKit.Check(wReady, "Wilder becomes ready at configured period");
   g_algoKit.CheckClose(wState,4.0,1.0e-12,"Wilder seed mean matches reference");
   g_algoKit.Check(CQmeAlgorithms::WilderPush(7.0,3,wCount,wSeed,wState,wReady),"Wilder update accepted");
   g_algoKit.CheckClose(wState,5.0,1.0e-12,"Wilder recurrence matches reference");

   //--- CUSUM is a change detector; it resets its accumulator after an alarm
   double pos=0.0, neg=0.0; bool changed=false;
   g_algoKit.Check(CQmeAlgorithms::CusumPush(1.0,0.0,0.25,1.5,pos,neg,changed),"CUSUM accepts observation");
   g_algoKit.Check(!changed,"CUSUM below threshold emits no event");
   g_algoKit.Check(CQmeAlgorithms::CusumPush(1.0,0.0,0.25,1.5,pos,neg,changed),"CUSUM accepts repeated shift");
   g_algoKit.Check(changed && pos==0.0 && neg==0.0,"CUSUM emits change event and resets");
   g_algoKit.Check(!CQmeAlgorithms::CusumPush(0.0,0.0,0.0,0.0,pos,neg,changed),
                   "CUSUM rejects nonpositive threshold");

   //--- two-pointer intersection preserves sorted multiset multiplicity
   double leftSorted[]={-2.0,1.0,1.0,4.0,9.0};
   double rightSorted[]={1.0,1.0,3.0,9.0};
   double common[];
   const int commonCount=CQmeAlgorithms::IntersectSorted(leftSorted,5,rightSorted,4,common);
   g_algoKit.CheckEqual(commonCount,3,"two-pointer intersection returns common multiplicity");
   if(commonCount==3)
     { g_algoKit.CheckClose(common[0],1.0,0.0,"intersection first match");
       g_algoKit.CheckClose(common[1],1.0,0.0,"intersection duplicate match");
       g_algoKit.CheckClose(common[2],9.0,0.0,"intersection final match"); }
   double unsorted[]={2.0,1.0};
   g_algoKit.CheckEqual(CQmeAlgorithms::IntersectSorted(unsorted,2,rightSorted,4,common),-1,
                        "two-pointer rejects unsorted input");

   //--- fixed rolling mean and monotonic maximum deque
   CQmeSlidingWindow window; window.Init(3);
   g_algoKit.CheckClose(window.Mean(-1.0),-1.0,0.0,"empty rolling window uses fallback");
   g_algoKit.Check(window.Push(1.0)&&window.Push(2.0)&&window.Push(3.0),"window accepts initial values");
   g_algoKit.CheckClose(window.Mean(),2.0,1.0e-12,"window initial mean");
   g_algoKit.Check(window.Push(7.0),"window overwrites oldest at capacity");
   g_algoKit.CheckClose(window.Mean(),4.0,1.0e-12,"window mean reflects eviction");
   CQmeMonotonicDeque deque; deque.Init(4,true);
   g_algoKit.Check(deque.Push(0,2.0)&&deque.Push(1,1.0)&&deque.Push(2,5.0),
                   "monotonic deque accepts increasing indexes");
   int topIndex=-1; double topValue=0.0;
   g_algoKit.Check(deque.Front(topIndex,topValue)&&topIndex==2&&topValue==5.0,
                   "monotonic deque exposes maximum");
   deque.ExpireBefore(3);
   g_algoKit.Check(!deque.Front(topIndex,topValue),"deque expires out-of-window maximum");
   g_algoKit.Check(!deque.Push(2,8.0),"deque rejects nonmonotonic index");

   //--- balanced interval index, inclusive boundaries, invalid input and empty tree
   CQmeIntervalTree intervals;
   double ilow[]={10.0,15.0,30.0,12.0}, ihigh[]={20.0,18.0,40.0,15.0};
   int ipayload[]={10,20,30,40};
   g_algoKit.Check(intervals.Build(ilow,ihigh,ipayload,4),"interval tree builds bounded ranges");
   int hits[]; const int hitCount=intervals.Query(15.0,16.0,hits);
   g_algoKit.CheckEqual(hitCount,3,"interval tree returns all intersecting ranges");
   bool got10=false,got20=false,got40=false;
   for(int h=0;h<hitCount;h++)
     { if(hits[h]==10) got10=true; if(hits[h]==20) got20=true; if(hits[h]==40) got40=true; }
   g_algoKit.Check(got10&&got20&&got40,"interval results preserve payload identity");
   g_algoKit.CheckEqual(intervals.Query(21.0,29.0,hits),0,"interval query handles no matches");
   g_algoKit.CheckEqual(intervals.Query(5.0,4.0,hits),-1,"interval query rejects inverted bounds");
   double emptyLo[],emptyHi[]; int emptyIds[];
   g_algoKit.Check(intervals.Build(emptyLo,emptyHi,emptyIds,0),"interval tree accepts empty build");
   g_algoKit.CheckEqual(intervals.Query(-1.0,1.0,hits),0,"empty interval tree returns no matches");
   double invalidLo[]={2.0},invalidHi[]={1.0}; int invalidId[]={1};
   g_algoKit.Check(!intervals.Build(invalidLo,invalidHi,invalidId,1),"interval tree rejects inverted stored range");

   //--- pre-existing bounded ring buffer behavior and wraparound
   CQmeRing ring; ring.Init(3);
   g_algoKit.CheckEqual(ring.Count(),0,"ring initializes empty");
   g_algoKit.CheckClose(ring.Average(-1.0),-1.0,0.0,"empty ring average fallback");
   ring.Push(1.0); ring.Push(3.0); ring.Push(5.0); ring.Push(7.0);
   g_algoKit.CheckEqual(ring.Count(),3,"ring remains at configured capacity");
   g_algoKit.CheckClose(ring.Last(),7.0,0.0,"ring last after wraparound");
   g_algoKit.CheckClose(ring.Average(),5.0,1.0e-12,"ring average after oldest eviction");
   g_algoKit.CheckClose(ring.Minimum(),3.0,0.0,"ring minimum after wraparound");
   g_algoKit.CheckClose(ring.Maximum(),7.0,0.0,"ring maximum after wraparound");
   ring.Clear();
   g_algoKit.CheckEqual(ring.Count(),0,"ring clear releases logical contents");

   //--- bounded LRU eviction and explicit invalidation
   CQmeLRUCache lru; lru.Init(2);
   g_algoKit.Check(lru.Put("A",1.0)&&lru.Put("B",2.0),"LRU inserts two values");
   double cached=0.0;
   g_algoKit.Check(lru.Get("A",cached)&&cached==1.0,"LRU hit refreshes recency");
   g_algoKit.Check(lru.Put("C",3.0),"LRU insert at capacity evicts least recent");
   g_algoKit.Check(!lru.Get("B",cached),"LRU evicted key misses");
   g_algoKit.Check(lru.Get("A",cached)&&cached==1.0,"recent LRU key survives eviction");
   g_algoKit.Check(lru.Invalidate("A")&&!lru.Get("A",cached),"LRU explicit invalidation works");
   g_algoKit.Check(!lru.Put("",4.0),"LRU rejects empty key");

   //--- disjoint-set union with path compression/rank and bounded indexes
   CQmeUnionFind uf;
   g_algoKit.Check(uf.Init(5),"union-find initializes bounded set");
   g_algoKit.Check(uf.Union(0,1)&&uf.Union(1,2),"union-find joins components");
   g_algoKit.Check(uf.Find(0)==uf.Find(2),"union-find finds common root");
   g_algoKit.CheckEqual(uf.ComponentSize(1),3,"union-find component size");
   g_algoKit.Check(!uf.Union(0,2),"union-find reports already-connected pair");
   g_algoKit.Check(uf.Find(-1)==-1&&!uf.Union(0,9),"union-find rejects invalid indexes");
   g_algoKit.Check(!uf.Init(513),"union-find rejects over-capacity set");

   //--- deterministic Kahn topological order and cycle rejection
   int dag[9]={0,1,0, 0,0,1, 0,0,0};
   int topo[];
   g_algoKit.Check(CQmeAlgorithms::TopologicalSort(dag,3,topo),"topological sort accepts DAG");
   g_algoKit.Check(ArraySize(topo)==3&&topo[0]==0&&topo[1]==1&&topo[2]==2,
                   "topological sort emits dependency order");
   int cycle[4]={0,1,1,0};
   g_algoKit.Check(!CQmeAlgorithms::TopologicalSort(cycle,2,topo)&&ArraySize(topo)==0,
                   "topological sort rejects cycle and clears output");

   //--- heap-based K-way merge validates each sorted stream
   double streams[]={1.0,4.0,7.0,2.0,3.0,8.0,0.0,9.0};
   int offsets[]={0,3,5}, lengths[]={3,3,2};
   double merged[];
   g_algoKit.Check(CQmeAlgorithms::KWayMerge(streams,offsets,lengths,3,merged),
                   "K-way merge accepts sorted streams");
   double mergedExpected[]={0.0,1.0,2.0,3.0,4.0,7.0,8.0,9.0};
   g_algoKit.CheckEqual(ArraySize(merged),8,"K-way output has total input size");
   for(int mi=0;mi<ArraySize(merged);mi++)
      g_algoKit.CheckClose(merged[mi],mergedExpected[mi],0.0,
                           "K-way merged position "+IntegerToString(mi));
   double badStream[]={2.0,1.0}; int oneOffset[]={0},oneLength[]={2};
   g_algoKit.Check(!CQmeAlgorithms::KWayMerge(badStream,oneOffset,oneLength,1,merged),
                   "K-way merge rejects unsorted stream");

   //--- sweep-line maximum overlap for closed intervals
   double lowers[]={1.0,2.0,3.0}, uppers[]={3.0,4.0,3.0}; int overlap=0;
   g_algoKit.Check(CQmeAlgorithms::SweepMaxOverlap(lowers,uppers,3,overlap),
                   "sweep-line accepts valid intervals");
   g_algoKit.CheckEqual(overlap,3,"closed intervals sharing endpoint overlap");
   double badUpper[]={0.0}; double badLower[]={1.0};
   g_algoKit.Check(!CQmeAlgorithms::SweepMaxOverlap(badLower,badUpper,1,overlap),
                   "sweep-line rejects inverted interval");

   //--- production diagnostic integration: cumulative cycle dispersion only
   CPerformanceMetrics metrics;
   metrics.Init(10, 100000.0);
   g_algoKit.CheckClose(metrics.CycleStdDevMs(), 0.0, 0.0,
                        "cycle dispersion starts at zero");
   metrics.CycleBegin(); metrics.CycleEnd();
   metrics.CycleBegin(); metrics.CycleEnd();
   g_algoKit.CheckEqual(metrics.Cycles(), 2, "cycle metrics still count both samples");
   g_algoKit.Check(QmeIsFinite(metrics.CycleStdDevMs()) && metrics.CycleStdDevMs() >= 0.0,
                   "Welford dispersion is finite and nonnegative");
   g_algoKit.Check(QmeIsFinite(metrics.CycleEwmaMs()) && metrics.CycleEwmaMs() >= 0.0,
                   "EWMA production diagnostic is finite and nonnegative");

   return(g_algoKit.End());
  }

#endif // __QME_TEST_ADVANCED_ALGORITHMS_MQH__
