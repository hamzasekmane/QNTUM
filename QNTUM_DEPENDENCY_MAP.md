# QNTUM dependency map (as wired in source)

## Entry and composition
- `QME_Main.mq5` is the only EA entry point: declares inputs/globals and handlers `OnInit`, `OnDeinit`, `OnTick`, `OnTimer`, `OnTradeTransaction` (see lines 325-398). It maps inputs to `SInputs`, initializes engine and output/monitoring components.
- `QME.mqh` (includes around lines 20-161) is the translation-unit composition root: includes Core, Data, Account, Analysis, Zones, Intelligence, Strategy, Risk, Execution, Persistence, Runtime, Monitoring, Output in dependency order. Headers are implementation-bearing MQL include files, not separate linkable modules.
- `test_system.py` invokes Python structural heuristics and checks source strings/defaults/test pairing; it does not compile or execute MQL algorithms.

## Module boundaries, public interfaces and owned state

| Module | Primary boundary / public interface | Main state and flow |
|---|---|---|
| Core | Enums/types/constants/config, logger, event bus/dispatcher/scheduler, funnel/history guards/profiler, utility hashing/path helpers. Most modules depend on it. | Inputs normalized by `CConfig`; shared event/diagnostic types. `QmeScopedStateName` in `Core/Utils.mqh:170-175`. |
| Account | Account mode, snapshot, equity/loss state, symbol specs, broker capabilities, margin and permissions. `CAccountContext` used by Engine, Risk, Gateway. | Broker-derived account and per-symbol constraints; account loss state serialized in `[ACCT]`. |
| Data | Symbol market-data acquisition, ticks, bars, timeframe contexts, indicators, history/data-quality/synchronization, clock/session and profiles. | `CMarketData` serves scanner; `CTickProcessor` caches tick; `CTimeframeContext` owns `CBarSeries` and indicator handles. Scanner owns the per-symbol five-slot contexts. |
| Analysis | Factor catalog and analysis subpackages (including liquidity outcomes). Called from scanner/build-analysis; computes factor outputs, not broker I/O. | Analysis structs are per-symbol/per-TF in `CSymbolRuntime.analysis[]`. |
| Zones | Zone types/identity/validation/lifecycle/ranking/building/board/engine/top-zones. | Per-symbol `CZoneEngine`, refreshed by scanner from setup/entry analysis. |
| Intelligence | Priors, adaptive weights, probability, causal checks, scoring, MTF confluence, calibration, signal quality and outcome analysis. | Scoring/calibration state; used by strategy and signal decision layers. Some learning/outcome state is persisted via RuntimeMemory/history; verify per class before persistence changes. |
| Strategy | MTF entry rig/collector/clusterer/engine/plan lifecycle; setup, signal types/lifecycle/registry/dedup/expiry, strategy registry, signal and decision engines. | Candidate/plan/signal lifecycle, daily/cooldown limits, dedup; Engine drives decisions. |
| Risk | Budget, daily loss, drawdown, consecutive losses, portfolio/exposure/correlation, spread/session/news, pretrade and risk engine. | Current account/portfolio risk checks invoked before Gateway; per-trade plan and risk state are runtime-owned. |
| Execution | Request builder/validator, journal/monitor, reconciliation, idempotency, order manager, gateway, transaction handler, trade manager. | Gateway is new-entry pipeline and persistence pre-send claim; `COrderManager::Send` calls entry `OrderSend`; TradeManager independently handles SLTP/close requests. |
| Persistence | State serializer/store, runtime memory, position/signal stores, checkpoint manager, recovery composer/parser. | Common Files `QME` folder. Engine composes one document; gateway saves in-flight intent immediately before entry request; Engine periodically/finally checkpoints unless blocked. |
| Runtime | Containers, scanner, scheduler, canonical snapshot/replay, RuntimeController, ShutdownManager, Engine. | Engine orchestrates initialization, cycles, scans, decisions, risk, execution, maintenance, shutdown. Scanner owns symbol runtime array and scan diagnostics. |
| Monitoring | Error tracking, performance/execution statistics, health monitor, runtime diagnostics, watchdog. | Main/Engine supply current state and events; watchdog/health can report critical/warn independently of EA initialization. |
| Output | Alert ports/guard/engine/binding, explanations, dashboard, visualization. | `QME_Main` globals bind to engine state and render/log; presentation is not execution authority. |
| Tests | 23 MQL5 test programs (.mq5 paired with .mqh), `TestKit.mqh`. | MQL tests require MetaEditor/MT5. Python suite only verifies static source conditions and tooling. |
| Tools | `mql5check.py`, `mql5fields.py`, `mql5calls.py`. | Heuristic scanners; report no compiler guarantee. |
| Documentation | Existing architecture, risk, execution, testing, audit and deployment notes. | Design intent and prior audits; not authoritative over current implementation. |

## Actual high-level data/control flow
1. MT5 events in `QME_Main.mq5` call Engine (`OnTick` / timer) and transaction handler (`OnTradeTransaction`); diagnostics/alerts/dashboard sample engine and account state.
2. Engine account refresh and RuntimeController/recovery gates precede scan/decision paths. With recovery blocked, code can perform safe signal preview only under analysisOnly=true and all demo/real/armed switches false (`Runtime/Engine.mqh:748-764`); checkpoint writes are suppressed while recovery is blocked (`:384-390`).
3. Scheduler marks a scan; Scanner refreshes symbol contexts and market data, builds analysis per timeframe, marks `tfReady`, runs quality checks over all five configured timeframes and checks tick freshness (`Runtime/Scanner.mqh:324-432`). `snapshot.dataValid` is the final combined result.
4. Signal/setup/decision pipeline consumes valid snapshots and produces signal/plan; risk engine and execution validation gate new entries.
5. ExecutionGateway validates/builds request, performs request risk revalidation, claims idempotency key, writes pre-send checkpoint, then calls OrderManager (`Execution/ExecutionGateway.mqh:222-275`). Unknown outcomes remain in-flight and require reconciliation (`:282-295`).
6. Position management is a parallel broker-operation path: Engine invokes TradeManager to tighten SL or close opposite position (`Runtime/Engine.mqh:543-553,565-592`); TradeManager directly calls `OrderSend` for SLTP/close (`Execution/TradeManager.mqh:110,211`).
7. Checkpoint composition serializes `[ACCT] [POS] [SIG] [DEDUP] [IDEM] [MEM]` (`Persistence/StateRecovery.mqh:80-95`); StateStore writes `.tmp`, flushes/closes, then moves with rewrite (`Persistence/StateStore.mqh:82-124`).

## State ownership and cross-module coupling
- Market tick cache: Data/MarketData + per-symbol TickProcessor; read by scanner and risk/market guards.
- Bars/indicator handles: each `CSymbolRuntime.ctx[]` / `.series[]`; released on scanner shutdown.
- `tfReady[]`, analysis, snapshot and quality: owned by `CSymbolRuntime`, mutated by `RefreshSymbol`; signal/monitoring consumers rely on it.
- Scanner metrics `m_lastAnalysed`, `m_lastDataValid`, `m_scans`, `m_failures`: owned by Scanner; `valid` in `Describe` is recomputed from snapshots rather than copied counter.
- Signal lifecycle/dedup: strategy/Engine; dedup persisted by Recovery.
- Position state: Engine's `CPositionStateStore` and broker are dual sources; `PositionReconciler`/Recovery reconcile, broker state is authoritative for stale positions.
- Idempotency claims: ExecutionGateway owns live guard; serialized checkpoint and trade journal both record related facts. Journal is forensic, checkpoint is recovery authority.
- Durable checkpoint writes have two callers: Engine periodic/final checkpoint and ExecutionGateway pre-send intent checkpoint. Both target the same CCheckpointManager/StateStore. Engine deliberately does not write when recovery-blocked.
- TradeManager direct OrderSend duplicates low-level broker-call responsibility with OrderManager; current observed call sites are position protection/close, not a second new-entry pipeline.

## Dependency observations / unresolved assumptions
- Include order is mostly layered but headers contain inline implementations and may rely on earlier includes; static include scanning does not prove independent compilation or acyclic class-level dependencies.
- Runtime Engine is a broad composition root and owns orchestration across all subsystems; this is deliberate coupling but increases review surface.
- Session/clock work crosses Data, Risk, Scanner and Output; server/GMT and tick time must not be assumed interchangeable.
- Current source scoped filename is `qme_<login>_<hash(server)>_<magic>.txt`. A previously supplied log filename includes a date-like value and lacks an obvious matching component; runtime binary/source provenance remains unresolved.
- Some directories contain nested source not all enumerated by `QME.mqh` directly; include closure pulls these through module headers. `Documentation`, `Tests`, and `Tools` are not runtime dependencies.
