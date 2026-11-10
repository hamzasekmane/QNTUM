# QuantumMarketEngine — Architecture

> Status: implemented. 184 source files, all non-empty. Structural verification:
> `python3 Tools/mql5check.py` → `OK: no structural errors detected`.
> **No compiler was available in the build environment** — see `DeploymentGuide.md`
> for the exact MetaEditor steps and the honesty policy about compilation.

## 1. Design goals

1. **One strategy, two environments.** The same pipeline runs on DEMO and REAL.
   Nothing about *how* a trade is chosen changes with the account type; only
   *whether* the trade is allowed to be sent changes, and that decision is
   isolated in one place (`CTradingPermissions` + `CExecutionGateway`).
2. **Nothing is silently dropped.** Every refusal produces an `ENUM_QME_REJECT`
   reason and a human sentence, stored in the signal history and shown on the
   dashboard.
3. **The broker is the source of truth.** Positions are read from the terminal
   on every cycle; nothing is remembered from the previous cycle. State files
   are an optimisation for restart, never an authority.
4. **Conservative defaults.** Every trading switch defaults to `false`.
   `analysisOnly = true` ships enabled.

## 2. Layering

```
                 +------------------------------------------+
   QME_Main.mq5  | inputs, MQL5 event handlers, globals     |
                 +--------------------+---------------------+
                                      |
                 +--------------------v---------------------+
   Runtime       | CEngine (orchestrator)                   |
                 | CScanner (analysis factory)              |
                 | CScheduler, CRuntimeController            |
                 | CCheckpointManager, CStateRecovery        |
                 | CReplayEngine, CShutdownManager           |
                 +--------------------+---------------------+
                                      |
   Strategy ----> Decision ----> Risk ----> Execution ----> Broker
                                      |
   Intelligence (scoring, confluence, quality, calibration)
                                      |
   Analysis (market / structure / liquidity / price action)
                                      |
   Zones  |  Data  |  Account  |  Core
```

Dependency direction is strictly downward. Consequences:

* `Risk/` never includes `Strategy/`; the plan is rebuilt inside the risk engine.
* `Execution/` never includes `Strategy/`; it receives a plan.
* `Output/` and `Monitoring/` are leaves: they read state, they never change it.
* `Core/` includes nothing outside itself.

## 3. The cycle

`CEngine::Cycle()` runs this sequence, and only this sequence:

| # | Step | Component | Failure behaviour |
|---|------|-----------|-------------------|
| 1 | Account refresh | `CAccountContext` | cycle aborts, controller → FAULT |
| 2 | Scan due? | `CScheduler` | cycle returns without work |
| 3 | Market scan | `CScanner` | cycle aborts with a note |
| 4 | Session evaluation | `CSessionEngine` | session marked invalid |
| 5 | Trade permission | `CRuntimeController::MayTrade` | signals are recorded as DEFERRED |
| 6 | Signal generation | `CSignalEngine` | funnel counters record the refusal |
| 7 | Decision + risk | `CDecisionEngine` → `CRiskEngine` → `CPreTradeValidator` | rejection reason recorded |
| 8 | Execution | `CExecutionGateway` | state recorded, signal → EXECUTION_FAILED |
| 9 | Book-keeping | history, replay, execution statistics | — |
| 10 | Signal maintenance | `CSignalExpiry`, `CEngine::MaintainSignals` | terminal records pruned to history |
| 11 | Checkpoint | `CCheckpointManager` | logged, never fatal |

`MaintainSignals` also promotes an `EXECUTED` signal to `MONITORING` once its
position exists at the broker, so the registry mirrors reality rather than
intent. `ManagePositions` (timer tick, and only when `breakEvenAtR > 0`) tightens
protection; see `ExecutionSpecification.md` §7.1.

A cycle can therefore *not* trade without steps 5–8 all succeeding, and each of
those steps can only ever refuse.

## 3.1 Instrumentation

Three observers run alongside the cycle and never influence a decision:

* `CFunnel` — per-stage counters plus a per-reason rejection tally. It is why
  every refusal can be answered with "how many, and why".
* `CProfiler` — opt-in (`profileCycles`), section timings for the cycle; the
  report goes to the log at shutdown and into `Status()` while enabled.
* `CCanonicalSnapshot` — a per-symbol digest of the analysed state (price, ATR,
  bias, session, zone count). Identical inputs must produce an identical
  digest, which is what makes two runs comparable without replaying ticks.
  Written at debug level.

## 4. Component inventory

| Folder | Files | Responsibility |
|--------|-------|----------------|
| `Core/` | 15 | constants, enums, POD types, utils, errors, logger, events, config |
| `Data/` | 11 | bar series, contexts, indicators, quality guard, synchroniser, clock, profiles |
| `Account/` | 7 | mode detection, specs, state, broker capabilities, margin, permissions |
| `Analysis/` | 32 | market, structure, liquidity, price action + factor catalogue |
| `Zones/` | 9 | identity, validation, lifecycle, merge, ranking, board, engine |
| `Intelligence/` | 9 | priors, adaptive weights, probability, causality, scoring, confluence, calibration, quality, outcomes |
| `Strategy/` | 14 | MTF candidates, setups, entry rig, signal generation, registry, dedup, expiry, decision |
| `Risk/` | 11 | budget, guards, portfolio, exposure, correlation, spread/session, news, validator, engine |
| `Execution/` | 11 | retry policy, idempotency, request building, validation, journal, monitor, reconcile, send, transactions, trade management |
| `Persistence/` | 7 | serializer, atomic store, checkpoint, position/signal/history stores, recovery |
| `Runtime/` | 8 | containers, scanner, scheduler, snapshot, replay, controller, shutdown, engine |
| `Monitoring/` | 6 | errors, performance, execution stats, health, diagnostics, watchdog |
| `Output/` | 7 | alert ports/guard/engine/binding, explanations, dashboard, visualisation |
| `Tests/` | 18 programs | unit, integration, regression, validation |

## 5. Event and state ownership

* `CEventLedger` — append-only ring of significant events (lifecycle changes,
  refusals, executions). Owned by `CEngine`, attached to `CSignalLifecycle`.
* `CSignalRegistry` — live signals only, bounded by `QME_MAX_SIGNALS`.
  Terminal records are evicted after being written to history.
* `CPositionStateStore` — which positions belong to this magic, for restart.
* `CReplayEngine` — bounded ring of decisions, audited for rule violations.

## 6. Why MQL5 shaped the design

| MQL5 constraint | Consequence in this codebase |
|-----------------|------------------------------|
| No multiple inheritance | single-inheritance hierarchies; interfaces are plain virtual classes (`CAlertPort`) |
| No function pointers | policy objects (`CRetryPolicy`) and callbacks through class methods |
| No forward visibility of free functions | helpers are defined above their first user; deliberate ordering inside headers |
| `static const` members illegal | `const`/`#define` constants live in namespace scope |
| Structs with `string` cannot live in fixed arrays | those collections use dynamic arrays (`ArrayResize`) |
| `ZeroMemory` only on POD | used only on request/result structs |
| No STL | `Runtime/AlgoContainers.mqh` provides bounded lists and a numeric ring |

## 7. What this architecture deliberately does not do

* **No martingale, grid, averaging or revenge logic.** There is no code path
  that increases volume after a loss.
* **No widening of protective stops.** `CTradeManager::ModifyProtection` refuses
  any move that would widen a stop, and logs the refusal.
* **No hidden retry loops.** Retries are capped, delayed, and forbidden after an
  ambiguous answer until reconciliation has run.
* **No fabricated market data.** Missing history produces `SKIP`/invalid
  analysis, never synthetic bars.
