# Data structures and optimization plan

## Decision

No new hash map, binary-search index, heap, memoization cache, sliding-window accumulator or dynamic queue was introduced. There is no measured bottleneck that establishes benefit; bounded simple arrays are easier to audit and preserve deterministic behavior at current capacities.

| Candidate | Current pattern | Trigger to reconsider | Required correctness conditions |
|---|---|---|---|
| Hash index for signals/zones | Linear bounded arrays (signals 64, zones/fingerprints up to 512) | Profile shows lookup accounts for material scan latency at normal occupancy. | Collision resolution, stable canonical key, delete/reuse, eviction, rebuild on restore, identical duplicate semantics. |
| Binary search | No identified sorted invariant for all queried arrays | Data owner can maintain sorted order cheaply and profiling shows lookup dominates. | Insert/delete ordering, duplicate keys, invalid indices, synchronization with persistence. |
| Heap for top-N zones/candidates | One-pass selection/insertion on bounded set | Large repeated N-selection and large occupancy; compare against full sort and current partial insertion. | Stable deterministic tie-breaking and exact output equivalence. |
| Indicator/feature cache | Persistent indicator handles; CopyBuffer on read | MT5 profile demonstrates repeated same closed-bar/config request cost. | Key includes symbol, timeframe, bar time, periods/config; invalidate on new bar/history reset/config change; never serve stale values. |
| Sliding windows | Repeated bounded bar scans | Measured repeated overlapping scans dominate. | Closed-bar causality, startup warmup, gap/history correction reset, exact tolerance equivalence. |
| Sort/selection | Selection sort for zone ranking | Measured prune/rank cost dominates with realistic occupancy. | Exact score/tie order, stable semantics, empty/duplicate/all-equal/full-boundary tests. |
| Ring buffers | EventBus already bounded circular FIFO; other records bounded arrays | Only if actual queue workload requires different capacity/policy. | FIFO/order, overflow handling, reset, no drop of safety-critical reconciliation events. |
| Persistent index | Records serialized and scanned/rebuilt as needed | Recovery/startup profiling proves material issue. | Record/index atomic consistency, schema versioning, index rebuild and fail-closed corruption policy. |

For each future optimization, record an MT5 baseline and changed build on identical fixture/config, compare output fingerprints and run functional boundary tests. Python benchmarks do not substitute for terminal timing. No memory/performance improvement is claimed in current work.
