# Signal lifecycle reliability audit

## Traced lifecycle

The architectural route is market data → scanner/timeframe features → candidate collector/clusterer → setup/scoring and signal validation → deduplication/fingerprint checks → signal registry/lifecycle → engine decision and, only after separate safety gates, execution intent. Related code: `Runtime/Scanner.mqh`, `Strategy/MTF/*`, `Strategy/SetupEngine.mqh`, `Intelligence/ScoringEngine.mqh`, `Strategy/SignalEngine.mqh`, `Strategy/SignalDeduplicator.mqh`, `Strategy/SignalRegistry.mqh`, `Strategy/SignalLifecycle.mqh`, and `Execution/IdempotencyGuard.mqh` / `Execution/ExecutionGateway.mqh`.

Existing static regression checks cover repeated signal suppression, invalid candidate rejection, rejected fingerprint retry and unknown execution guard presence. Existing integration suites include repeated-signal and MTF pipeline cases. This is source/static evidence; MQL tests were not run.

## Identity separation and safety

Setup identity, evaluation revision, event ID and execution intent ID are distinct conceptual concerns. The source has signal fingerprints and execution idempotency components, but this audit does not assert a complete formal identity contract across registry eviction, restart and broker outcomes. A changed signal ID must never be assumed sufficient authority for a new broker submission. `Execution/` must reconcile existing positions/orders and unknown outcomes before retry; verify with broker simulation and restart tests.

Repeated unchanged scans must be tested for stable outputs and no duplicate executable intent; a new closed-bar evaluation can legitimately produce a new evaluation record without automatically creating a new order. Do not alter thresholds to hide duplicates. No implementation change was made because no verified lifecycle defect was reproduced in MT5.

## Remaining acceptance tests

Run `Tests/Regression/Test_RepeatedSignals`, previous-signal tests, MTF pipeline, execution failures and position recovery in MT5. Add/test same setup with new closed-bar revision, changed setup fingerprint, registry eviction, restart after submission, ambiguous broker response, existing position/order, and restored intent. Verify authorization revocation/PAUSED/FAULT prevents NEW entries while reconciliation/protective management continues as specified. Until these run, signal/execution idempotency is not certified.
