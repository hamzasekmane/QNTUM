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
| D-020 | HIGH | No compilation/test/backtest evidence for the repaired tree | no MetaEditor/MT5 in the build environment | PARTIALLY CLOSED — `QME_Main.mq5` compiled 0/0 on 2026-11-10 (round 3); the 20 test programs, test execution, DEMO and backtest evidence still outstanding |
| D-021 | LOW | `Monitoring → Runtime/AlgoContainers` upward include | containers physically in Runtime | OPEN — relocation candidate to Core, not yet moved |
| D-022 | CRITICAL | `m_account.Snapshot().symbol` in Engine init log | `SAccountContext` has no `symbol` (accounts have login/server, not a symbol) | FIXED (round 2) — logs account login + server |
| D-023 | HIGH | `CRuntimeDiagnostics` called `CConfig::RealTradingEnabled()` on a const config | authorization accessors were non-const | FIXED (round 2) — `Demo/RealTradingEnabled`, `SessionAllowed`, `InBlackoutWindow` are now const (all read-only) |

## Rules for this register

- Nothing is marked "verified" without evidence (compiler log, executed
  test output). Static-checker passes are recorded as such, never as
  compilation.
- New defects are appended; fixed rows are never deleted.
