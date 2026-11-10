# Defect Register — QuantumMarketEngine

> Opened 2026-11-10 from the first MetaEditor compilation log
> (101 errors, 27 warnings). Severity: CRITICAL = blocks compilation or
> unsafe; HIGH = wrong behaviour likely; MEDIUM = localised defect;
> LOW = warnings/hygiene. "Fixed" means repaired in source and passed the
> three static checkers; it does **not** mean compile-verified — that
> requires the next MetaEditor log (see CompilationReport.md).

| ID | Severity | Defect | Root cause | Status |
|---|---|---|---|---|
| D-001 | CRITICAL | ~45× "invalid index value" across 19 files | capacity limits were `const int` globals, not compile-time constants | FIXED — all capacities are `#define` |
| D-002 | CRITICAL | `Zones/ZoneMerger.mqh` included but nonexistent | stale umbrella include; merging lives in `CZoneBoard::AddOrMerge` | FIXED — include removed |
| D-003 | CRITICAL | Unqualified `LiquidityMap.mqh` include | wrong relative path | FIXED — `../Liquidity/LiquidityMap.mqh` |
| D-004 | CRITICAL | `CEngine::Init(const SInputs &input …)` | `input` is a reserved keyword | FIXED — parameter renamed `in` |
| D-005 | CRITICAL | `SAccountContext* Ptr()`, `SSymbolSpec* SpecPtr()`, `STradingZone* PtrAt()` | MQL5 forbids pointers to structures | FIXED — removed; copy-out APIs (`Snapshot`, `SpecInto`, `At`/`ById`) are the interface |
| D-006 | CRITICAL | `CAccountContext::State()` declared twice | duplicated line | FIXED |
| D-007 | CRITICAL | `CPositionStateStore::At` declared `int`, defined `bool` | signature drift | FIXED — `bool` both sides (callers already treat it as bool) |
| D-008 | CRITICAL | `CRetryPolicy::DelayMs` declared 2-arg, defined 3-arg | an earlier edit landed on the definition only | FIXED — declaration carries `baseMs = 250` default |
| D-009 | HIGH | `MqlTradeTransaction.time` read in 5 places | the struct has no `time` field | FIXED — `TimeCurrent()`, refined to `DEAL_TIME` from history |
| D-010 | HIGH | `trans.symbol` cast to `long` in a log line | `symbol` is a string | FIXED |
| D-011 | HIGH | `ActiveCount` called on const zone engine | method not const | FIXED — const on `CZoneBoard`/`CZoneEngine` (read-only) |
| D-012 | HIGH | Scanner assigned a `const` timeframe array; `SLiquidityLevel` possibly uninitialised | declaration/usage mismatch | FIXED — non-const array; level field-initialised |
| D-013 | HIGH | `CHistoryValidator` array params (`*ctxs[]`, `const tfs[]`) | MQL5 arrays are reference-only, never const | FIXED — `&ctxs[]`/`&tfs[]` + bounds check |
| D-014 | MEDIUM | Aggregate init of `SStructureEvent[3]` | MQL5 has no such initialiser | FIXED — three explicit checks |
| D-015 | MEDIUM | `COrderManager::Send` missing return path | loop-only exits | FIXED — defined failure result after the loop |
| D-016 | LOW | 27 shadow warnings (`magic`, `minRR`, `maxRetries`, …) | input globals shared names with parameters | FIXED — all 57 inputs renamed `Inp*` |
| D-017 | LOW | long→int / ulong→long / double→int conversion warnings | implicit narrowing | FIXED — explicit int clamp, ulong size, `(int)` mode cast |
| D-018 | MEDIUM | `mql5check.py` include-resolution check was vacuous | includes collected from string-blanked text | FIXED (previous session) — raw-text collection, probe-verified |
| D-019 | MEDIUM | Nine helper classes not on the runtime path | implemented library code, deliberately unwired (behaviour change unverifiable here) | OPEN — documented in Phase0_Audit §8; wire only with compile+DEMO evidence |
| D-020 | HIGH | No compilation/test/backtest evidence for the repaired tree | no MetaEditor/MT5 in the build environment | PARTIALLY CLOSED — `QME_Main.mq5` compiled 0/0 on 2026-11-10 (round 3); the 21 test programs, test execution, DEMO and backtest evidence still outstanding |
| D-021 | LOW | `Monitoring → Runtime/AlgoContainers` upward include | containers physically in Runtime | OPEN — relocation candidate to Core, not yet moved |
| D-022 | CRITICAL | `m_account.Snapshot().symbol` in Engine init log | `SAccountContext` has no `symbol` (accounts have login/server, not a symbol) | FIXED (round 2) — logs account login + server |
| D-023 | HIGH | `CRuntimeDiagnostics` called `CConfig::RealTradingEnabled()` on a const config | authorization accessors were non-const | FIXED (round 2) — `Demo/RealTradingEnabled`, `SessionAllowed`, `InBlackoutWindow` are now const (all read-only) |
| D-024 | CRITICAL | Runtime crash `array out of range` (FvgEngine:97) when the first FVG was found | `CFvgEngine::Detect`/`COrderBlockEngine::Detect` called `ArrayResize` on a caller-owned **fixed-size** struct-member array (`SMarketAnalysis::fvgs[8]`/`orderBlocks[8]`); the resize fails silently and the subsequent index is out of range | FIXED — detectors never resize; capacity = min(maxOut, ArraySize(out)), writes bounded by it; regression suite `Test_FvgSafety` |
| D-025 | HIGH | Test_Execution: analysisOnly did not yield the config reason | the hard config block was evaluated last in `CExecutionValidator::Local`, after market/geometry refusals that fire first on live prices | FIXED — analysisOnly is now the first check; multi-fault precedence test added |
| D-026 | HIGH | Deduplicator restore tests failing | (a) `Deserialize` loaded malformed lines as time=0 (block-forever) records and wiped held state on garbage; (b) two test files encoded wrong semantics (second fingerprint never registered; expected a restarted cooldown; expected a just-fired signal free after restart) | FIXED — scratch-parse with per-line rejection (no timestamp/empty/duplicate), state only replaced by a valid document; tests corrected to the documented semantics and strengthened (remaining-cooldown + post-expiry + malformed-sibling cases) |
| D-027 | HIGH | `CEntryRig::FromZone` produced `rr = 0` and accepted inverted zones | `rr` was never assigned; zone edges were silently repaired with MathMax/MathMin | FIXED — inverted/degenerate zones refused with `QME_REJ_INVALIDATED` and a precise note; targets normalized; `rr` derived from the actual normalized entry/stop/target |
| D-028 | MEDIUM | Test_Risk expected 1.00/0.33 lots, engine produced 0.50/0.16 | test expectations implied a 5 USD pip value; its own mock spec (tickValue 1.0 / tickSize 0.00001, 20-pip stop) loses 200 USD/lot, so 0.50/0.16 is correct | TEST CORRECTED with the derivation recorded; engine audited and unchanged; added metals-spec, coarse-step and minimum-above-budget cases. Risk was NOT increased to meet the old expectation |
| D-029 | HIGH | Test_Expiry: a direct `Check` expired an EXECUTED signal | `Check` exempted only terminal states; EXECUTED is live-but-post-execution and reached the time check (the registry path filtered states separately, which is why its assertion passed) | FIXED — `Check` and `Process` now share one rule: only DETECTED/EVALUATING/APPROVED/EXECUTION_PENDING can expire |
| D-030 | MEDIUM | `CMssEngine::IsConfirmed` could never return true | it additionally required `state.lastEvent`, a field no producer ever sets; the confirmation flag was dead | FIXED — the flag is authoritative; the scanner now syncs `mssConfirmed`/`mssSide`/`lastEvent` from the detected MSS event so state stays consistent |
| D-031 | MEDIUM | Test_Zones merge assertions failing | test used the production 60% threshold on geometry overlapping 50% of the smaller zone (the documented metric) — no merge is the correct behaviour there | TEST CORRECTED to the documented metric (merges at 40%) and extended: 60% gate refuses, containment keeps the outer envelope, duplicate insertion is idempotent; merged zones now also carry `merged = true` |
| D-032 | MEDIUM | Entire test-suite execution was unrecorded | results existed only in chat | FIXED — `Documentation/TestResults.md` opened as the evidence log; repair-round re-runs are NOT TESTED until executed |

## Rules for this register

- Nothing is marked "verified" without evidence (compiler log, executed
  test output). Static-checker passes are recorded as such, never as
  compilation.
- New defects are appended; fixed rows are never deleted.
