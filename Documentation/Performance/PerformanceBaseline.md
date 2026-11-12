# Performance baseline

**Status: NOT MEASURED.** No MT5 terminal or MetaEditor profiler run was performed in this environment. Recording invented latency, memory, call counts, or cache ratios would be misleading.

## Static workload bounds (not a timing baseline)

- Event ring capacity: 512.
- Event dispatch sinks: 16.
- Signal registry: 64; signal fingerprints: 512.
- Zone capacities: up to 96 per timeframe and 512 per symbol in current source review.
- Candidate capacity: 32; runtime history: 256.
- Scanner volume profile call: up to 200 bars × 24 buckets.

## Measurement protocol needed

On a pinned MT5 terminal/build and fixed history snapshot, measure full timer cycle and sections around history synchronization, indicator reads, per-timeframe feature analysis, zone prune/select, candidate merge/scoring, persistence and event dispatch. Use `GetMicrosecondCount()` with low-overhead counters, collect call count, total/mean/median/p95/max and processed sizes/occupancy. Separate warm-up, terminal history loading, and steady state; repeat on representative single- and multi-symbol/timeframe workloads. Measure baseline and candidate builds using same inputs and compare decision/output fingerprints. Record terminal/build, symbol specs, input settings and CPU environment. Memory profiling must state exactly which MT5 metrics are observable.

No source profiling instrumentation was added: without a runtime measurement harness, instrumentation itself would be unvalidated and could perturb hot paths. Existing `Core/Profiler.mqh` and `Monitoring/PerformanceMetrics.mqh` are present, but their usage/configuration has not been measured here.
