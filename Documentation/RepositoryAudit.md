# Repository Audit — QuantumMarketEngine

> Date: 2026-11-10. Method: recursive inspection of actual file contents
> (not the original listing), plus the three static checkers in `Tools/`.
> Baseline compiler evidence: the first MetaEditor compilation of
> `QME_Main.mq5` (user-supplied log, 2026-11-10): **101 errors, 27 warnings**.

## 1. Inventory

| Measure | Count |
|---|---|
| MQL5 source files scanned by `Tools/mql5check.py` | 188 (all implemented, 0 empty) |
| Documentation files (before this audit set) | 10 |
| Classes (incl. the `IQmeEventSink` interface) | 146 |
| Test programs | 20 (18 suites + `TestKit.mqh` + wrappers counted by layer scan) |
| Empty source files | **0** |
| Broken `#include` paths | **0** (after the ZoneMerger/LiquidityMap repair) |
| Duplicate class definitions | 0 |
| Duplicate method definitions | 0 (one legal overload, `CPortfolioSnapshot::CountFor`) |

Layer file counts: Core 15, Data 11, Account 7, Analysis 29, Zones 9,
Intelligence 9, Strategy 15, Risk 11, Execution 11, Persistence 7,
Runtime 8, Monitoring 6, Output 7, Tests 21 (incl. harness), root 2
(`QME.mqh`, `QME_Main.mq5`).

## 2. Findings by severity

See `DefectRegister.md` for the full register. Summary of what the first
real compilation exposed (grouped by root cause, not by file):

| # | Root cause | Files affected | Severity |
|---|---|---|---|
| RC-1 | Capacity limits declared as `const int` globals; MQL5 array sizes must be compile-time constants | 19 files, ~45 errors | CRITICAL |
| RC-2 | Pointers to structures (`SSymbolSpec*`, `SAccountContext*`, `STradingZone*`) — illegal in MQL5 | 3 files | CRITICAL |
| RC-3 | Duplicate/conflicting method signatures (`State()`, `At()`, `DelayMs`) | 3 files | CRITICAL |
| RC-4 | Reserved keyword `input` used as a parameter name in `CEngine::Init` | Engine | CRITICAL |
| RC-5 | Umbrella header included a nonexistent file (`Zones/ZoneMerger.mqh`) | everything via `QME.mqh` | CRITICAL |
| RC-6 | `MqlTradeTransaction.time` does not exist | TransactionHandler | HIGH |
| RC-7 | Non-const method called on a const object (`ActiveCount`) | Engine/ZoneEngine | HIGH |
| RC-8 | `const` local array assigned after declaration; possibly-uninitialised struct | Scanner | HIGH |
| RC-9 | Array parameters without reference syntax / declared `const` | HistoryValidator | HIGH |
| RC-10 | C-style aggregate initialisation of a struct array | CausalValidator | MEDIUM |
| RC-11 | Missing return path (`COrderManager::Send`) | Execution | MEDIUM |
| RC-12 | All 57 terminal inputs shadowed function parameters (27 warnings) | QME_Main + many | LOW |
| RC-13 | Avoidable numeric-conversion warnings (long→int, ulong→long, double→int) | 3 files | LOW |

## 3. Dependency problems

- Include graph is acyclic at layer level except two upward edges worth
  noting (see `DependencyAudit.md`): `Data/SymbolProfile` includes
  `Account/SymbolSpecifications` (data layer reading account-layer spec
  loading — accepted, specifications are symbol metadata), and
  `Monitoring/PerformanceMetrics` includes `Runtime/AlgoContainers`
  (containers physically live in Runtime; a candidate for relocation to
  Core, recorded as a LOW architectural note, not changed in this round).
- `CHistoryValidator` had no callers (still true after repair; its
  signature is now compilable). Recorded in the defect register as a
  known disconnected module, together with the eight other library-only
  helpers listed in `Phase0_Audit.md` §8.

## 4. Unimplemented / disconnected

- No empty method bodies or placeholder returns were found by inspection
  in the repaired files; classes not on the runtime path are listed in
  `Phase0_Audit.md` §8 with reasons (documented library code, not stubs).
- Declared-but-never-defined check (mql5check): clean.

## 5. Critical architectural risks

1. **No compilation evidence exists yet for the repaired tree** — the
   baseline log is from before the repair; a fresh MetaEditor log is the
   only acceptable proof (see `CompilationReport.md`).
2. The compiler stopped at 101 errors; latent errors beyond that cap are
   expected and will be handled from the next log (round 2).
3. Fixed-capacity arrays everywhere: behaviour at capacity (event queue,
   funnel, registry) is drop-oldest/reject-with-reason by design, but it
   has never been exercised at runtime.
