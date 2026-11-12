# Complete project tree audit

**Audit date:** 2026-11-10. **Revision reviewed:** `f52ff27918bcefed06f923f46fa99e985c2f7012` plus the uncommitted audit report from the preceding turn. No source code changes have been made in this audit. Inventory is based on `git ls-files` and recursive source traversal; this document does not claim a full semantic manual review of every local variable in every function.

## Inventory

- 224 tracked files at the reviewed base revision; working directory also contains an ignored Python bytecode cache.
- 192 MQL sources: 170 `.mqh`, 22 `.mq5`; 43 files under `Tests/` (21 paired test programs and 21 suites plus `Tests/TestKit.mqh`).
- 27 tracked Markdown documents and one CSV in `Documentation/`.
- Major source domains: `Account` (6), `Analysis` (30), `Core` (15), `Data` (12), `Execution` (11), `Intelligence` (9), `Monitoring` (6), `Output` (9), `Persistence` (7), `Risk` (11), `Runtime` (8), `Strategy` (15), `Zones` (9), plus entry points, tests, tools and documentation. Counts include nested files as inventoried in the current checkout and should be regenerated if the tree changes.

## Directory responsibility and review result

| Directory / entry | Responsibility and important ownership | Audit disposition |
|---|---|---|
| `QME_Main.mq5`, `QME.mqh` | Terminal event entry/UI and umbrella include/composition | Inspected as integration boundary; actual MetaEditor compile not run. |
| `Account/` | Account mode, permission, broker/symbol constraints | Safety-critical; no trading/account mutations performed. |
| `Core/` | Types, config, constants, events, scheduling, logging/profiling | Static include/type checks pass. Event bus uses bounded ring. |
| `Data/` | Market clock, bars, quote sessions, history quality and indicators | Static path inspection; terminal data semantics require MT5 validation. |
| `Analysis/` | Market, structure, liquidity and price-action features | Feature pipeline inspected selectively; no claims that every formula was validated against market fixtures. |
| `Zones/` | Zone construction, lifecycle, ranking, selection | Bounded board and selection/sort paths inspected. |
| `Intelligence/` | Scoring, probability, calibration, causal/MtF reasoning | Architectural responsibility inferred from source/module names and include graph; no model-quality claim. |
| `Strategy/` | Candidate generation/merge, signal decision, identity/lifecycle/registry | Signal path reviewed at integration level; see dedicated lifecycle report. |
| `Risk/` | Portfolio, exposure, loss, pre-trade controls | Protected from changes; execution safety remains fail-closed by defaults. |
| `Execution/` | Validation, idempotency, broker requests, monitoring/reconciliation | No broker calls made; runtime/server behavior unverified. |
| `Persistence/` | Serialization, state stores, checkpoint/recovery | Static inventory only; fault injection and terminal recovery not run. |
| `Runtime/` | Scanner, engine, scheduler, controller and lifecycle | Scanner/engine call paths reviewed; broad dynamic review remains outstanding. |
| `Monitoring/`, `Output/` | Diagnostics/profiling and alerts/dashboard/explanations | Existing responsibilities inventoried; no profiling data collected. |
| `Tests/` | MQL5 unit/integration/regression/validation programs | Paired and static checks pass; MQL5 suites not executed here. |
| `Tools/` | Python source heuristics | Three static tools execute successfully; not a compiler. |
| `Documentation/` | Architecture, risk, deployment, audit and test records | Some pre-existing reports are historical and not treated as proof of current runtime behavior. |

## Lifecycle and data flow (high-level)

Terminal events enter `QME_Main.mq5` and route through the runtime engine/controller. The scanner synchronizes symbol/timeframe history, validates data quality, builds closed-bar contexts and analyses; those feed zones and MTF candidate collection/merging, then setup/scoring/signal validation and lifecycle/registry. Risk validation and execution modules gate any broker intent. Execution monitoring, transactions and reconciliation update state; persistence modules serialize/checkpoint and recovery restores state. Monitoring/output expose diagnostics. For exact include edges and architectural boundary notes see `ModuleDependencyMap.md` and the pre-existing `Documentation/DataFlow.md`, `Architecture.md`, `SignalLifecycle.md`, `ExecutionSpecification.md` and `RiskSpecification.md`.

## Structural findings / severity

- **High (release evidence gap, not asserted code defect):** MetaEditor compilation, MT5 runtime suites, broker simulation, persistence fault injection and representative performance profiling are not available in this run. Therefore DEMO readiness cannot be certified.
- **Medium (maintainability):** monitoring has a dependency on runtime containers, recorded as a low-level layer exception in `Documentation/DependencyAudit.md`; consider a future interface/ownership cleanup only if it can be isolated and regression-tested.
- **Medium (verification gap):** the static tools do not establish all variable lifetimes, MQL5 pointer semantics, or behavior under terminal/restart conditions. See variable and recovery reports.
- No source file was deleted as unused. No dead/unreachable implementation is claimed without runtime reachability evidence. Include-cycle absence is limited to the graph report's recorded analysis; no broad dead-code proof is made.

## Exact files

The authoritative recursively complete file list is `git ls-files` at the reviewed revision (224 tracked paths). This report deliberately summarizes the tree by responsibility rather than duplicating a brittle generated 224-line manifest. Re-run `git ls-files` to reproduce it. Full per-symbol/class and per-variable semantic audit is **not complete**; the requested deliverables are staged as audit status reports, not falsely complete attestations.
