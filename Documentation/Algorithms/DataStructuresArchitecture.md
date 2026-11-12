# QME data structures architecture and implementation status

## Existing production owners

- `Core/EventBus.mqh`: fixed-capacity FIFO ring; bounded event ordering remains unchanged.
- `Runtime/AlgoContainers.mqh`: bounded string/ticket lists and `CQmeRing`; the numeric ring holds at most 128 samples.
- `Strategy/SignalDeduplicator.mqh`: authoritative fixed fingerprint/time/ID arrays and ring eviction; a 1024-int open-addressed secondary index accelerates lookup. The index is rebuilt after prune/deserialize; strings are compared after hash matches. Persistent records remain the authority.
- `Strategy/SignalRegistry.mqh`: bounded signal records and current lifecycle/eviction semantics unchanged.
- `Zones/ZoneBoard.mqh`: current zone ownership and lifecycle unchanged. No new interval index has been made authoritative there.
- `Data/BarSeries.mqh`: descending closed-bar array. New exact `FindShiftByTime`/`AtTime` binary lookup requires the validated order contract.
- `Monitoring/PerformanceMetrics.mqh`: existing rolling timings remain; Welford sample dispersion and EWMA cycle latency add diagnostics only.

## New bounded algorithm toolkit (`Core/Algorithms.mqh`)

Contains deterministic numeric primitives, binary time lookup, heap, quickselect, stable merge sort, augmented balanced interval tree, bounded LRU, sliding window, monotonic deque, prefix sums, Welford, EWMA, Wilder smoothing, two-pointer intersection, CUSUM, sweep-line overlap, union-find, k-way merge, and topological sort. The pre-existing event/sample ring remains in its prior owner rather than duplicated.

Bounds and ownership are explicit: heap<=512, interval tree<=512, cache<=128, sliding window<=128, monotonic deque<=512, union-find<=512, topological graph<=64; caller-owned dynamic output arrays are reset on failure where implemented. The utility tests in `Tests/Unit/Test_AdvancedAlgorithms` check representative numerical, ordering, duplicate, capacity and invalid-bound cases.

## Integration boundary / limitations

Only hash fingerprint lookup, BarSeries time lookup and Welford performance diagnostics currently have production callers. The remaining utilities are not yet wired into zones, candidate ranking, liquidity clustering, MTF scheduling or feature caches. They are not permission to change strategy behavior. In particular, LRU is not used for market data; CUSUM does not generate entries; Wilder does not replace terminal ATR; union-find does not cluster liquidity; topological sort does not replace the fixed engine schedule.

No native MetaEditor compile/runtime run is available. Therefore these source implementations and their MQL tests are not certified as working until a Windows MT5 environment compiles and executes them. Performance remains unmeasured.
