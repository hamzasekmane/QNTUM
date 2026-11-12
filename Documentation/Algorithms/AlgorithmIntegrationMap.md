# Algorithm integration map — implementation status

All 20 requested algorithm families have source implementations or were already present, but only four have production call sites at this stage. Native compile/runtime checks are blocked; utility tests are written, not executed. No strategy threshold or execution protection was changed.

| # | Algorithm | Implementation owner | Production connection | Test / validation gate |
|---:|---|---|---|---|
| 1 | Hash map | `Strategy/SignalDeduplicator.mqh` | Secondary index for fingerprint `Find`; authoritative ring/persistence remains unchanged. | `Test_HashIndex`: collision, miss, cooldown, prune, restore and capacity; requires MT5. |
| 2 | Binary search | `Core/Algorithms.mqh`, `Data/BarSeries.mqh` | `CBarSeries::FindShiftByTime/AtTime` exact lookup for valid descending closed bars. | `Test_AdvancedAlgorithms`: exact/missing/empty/boundary; requires MT5. |
| 3 | Min heap | `Core/Algorithms.mqh::CQmeMinHeap` | Utility only; not used to replace deterministic zone selection. | Empty, duplicate, order and capacity test; requires MT5. |
| 4 | Quickselect | `Core/Algorithms.mqh::Quickselect` | Utility only; not connected to opportunity ranking. | Reference order statistics and invalid rank test; requires MT5. |
| 5 | Merge sort | `Core/Algorithms.mqh::StableMergeSort` | Utility only; existing zone ranker unchanged. | Sorted output, duplicates, empty input test; requires MT5. |
| 6 | Interval tree | `Core/Algorithms.mqh::CQmeIntervalTree` | Utility index; not installed as `ZoneBoard` owner index. | Inclusive overlaps, empty, inverted intervals, payload tests; requires MT5. |
| 7 | EWMA | `Core/Algorithms.mqh::EwmaPush` consumed by `Monitoring/PerformanceMetrics.mqh` | Cycle durations tracked as diagnostic EWMA (alpha 0.2), not a market signal. | Recurrence/finite test; no trading effect. |
| LRU | `Core/Algorithms.mqh::CQmeLRUCache` | Utility only; no market data cached, avoiding stale-data risk. | Recency, eviction, invalidation and empty-key tests; requires MT5. |
| 8 | Ring buffer | `Core/EventBus.mqh`, `Runtime/AlgoContainers.mqh` | Existing event and sample histories; no duplicate ring added. | Existing suite plus overflow/runtime validation needed. |
| 9 | Sliding window | `Core/Algorithms.mqh::CQmeSlidingWindow` | Utility only; not replacing bar statistics. | Mean, fallback and overwrite tests; requires MT5. |
| 10 | Monotonic deque | `Core/Algorithms.mqh::CQmeMonotonicDeque` | Utility only; swing logic unchanged. | Max, expiration, index ordering and capacity tests; requires MT5. |
| 11 | Prefix sums | `Core/Algorithms.mqh` | Utility only; no market aggregation replaced. | Half-open range, empty, invalid bound and overflow tests; requires MT5. |
| 12 | Welford | `Core/Algorithms.mqh` | `Monitoring/PerformanceMetrics.mqh` cumulative cycle-time dispersion, diagnostics only. | Reference variance, large offset, overflow and metrics integration tests; requires MT5. |
| 13 | EWMA | `Core/Algorithms.mqh` | Utility only; volatility regime semantics unchanged. | Seed, recurrence, invalid alpha tests; requires MT5. |
| 14 | Wilder | `Core/Algorithms.mqh` | Utility only; platform ATR unchanged. | Seed period/readiness and recurrence tests; requires MT5. |
| 15 | Two pointers | `Core/Algorithms.mqh::IntersectSorted` | Utility only; no candidate/event matcher changed. | Duplicate multiset intersection and unsorted-input test; requires MT5. |
| 16 | CUSUM | `Core/Algorithms.mqh::CusumPush` | Utility only; not connected to scoring/entries. | Change threshold/reset/invalid config tests; diagnostics-only if adopted. |
| 17 | Sweep line | `Core/Algorithms.mqh::SweepMaxOverlap` | Utility only; no zone decisions changed. | Closed-interval equality, invalid range tests; requires MT5. |
| 18 | Union-find | `Core/Algorithms.mqh::CQmeUnionFind` | Utility only; no EQH/EQL clustering changed. | Join, duplicate join, component size and index bounds tests; requires MT5. |
| 19 | K-way merge | `Core/Algorithms.mqh::KWayMerge` | Utility only; MTF event source/order unchanged. | Sorted stream, duplicate/order and invalid stream tests; requires MT5. |
| 20 | Topological sort | `Core/Algorithms.mqh::TopologicalSort` | Utility only; static engine pipeline unchanged. | DAG order, cycle rejection and empty graph tests; requires MT5. |

## Adoption gate

A source utility being present is not equivalent to integration in a live analysis path. Before adopting any utility in zones, liquidity, candidates, signals or market statistics, run MetaEditor build + MT5 fixture suites, compare exact outputs with current QME reference behavior, measure representative workloads, inspect allocations, then keep the old path if no measured benefit. Execution and risk protections remain authoritative and untouched.
