# Advanced algorithms catalog — current implementation state

**Source implementation status: implementations are present for the 19 newly requested algorithms plus the pre-existing ring buffer (20/20 source-level).** This is not a claim that they compile, execute correctly in MT5, are all wired into trading decisions, or are performance-verified. New generic primitives live in `Core/Algorithms.mqh`; hash lookup, bar-time search, Welford and EWMA diagnostics also have production call sites. Other primitives are exercised by the deterministic MQL5 algorithm suite but remain adoption candidates until native validation and workload evidence exist.

| # | Algorithm | Implementation / owner | Complexity and bounds | Integration / current limitation |
|---:|---|---|---|---|
| 1 | Hash table/map | `Strategy/SignalDeduplicator.mqh` open-addressed secondary index | Expected O(L), worst O(L+1024); 1024 integer slots, max 512 records | Used for fingerprint lookup; serialized array remains authoritative; collision/tombstone/restore paths implemented. Not the execution-intent authority. |
| 2 | Binary search | `Core/Algorithms.mqh`; `Data/BarSeries.mqh::FindShiftByTime/AtTime` | O(log B), O(1) extra | Integrated with validated closed-bar series; exact timestamp only. |
| 3 | Min heap | `CQmeMinHeap` in `Core/Algorithms.mqh` | O(log n) push/pop; capacity 1..512 | Utility tested; not substituted into candidate ranking absent MT5 equivalence/performance data. |
| 4 | Quickselect | `CQmeAlgorithms::Quickselect` | Average O(n), worst O(n²), O(1) extra | Numeric array primitive; mutates its input; not used for production ranking. |
| 5 | Merge sort | `CQmeAlgorithms::StableMergeSort` | O(n log n), O(n) scratch | Stable numeric ascending sort; not replacing zone ranking because ties/order must match and benchmark is unavailable. |
| 6 | Interval tree | `CQmeIntervalTree` | Balanced query pruning with subtree max-upper; worst O(n), O(n) fixed storage, capacity 512; build currently O(n²) insertion ordering | Exact closed interval lookup and payload return; tested as utility, not yet owner index in ZoneBoard. |
| 7 | LRU cache | `CQmeLRUCache` | Bounded linear key lookup/eviction O(capacity), capacity<=128 | Exact string keys, finite values, explicit invalidation; useful cache primitive, not wired to market data (stale-data policy must be owner-specific). |
| 8 | Ring buffer | `Core/EventBus.mqh`, `Runtime/AlgoContainers.mqh::CQmeRing` | O(1) bounded push/pop; existing capacities fixed | Pre-existing QME implementation; no duplicate structure introduced. |
| 9 | Sliding window | `CQmeSlidingWindow` | O(1) push/mean; capacity<=128 | Rolling mean with overwrite; utility tests include eviction. Not yet used as a market feature. |
| 10 | Monotonic deque | `CQmeMonotonicDeque` | Amortized O(1) push/expire; capacity<=512 | Max or min mode, strictly increasing indices; test covers expiration/order. No swing detector replacement yet. |
| 11 | Prefix sums | `CQmeAlgorithms::BuildPrefixSum/PrefixRangeSum` | Build O(n), range O(1), O(n) storage | Half-open range, finite/overflow checks; numeric utility test. Not yet used by an analysis feature. |
| 12 | Welford | `CQmeAlgorithms::WelfordPush/WelfordVariance` | O(1) update/query, O(1) state | Used by `CPerformanceMetrics` for cumulative cycle-time sample deviation only; not trading input. |
| 13 | EWMA | `CQmeAlgorithms::EwmaPush`; consumed by `Monitoring/PerformanceMetrics.mqh` | O(1) update, O(1) state | Tracks cycle-latency diagnostic with alpha 0.2; no trading/volatility decision effect; recurrence test added. |
| 14 | Wilder smoothing | `CQmeAlgorithms::WilderPush` | O(1) update, O(1) state | Arithmetic seed then Wilder recurrence; platform ATR remains unchanged. |
| 15 | Two pointers | `CQmeAlgorithms::IntersectSorted` | O(n+m), output O(k) | Validates finite sorted inputs; preserves multiset duplicate intersection; not yet a production event matcher. |
| 16 | CUSUM | `CQmeAlgorithms::CusumPush` | O(1) update/state | Change flag resets accumulators; utility only, never an entry signal and not connected to scoring. |
| 17 | Sweep line | `CQmeAlgorithms::SweepMaxOverlap` | O(n log n) event sort plus O(n) scan; O(n) scratch | Closed intervals; starts precede ends at equal coordinate. Returns peak overlap, not candidate trades. |
| 18 | Union-find | `CQmeUnionFind` | Near O(α(n)) amortized; fixed capacity 512 | Path compression/rank/component size; not yet used to merge actual liquidity levels. |
| 19 | K-way merge | `CQmeAlgorithms::KWayMerge` | O(N log k), O(k+N) output | Heap merges validated sorted numeric streams; not yet wired to MTF event stream ownership. |
| 20 | Topological sort | `CQmeAlgorithms::TopologicalSort` | O(V²) using bounded adjacency matrix, V<=64; O(V²) input | Deterministic Kahn order, rejects cycles; current engine's static execution order remains unchanged. |

## Completion status

Source implementations are present for all 20 capabilities (the ring buffer predates this work); they remain unverified by the target compiler/runtime. Only fingerprint lookup, closed-bar timestamp lookup and Welford performance diagnostics currently have production call sites. The others are deliberately not substituted into QME trading/analysis paths until output equivalence, real MT5 compilation/runtime tests, and representative performance measurements pass. As a result, the user-requested *full production integration* is incomplete; this catalog does not label QME production-ready.
