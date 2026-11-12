# Runtime benchmark report — Phase 2

**Status: BLOCKED — no MT5 runtime profiler.** No measured timing, memory usage, cache hit rate, call count, or before/after comparison is available. No performance claim is made.

Required workloads include fingerprint lookup, candidate collection/ranking, zone lookup, historical data access, multi-timeframe calculations, event scheduling and persistence, across stated symbol/timeframe counts and representative data/occupancies. The prior static bounds (for example zones up to 512, candidates 32, event capacity 512) are not runtime measurements.

The current Python static suite is not a benchmark. No optimization was introduced. Run identical fixed inputs/builds on a pinned MT5 terminal and record build, hardware, symbols/timeframes, bars, candidates/zones, calls, total/mean/median/p95/max microseconds, and memory metric methodology. Include warm-up separation and output fingerprint equivalence. Native timing must be instrumented in the actual MQL5 runtime; report instrumentation overhead separately. Until then performance acceptance is unmet.
