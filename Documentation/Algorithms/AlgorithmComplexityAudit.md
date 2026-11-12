# Algorithm complexity audit

Complexities below are source-level bounds, not observed runtime. Costs depend on actual counts, terminal calls and execution frequency. No strategy threshold or signal semantics changed.

| Path | Purpose / input-output | Complexity and memory | Failure/bottleneck notes |
|---|---|---|---|
| `SignalRegistry` | Find/manage signal records | Linear lookup O(S), bounded S=64 in reviewed limits; O(S) storage. | Small upper bound; duplicate fingerprint/rejection semantics must remain exact. |
| `SignalDeduplicator` | Fingerprint cooldown and pruning | Linear O(F), F<=512; O(F). | Hashing is not justified without measured lookup dominance and stable deletion/recovery semantics. |
| `ZoneBoard` | Add/update/search/prune zones | Linear searches O(Z); prune retains and sorts kept values; selection-sort O(Z²), Z<=512; temporary O(Z). | Worst-case sorting comparisons 130,816 for Z=512; theoretical only. Score computation and call frequency unmeasured. |
| `TopZones::Select` | Select side-compatible highest-ranked zones | Full board traversal O(Z), insertion/ordered top-N work up to O(ZN); output O(N). | Heap could help if N and occupancy repeatedly large; no representative evidence. Preserve deterministic ties. |
| `CandidateClusterer` | Merge bounded candidate evidence | Candidate collection bounded at 32; pair/merge loops are bounded by candidate count (inspect implementation before changing). | No workload profile; prevent claims that this dominates. |
| `VolumeProfile::Build` | Map bars into price buckets | O(BK), B<=200, K=24 => <=4,800 bar-bucket units in reviewed call; O(K) profile plus bounded scratch. | Small fixed bound; verify volume/bucket edge cases in MQL tests. |
| `BarSeries` extrema/averages | Closed-bar window calculations | O(W) per query; space O(1). | Incremental rolling cache risks stale/future/forming-bar semantics. |
| Structure/price-action detectors | Closed-bar feature extraction | Primarily bounded scans over configured scan bars; detailed per-function operation counts not gathered. | Runtime cost must be profiled; formulas require fixture-level correctness tests. |
| IndicatorCache `Value`/series | Read indicator handle buffers | CopyBuffer volume O(shift) for Value, O(count) for series plus temporary/output arrays; terminal-call cost dominates and isn't captured by Big-O. | Readiness/copy failure returns false. Cache needs explicit closed-bar/config invalidation. |
| EventBus | Bounded FIFO | O(1) enqueue/dequeue on fixed ring capacity 512; O(512) storage. | Appropriate existing ring; overflow policy should remain tested. |
| EventDispatcher | Sink dispatch | O(E) per dispatch, E<=16. | Tiny bound. |
| `RuntimeMemory` | Bounded history find/update | O(H), H<=256; O(H). | Hash index unlikely to justify extra persistence/rebuild complexity absent evidence. |
| Persistence serialization/recovery | Encode/decode records | Generally linear in serialized records/bytes; precise bounds and atomicity not validated here. | High reliability impact; requires corruption/interrupted-write testing. |
| Scanner | Multi-symbol/timeframe scan | Scales with symbols × timeframes × analyses; each analysis invokes multiple bounded detectors and terminal data calls. | Highest likely aggregate-cost surface; no profiling baseline, so no prioritization claim beyond profiling first. |

## Algorithm/data-structure decision

No implementation was changed because measured frequency/latency data and MT5 runtime are unavailable. Full selection/lookup edge suites, including duplicates, empty/full capacity, invalid indices and deterministic ordering, have not been run in MQL5. See `DataStructuresOptimizationPlan.md` and performance reports.
