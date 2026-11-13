# QNTUM root-cause report — Phase 1 (read-only)

**Scope/evidence:** static inspection on branch `arena/f6fb8d86-qntum` (base named in Arena note), available Python/static checks, and runtime excerpts previously supplied in this conversation. No MetaEditor or MT5 terminal is available. Raw logs in the prompt's placeholder were empty; earlier conversation excerpts are used where explicitly noted. Findings are not a production-readiness verdict.

## Findings (highest risk first)

### QME-AUD-01 — Legacy unscoped state intentionally blocks clean start
- **Module/severity/evidence:** Persistence + Runtime; HIGH; **CONFIRMED** source path, runtime log matches.
- **Locations:** `Runtime/Engine.mqh:258-277,279-288,344-370`; `Core/Constants.mqh:53`; `Core/Utils.mqh:168-175`.
- **Observed:** logs report legacy `qme_state.txt` and missing scoped state, then `recovery=BLOCKED`, `runtime FAULT`; shutdown skips final checkpoint when recovery is blocked (`Engine.mqh:308-317`).
- **Expected:** never silently discard possible unresolved state; require reconciliation. Current code does this deliberately.
- **Root cause / trace:** scoped target is built from login + hash(server) + magic (`Utils.mqh:170-175`), legacy file is separately detected (`Engine.mqh:262`); if persistence enabled, scoped state absent, and legacy exists, flag is set (`266-271`). `RestoreState()` logs clean only for absent scoped file (`344-359`), but fault is still latched (`279-288`). Saves are suppressed while blocked (`Engine.mqh:384-390` and deinit 309-317). Thus “starting clean” does not cancel the prior critical legacy-state finding. This matches the supplied log; no evidence is available to determine what the legacy file contains.
- **Dependencies:** account/server/magic scope, checkpoint, idempotency state, positions, runtime controller, health.
- **Correction proposal:** none without operator reconciliation and approval. Do not delete, import, rename, overwrite, or bypass state. Add reconciliation evidence and a documented operator resolution path only after design review.
- **Regression:** simulated matrix for legacy present/absent × scoped present/absent × valid/corrupt, asserting no writes or entry execution while blocked and no destructive file operations.
- **Verification:** static trace + logs from user. Live state contents and broker reconciliation **NOT VERIFIABLE HERE**.

### QME-AUD-02 — Checkpoint identity is in filename, not authenticated in payload
- **Module/severity/evidence:** Persistence; HIGH; **CONFIRMED** source.
- **Locations:** `Core/Utils.mqh:168-175`; `Persistence/StateRecovery.mqh:80-95,119-143`; `Runtime/Engine.mqh:258-277,362-375`.
- **Observed:** a file selected by the scoped pathname is accepted based on format version and section structure; payload does not carry account/server/magic identity.
- **Expected:** validate payload identity against the live account/server/magic before applying state.
- **Root cause / trace:** pathname embeds login, hashed server and magic; `Compose` writes version + ACCT/POS/SIG/DEDUP/IDEM/MEM sections, with no account/server/magic field; `Apply` checks version and ordered section markers and then applies account, positions, etc. A misplaced/copied/renamed file with valid shape is not identity-bound by payload. Whether an attacker/operator can place such file is environmental; mismatch protection is therefore incomplete at file-content level.
- **Dependencies:** account state, positions and order idempotency.
- **Correction proposal:** add explicit identity fields to a future schema and reject mismatch before mutating any target; preserve current files and maintain versioned compatibility with operator reconciliation.
- **Regression:** wrong login/server/magic payload must be rejected without mutating any in-memory store; matching identity passes.
- **Verification:** static source trace; no MQL runtime test.

### QME-AUD-03 — Partial restore may mutate some stores before later section failure
- **Module/severity/evidence:** Persistence; HIGH; **CONFIRMED** source behavior.
- **Locations:** `Persistence/StateRecovery.mqh:128-143,144-162,164-200`; `Runtime/Engine.mqh:362-370`.
- **Observed:** `Apply` validates section markers first, then incrementally deserializes account, positions, history, dedup and intents. Some later failures return `loaded=false` after earlier objects have already been mutated (e.g. invalid IDEM at 184-191); Engine sets recovery blocked but has no rollback.
- **Expected:** either validate into temporary objects then commit atomically, or guarantee rollback on any failure.
- **Root cause:** validation is structurally partial rather than transactional. The report specifically confirms invalid intent records can fail after account/positions/history/dedup have been applied.
- **Dependencies:** recovered risk baseline and in-flight orders; blocked engine reduces immediate entry risk, but in-memory state remains partially restored and diagnostics can be misleading.
- **Correction proposal:** parse/validate into isolated temporary state; apply only once all sections and invariants pass. Do not weaken recovery lock.
- **Regression:** corrupt each section in turn; assert failure leaves every live state object byte-for-byte/logically unchanged.
- **Status after Phase 2 work:** fixed in source by preflighting account, positions, history, dedup, idempotency and runtime-memory sections into isolated temporary objects before any live deserialize; malformed late sections that make a deserializer fail now reject before the live stores are changed. MQL regression added.
- **Remaining limitation:** several legacy deserializers tolerate malformed rows if at least one valid row is present, so preflight does not prove strict whole-document semantic validation; no claim of complete corruption detection.
- **Verification:** source-level regression and Python static checks pass; MQL regression not run because MetaEditor/MT5 unavailable. Status: **fixed but not verifiable here**.

### QME-AUD-04 — Filename in supplied log does not match current source naming
- **Module/severity/evidence:** Build/deployment + Persistence; HIGH; **SUSPECTED** runtime binary/source mismatch.
- **Locations:** supplied log reports `QME\\qme_52959880_1635298256_20261110.txt`; current `Core/Utils.mqh:170-175` returns `qme_<login>_<server-hash>_<magic>.txt`, and `Runtime/Engine.mqh:260-263` uses it.
- **Observed:** supplied filename appears to contain account, an integer (possibly server hash or magic), and date; current source has account, server hash, magic, no date. Its format is not the current `QmeScopedStateName` contract.
- **Expected:** running EX5 and source revision should agree on state format and path.
- **Root cause:** not provable from logs alone; likely different/older compiled EX5, different branch/revision, or mistaken filename interpretation. Integer `1635298256` resembles a timestamp but could be other identity data; do not infer.
- **Dependencies:** actual file searched/read, whether reported missing state is the expected file, recovery.
- **Correction proposal:** first identify exact EX5 build/hash, source revision, Inputs, Common Files path and full filenames; no file movement or deletion. Confirm source-to-binary provenance before remediation.
- **Regression/verification:** in terminal, log exact computed state path/build revision and compare with Common Files listing, without altering files.

### QME-AUD-05 — Scanner summary counters have different semantics and can contradict
- **Module/severity/evidence:** Data + Monitoring; MEDIUM; **CONFIRMED** source semantics; user logs show example.
- **Locations:** `Runtime/Scanner.mqh:295-321,325-432,591-606`; `Runtime/Engine.mqh:802`.
- **Observed:** `m_lastAnalysed` is incremented only when `snapshot.dataValid` is true, and `m_lastDataValid` is incremented in the same branch (`303-305`), then both receive the same count (`315-316`). In the summary, `valid` is recomputed from current snapshots (`593-602`) while last counts are from the last completed scan. These can differ after invalidation, before first scan, on refresh failure, or between scans; labels imply separate meanings.
- **Expected:** define “analysed” as refresh/analysis completed separately from fully data-valid, with freshness/time of measurement explicit; `valid` should identify same epoch or be named currentSnapshotValid.
- **Root cause:** conflated count definitions and mixing current snapshot state with last-scan counters. `Scan()` returns true after refresh even if no symbol has a valid snapshot (`321`); return value means refresh completed, not market valid.
- **Dependencies:** dashboard, watchdog, HealthMonitor, signal gating.
- **Correction proposal:** document and split counters/epochs; preserve strict per-symbol validity gates. Do not interpret `valid=4` alone as recovery healthy.
- **Regression:** complete scan with mix of success/data-quality-block/not-ready; refresh failure; summary before any scan; verify each named count and scan epoch.
- **Verification:** static trace; logs show `valid=4 scans=1 lastAnalysed=4 lastDataValid=4`, consistent for that scan but not proof across failure cases.

### QME-AUD-06 — Per-symbol `tfReady` means analysis build succeeded, not raw data completeness
- **Module/severity/evidence:** Data pipeline; MEDIUM; **CONFIRMED**.
- **Locations:** `Runtime/Scanner.mqh:324-348,361-418`; `Data/TimeframeContext.mqh:132-187`.
- **Observed:** `CTimeframeContext::Refresh()` sets raw `m_dataValid` from series validity, then separately indicator readiness. But it returns `m_dataValid && m_indicatorReady` (`187`). Scanner checks `ctx.Refresh()`, `ctx.Ready()`, series refresh, and `BuildAnalysis`; only after all succeed does it set `tfReady=true` (`338-348`). Later snapshot validity requires every TF `tfReady`, fresh quality validation, plus fresh tick (`399-423`). Therefore a source-looking-healthy timeframe can be `tfReady=false` due indicator/analysis readiness; that is not necessarily erroneous. Conversely `tfReady=true` alone is not sufficient proof of data quality.
- **Expected:** labels distinguish acquisition, synchronization, indicator readiness, analysis readiness, and quality.
- **Root cause:** a single “ready” concept spans multiple layers; no evidence of a definite incorrect per-symbol validity verdict from source alone.
- **Dependencies:** scanner diagnostics, signals, dashboard.
- **Correction proposal:** observability refinement only after agreeing on semantics; do not reduce gates.
- **Regression:** staged fixtures for history ready/indicators pending/analysis failure/quality failure/stale tick.
- **Verification:** static trace. User log at 12:04 shows 4 valid and one scan; no contradiction in the excerpt itself.

### QME-AUD-07 — Tick freshness compares tick timestamp to trade-server clock
- **Module/severity/evidence:** Data; MEDIUM; **CONFIRMED** implementation, runtime offset issue **SUSPECTED**.
- **Locations:** `Data/TickProcessor.mqh:140-152`; caller `Runtime/Scanner.mqh:419-423`.
- **Observed:** age is `TimeTradeServer() - tick.time`, rejecting zero/future times and age above configured 300 seconds. This is not local processing time and not `TimeCurrent()`.
- **Expected:** same broker-time basis or normalized timestamp basis, with clear behavior on clock skew/market closure.
- **Root cause:** no explicit offset/clock sanity telemetry in the freshness function. A future tick is rejected; differences between tick timestamp and server time can cause false stale/future decisions. Cannot confirm the supplied runtime had such skew.
- **Dependencies:** snapshot validity and signal gating.
- **Correction proposal:** add diagnostic clock deltas and runtime evidence before changing the rule; maintain fail-closed behavior.
- **Regression:** zero, future, exactly-at-limit, limit+1, server-clock offset, disconnected terminal.
- **Verification:** static only; supplied 12:04 excerpt has valid=4, not a failing tick case.

### QME-AUD-08 — Two direct `OrderSend` call sites outside the declared sole order manager
- **Module/severity/evidence:** Execution; HIGH design concern, **CONFIRMED** call graph; no confirmed new-entry bypass.
- **Locations:** `Execution/OrderManager.mqh:2-3,46-60`; `Execution/TradeManager.mqh:34-124,152-220`; callers `Runtime/Engine.mqh:543-553,565-592`; gateway path `Execution/ExecutionGateway.mqh:236-275`; engine recovery gates `Engine.mqh:748-764`.
- **Observed:** `OrderManager.mqh` claims it is the only `OrderSend()` site, but TradeManager directly sends SLTP modifications and position closes. These calls are position-management paths, not new order entries, and are distinct from `ExecutionGateway`'s new-entry `OrderSend`.
- **Expected:** comment/interface reflects all broker trade calls; management calls must remain available to protect positions while entries are blocked, but remain scoped to owned/reconciled positions and explicit controls.
- **Root cause:** duplicated broker API responsibility/documentation. Static call graph shows `ManagePositions` and `CloseOppositePositions` invoke TradeManager; exact outer guards and ownership policy need full runtime testing; no basis to call it an unguarded new-entry bypass.
- **Dependencies:** execution audit, position protection, emergency pause.
- **Correction proposal:** first document/verify ownership and authorization invariants; if approved, centralize or accurately distinguish entry-vs-position-management APIs without suppressing protection.
- **Regression:** mock calls proving every new entry traverses ExecutionGateway validations/idempotency/checkpoint; management only changes tracked owned position; analysis-only/recovery-blocked prevents entries but preserves allowed protection.
- **Verification:** static call-site trace; no MT5 execution.

## Runtime symptoms from prior user logs
- 11:58 excerpt: deinit reason 3; no trades/exec sends; reinit detected legacy state, then `FAULT` and `recovery=BLOCKED`; `signal-preview=OFF`; stale health alert. This is consistent with AUD-01, not proof that state is safe to discard.
- 12:04 excerpt: scanner moved to `scans=1 valid=4 lastAnalysed=4 lastDataValid=4 failures=0`; signal preview emitted rejects; `trades=0 exec built=0 sent=0`; `checkpoint-old` remains, and recovery is still blocked. Signal rejects are strategy/filter outcomes, not execution or recovery failures.
- Earlier D1 gap context was from another branch/log sequence; current source contains a higher-timeframe historic-gap window implementation on that prior merged lineage, but it is not diagnosed from this later M15 excerpt.

## Open questions requiring user/terminal evidence
1. Exact current EX5 build/version/hash and source commit; full Common\Files\QME directory listing (names, sizes, timestamps only initially).
2. Backup of `qme_state.txt` and exact path; never upload credentials. Broker account/server/magic confirmation; open positions/orders/deals and unresolved intents export to reconcile.
3. On terminal: enable detailed diagnostic output only if safe; capture initialization through first full scan, exact computed state path, runtime status transitions, tick server time and tick time, each timeframe series/indicator readiness and quality result.
4. MetaEditor compile logs and MT5 test-suite output for every `.mq5` test; no compile/runtime claims are made here.
