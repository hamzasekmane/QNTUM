# Advanced algorithm complexity report

This is source-level complexity and capacity analysis only. No MT5 compile/runtime timing was collected. Generic utilities are not automatically production integrations; see `AlgorithmIntegrationMap.md`.

| Algorithm | Implementation complexity | Memory / bounds | Current usage |
|---|---|---|---|
| Hash index | Expected O(L) including hashing, worst O(L+H), H=1024 probes | 1024 ints plus authoritative F<=512 records | Signal fingerprint lookup. |
| Binary search | O(log B) | O(1), existing closed-bar array | Bar time exact lookup, descending order required. |
| Min heap | O(log n) push/pop, O(1) peek not exposed | Fixed 512 doubles, configurable capacity<=512 | Utility only. |
| Quickselect | Average O(n), worst O(n²) | In-place O(1) | Utility only, input mutates. |
| Stable merge sort | O(n log n) | O(n) scratch | Utility only; numeric ascending sort. |
| Interval tree | Query prunes using subtree max-upper; worst O(n), build sorting O(n²) | Fixed 512 nodes | Utility only, payload query. |
| LRU cache | O(capacity) get/put/evict | Fixed <=128 strings/values/ages | Utility only; no stale market data used. |
| Ring buffer | O(1) enqueue/dequeue | Fixed existing capacities | Already used by event/sample buffers. |
| Sliding window | O(1) push/mean | Fixed <=128 values | Utility only; eviction subtracts outgoing sample. |
| Monotonic deque | Amortized O(1) push/expire | Fixed <=512 value/index pairs | Utility only; max or min mode. |
| Prefix sums | O(n) build, O(1) half-open range query | O(n) doubles | Utility only; detects non-finite cumulative sum. |
| Welford | O(1) push/variance | O(1) state | Cumulative cycle-time sample dispersion diagnostic. |
| EWMA | O(1) update | O(1) state | Cycle-time diagnostic, alpha 0.2; no trading consumer. |
| Wilder | O(1) update after O(period) seed | O(1) state | Utility only; platform ATR not replaced. |
| Two pointers | O(n+m), output construction O(k) | O(k) output | Validates sorted finite inputs; multiplicity-preserving intersection. |
| CUSUM | O(1) update | O(1) positive/negative accumulators | Utility only; no entry use. |
| Sweep line | O(n log n) event sort + O(n) scan | O(n) event/scratch arrays | Returns max overlap of closed intervals. |
| Union-find | Near O(α(n)) amortized | Fixed <=512 parent/rank/size arrays | Utility only. |
| K-way merge | O(N log k) | O(k) heap/cursors plus O(N) output | Validates sorted finite streams. |
| Topological sort | O(V²) bounded adjacency matrix | V<=64; O(V²) input, O(V) output | Utility only; current engine schedule unchanged. |

Performance is **NOT VERIFIED**. The hash benchmark harness is present but uncompiled/unrun. No claim of speedup is made; capacities and asymptotic bounds do not establish a real bottleneck or improvement.
