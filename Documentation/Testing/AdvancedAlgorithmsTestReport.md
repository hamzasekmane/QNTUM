# Advanced algorithms test report

**Status:** source implementations for all 20 capabilities are present (ring buffer pre-existed). `Tests/Unit/Test_HashIndex` and `Tests/Unit/Test_AdvancedAlgorithms` contain deterministic MQL5 test code. **None of these MQL5 suites has been compiled or executed** because MetaEditor/MT5 is unavailable. Do not treat their assertions as passing.

| Validation type | Status |
|---|---|
| Static repository suite | 49/49 passed after changes; checks source structure, safety invariants and paired-program presence, not algorithm outputs. |
| Algorithm unit programs | Hash: collisions, misses, cooldown, prune, persistence rebuild, capacity/eviction. Toolkit: binary search exact/empty/boundary; Welford reference variance, large offset and overflow; quickselect, merge sort, min-heap, prefix sums, interval tree, LRU, EWMA, Wilder, CUSUM, two-pointer intersection, sliding window, monotonic deque, union-find, topological sort, K-way merge and sweep-line representative fixtures. **Written, not executed.** |
| End-to-end QME integration | Hash lookup, bar time lookup and Welford monitoring have production call sites. Most remaining toolkit functions are not wired into market/candidate/zone/MTF production paths. No end-to-end equivalence suite yet. |
| MetaEditor compilation | BLOCKED — compiler unavailable. |
| MT5 runtime tests | BLOCKED — terminal unavailable. |
| Performance comparisons | NOT MEASURED — a hash benchmark harness exists but is uncompiled/unrun; no other baseline harness/results. |

Important coverage still needed before acceptance: randomized/property tests against reference implementations, full capacity and wraparound for each bounded container, LRU clock normalization boundary, monotonic deque wraparound/capacity, interval-tree worst-case shapes, merge-sort allocation failure, CUSUM sustained shifts and reset semantics, k-way duplicate tie ordering, topology invalid matrix dimensions, and exact production-output equivalence. Test CUSUM remains diagnostic-only; no test should route it to an entry.

No existing test assertion was removed or weakened. The static 49/49 result is not MQL5 compilation, runtime execution, or performance proof.
