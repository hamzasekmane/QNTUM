# QME algorithm and data-structure audit

> Historical audit snapshot. The subsequent `AdvancedAlgorithmsCatalog.md` records a later fingerprint hash-index implementation; this document's original no-change decision applied before that implementation and is preserved for history.

**Scope:** source-level audit of algorithm/data-structure candidates in the current QME checkout, with a decision on whether an optimization is justified. No trading logic or execution/risk controls were changed. This is not a complete semantic review of every one of the 224 tracked files; it is a targeted audit of the algorithmic hotspots and call paths identified in QME's scanner, data, zone, signal, and runtime-memory layers.

## Decision

**No algorithm/data-structure optimization implemented.** The repository contains no reproducible workload benchmark for these paths, and this environment cannot run MetaTrader 5 / MetaEditor MQL5 runtime benchmarks. A Python microbenchmark would not measure MQL5 array, terminal `CopyBuffer`, or indicator behavior and would be misleading. Current fixed capacities are mostly small and bounded, making asymptotic improvements alone insufficient evidence. Preserve current semantics until representative MT5 measurements demonstrate a bottleneck.

No public interfaces, signal/trading semantics, thresholds, risk controls, SL/TP validation, execution protections, or allocation behavior were modified. There are therefore no claimed runtime or memory improvements and no before/after performance numbers.

## Repository and flow reviewed

The checkout contains 224 tracked files (192 MQL5 source units including paired tests). Relevant flow: `Runtime/Scanner.mqh` refreshes symbol/timeframe data and builds analyses; indicator values flow through `Data/IndicatorCache.mqh` and `Data/TimeframeContext.mqh`; analyses feed zone, candidate, scoring, and signal paths. Runtime bounded collections include `Core/EventBus.mqh`, signal registries/deduplicator, zone board, and runtime memory. Relevant callers located by repository search include `ZoneEngine` calling zone prune/select and `Runtime/Engine` pruning terminal signals.

The scan path performs broad market-analysis work on each scan, including volume-profile and price-action analysis; reducing an individual bounded lookup without profiling the total scan is not proven worthwhile. No caching change was made because freshness/invalidation semantics are material to market data.

## Candidate assessment

| Area and implementation | Current cost / bounds | Assessment |
|---|---|---|
| Hash tables / ID lookup: `SignalRegistry`, `SignalDeduplicator`, `ZoneBoard`, `RuntimeMemory` | Linear lookup, with respective capacities reported in source/call-path review: 64 signals, 512 fingerprints, 512 zones, 256 history entries. | No hash table justified absent measured lookup dominance. Hashing adds state, collision behavior, invalidation and memory overhead at these bounds. |
| Binary search | No identified hot path maintaining sorted data with a stable ordering invariant. | Not applicable to unsorted registries/maps; adding sorting solely for lookup would add maintenance cost and potentially alter ordering. |
| Heap / priority queue: `Zones/TopZones.mqh` | Scans all zones and maintains the selected top-N; bounded zone board up to 512. | Heap can reduce selection work for large N, but N and actual board occupancy/workload were not measured. Keep deterministic tie/order behavior unchanged. |
| Memoization/cache: `Data/IndicatorCache.mqh` | Indicator handles persist; `Value`, `AtrSeries`, and `RsiSeries` call `CopyBuffer`; series allocate output and temporary arrays. | Potential repeated terminal calls/allocations, but changing to per-bar cache requires precise bar/time invalidation and readiness behavior. No evidence of repeated identical queries or measured cost. |
| Sliding windows: `Data/BarSeries.mqh`, analysis engines | Highest/lowest and averages traverse bounded bar windows. `VolumeProfile` builds over at most 200 bars and 24 buckets (bounded work up to 4,800 bar-bucket checks). | Could be a profiling target; incremental windows risk stale/incomplete-bar semantics and numerical drift. No benchmark showing benefit. |
| Sorting: `Zones/ZoneRanking.mqh` / `ZoneBoard::Prune` | Selection sort O(n²) on retained zones, n <= 512; prune also builds a temporary kept array. | Worst-case comparison bound at 512 is 130,816 comparisons (n(n-1)/2), but that is a theoretical bound, not observed runtime. The call frequency/occupancy and cost of score calculations are unknown; do not replace without equivalence and MT5 timing. |
| Dynamic arrays / queues: `Core/EventBus.mqh` | Fixed-capacity circular FIFO (512); bounded sinks (16). Several local scratch/output arrays resize in bounded analysis paths. | Event queue is already an appropriate constant-time bounded ring; no dynamic queue replacement warranted. Scratch allocations are potential profiling targets but no repeated allocation cost was measured. |
| Signal cleanup: `SignalRegistry::RemoveTerminalOlderThan` | Linear scan over a small bounded registry (64). | O(n), but bounded and not a demonstrated bottleneck. |

## Complexity and benchmark status

Since no change was accepted, there is no before/after complexity reduction to report. Existing representative bounds above are static source bounds, not performance measurements. No benchmark timing, memory profile, or functional equivalence comparison is claimed. A valid follow-up benchmark should execute in MetaTrader 5 on a fixed terminal/build, symbol/timeframe history fixture and fixed scan schedule; report repeated-run median and tail latency, memory/allocations if observable, occupancy/counts, and output fingerprints for the unchanged analysis results. Include empty, duplicate, maximum-capacity, invalid-index and reset/reinitialization cases before considering a data-structure change.

## Verification performed

- `python3 test_system.py`: **45/45 passed**. These are repository static checks, not MQL5 runtime tests.
- `python3 Tools/mql5check.py`: no structural errors detected; explicitly not a compiler proof.
- `python3 Tools/mql5fields.py`: 0 suspicious member accesses (heuristic).
- `python3 Tools/mql5calls.py`: 0 arity mismatches (heuristic).
- MT5/MetaEditor compilation and MQL5 unit/integration execution were not available/performed here. No algorithm-specific runtime benchmark or collection edge-case runtime test was added because no implementation changed.
- Safety defaults remain analysis-only ON, demo/real trading OFF, and real arming OFF (covered by static tests).

## Remaining work / limitations

1. Collect representative MT5 profiler traces before selecting an optimization; record symbol count, timeframe count, bars, zone occupancy and scan cadence.
2. Measure repeated `CopyBuffer` and scratch allocation costs before designing a cache or reusable buffer; define invalidation and preserve closed-bar indexing/readiness behavior.
3. If zone sorting is shown hot, compare current order against a replacement on identical fixtures, including equal scores, empty/singleton/full capacity, and pruning boundaries.
4. Run the paired MQL5 tests and compile in MetaEditor; passing Python static checks alone does not prove MQL5 compilation or runtime correctness.

The release/readiness status is unchanged; this audit does not imply trading readiness or profitability.
