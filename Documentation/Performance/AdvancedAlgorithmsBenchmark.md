# Advanced algorithms benchmark

**Status: NOT MEASURED; one secondary hash index integrated, all other candidates deferred.** MetaEditor/MT5 is not installed in the execution environment, so native MQL5 timing, allocation behavior and terminal data costs cannot be measured. Python timings would not represent the production runtime and are intentionally omitted.

| Workload | Existing baseline | Candidate | Before/after result |
|---|---|---|---|
| Fingerprint lookup | Not measured; prior bounded linear scan | 1024-slot secondary open-addressed index now implemented | N/A — native before/after still required; optimization not performance-verified |
| Candidate collection/ranking | Not measured | heap/quickselect/merge sort | N/A |
| Zone lookup/top-N | Not measured; bounded scan/insertion | hash/interval tree/heap | N/A |
| Historical data and MTF calculations | Not measured; terminal API plus closed-bar scans | cache/sliding/prefix/deque | N/A |
| Event scheduling | No benchmark; fixed ring/scheduler | K-way merge / alternate queue | N/A |
| Persistence | No benchmark | index/cache | N/A |

## Required native protocol

Record terminal and MetaEditor exact builds, hardware, compiler target, symbol/timeframe count, history span, exact fixture hash, data structure occupancy, operation/call counts, repeated-run mean/median/p95/max, and memory/allocation metric methodology. Benchmark old and new implementations in the same MT5 run/build with deterministic inputs and output digests. Include small, normal, large and worst-case datasets, repeated operations, empty/duplicate/full boundaries, and profiler overhead. Keep the old implementation unless a representative measured improvement exceeds noise without functional or memory regression.

A native MQL5 harness has been added at `Tools/Benchmarks/Benchmark_SignalHash.mq5` to compare indexed membership and a linear reference at 512 records with hit/miss queries, recording elapsed microseconds and output mismatches. It has **not** been compiled or run; no benchmark values or speedup claims are supplied. It is a single-run microbenchmark scaffold and requires warm-up/repeated runs and terminal metadata before acceptance.
