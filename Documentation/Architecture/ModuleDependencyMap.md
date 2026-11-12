# Module dependency and ownership map

**Evidence:** include scan and repository tools on current checkout; pre-existing `Documentation/DependencyAudit.md` contains the generated layer-edge summary and class inventory. A counted include edge is not automatically a runtime call edge.

## Dependency layers

```text
QME_Main.mq5 → QME.mqh / Runtime composition root
Runtime → Core, Account, Data, Analysis, Zones, Intelligence, Strategy,
          Risk, Execution, Persistence, Monitoring, Output
Data → Core (+ Account symbol metadata)
Analysis → Core + Data
Zones → Core + Data + Analysis
Intelligence → Core + Analysis
Strategy → Core + Intelligence + Account + Analysis + Zones + Risk
Risk → Core + Account (+ Data)
Execution → Core + Account
Persistence → Core + serialized Strategy/Execution records
Monitoring → Core + Account + Execution + Runtime (one coupling exception)
Output → Core + Strategy decision views
```

The umbrella include order recorded in `Documentation/DependencyAudit.md` is Core → Account → Data → Analysis → Zones → Intelligence → Strategy → Risk → Execution → Persistence → Runtime → Monitoring → Output. That report finds no layer-level include cycles. Current static verifier reports zero structural/include errors and local include targets resolve. Do not interpret this as proof there are no runtime dependency cycles or hidden global coupling.

## Ownership and flow

| Data / decision | Primary owner | Flow and consumers |
|---|---|---|
| Market clock and quotes/history | `Data/MarketClock`, `MarketData`, `BarSeries`, `DataSynchronizer` | Runtime scanner → timeframe contexts / guards → analysis. |
| Per-symbol/timeframe derived context | `Data/TimeframeContext`, `IndicatorCache` | Scanner and analysis engines; indicators are terminal handles with explicit release. |
| Market feature records | `Analysis/*` and shared records in `Core/Types.mqh` | Scanner → zone and MTF reasoning. |
| Zones | `Zones/ZoneBoard`/`ZoneEngine` | ranking and top-zone selection → strategy/analysis consumers. |
| Candidate hypotheses | `Strategy/MTF/CandidateCollector`, `CandidateClusterer` | Setup/scoring and validation. |
| Signal records and fingerprints | `Strategy/SignalRegistry`, `SignalDeduplicator` | lifecycle/decision → engine/runtime; execution idempotency is a separate execution concern. |
| Risk decisions | `Risk/*` | Pre-trade validation is a mandatory gate before execution request. |
| Execution intents and broker state | `Execution/*` | request construction/gateway → transaction/monitor/reconcile. Unknown outcomes require reconciliation. |
| Durable state | `Persistence/*` | engine checkpoint/recovery; isolation and compatibility need runtime tests. |
| Events and diagnostics | `Core/EventBus`, `EventDispatcher`; `Monitoring/*` | listeners/sinks and output; EventBus uses fixed bounded FIFO. |

## Coupling and unresolved verification

`Runtime/Engine` is the composition root and naturally depends on many modules. Strategy's risk dependency is documented as plan validation. Persistence serializes strategy/execution records by design. Monitoring's `PerformanceMetrics` dependency on runtime containers is a maintainability exception already identified in the dependency audit. No files are designated duplicate/obsolete or safe to remove; proving that requires full call graph including dynamic dispatch, includes, event sink registration, and MQL5 entry behavior.

The static scan counted 872 include directives over MQL source inputs (repeat includes count separately), with no unresolved local includes. Counts and prior class inventory may become stale when files change. Variable ownership, all function call edges, runtime reachability and restart behavior remain partially audited; see `VariableConfigurationAudit.md`, `SignalLifecycleAudit.md`, and `PersistenceRecoveryAudit.md`.
