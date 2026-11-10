# QuantumMarketEngine — Execution Specification

## 1. The only authorized path

```
STradePlan ⟶ CExecutionGateway::Execute ⟶ MqlTradeRequest ⟶ OrderSend
```

Nothing else may create a new order. `CTradeManager` may only modify SL/TP or
close, and it refuses to widen a stop.

## 2. Gateway pipeline

| Step | Component | Refusal |
|---|---|---|
| 1 | `CIdempotencyGuard::CanExecute` | `DUPLICATE_SIGNAL` |
| 2 | `CTradingPermissions::Authorize` (independent of the decision) | permission/config reason |
| 3 | `CTradeRequestBuilder::Build` | `INTERNAL` (illegal geometry) |
| 4 | `CExecutionValidator::Full` (local + `OrderCheck`) | mapped reason |
| 5 | `CIdempotencyGuard::Begin` | `DUPLICATE_SIGNAL` |
| 6 | `COrderManager::Send` | retcode → reason |
| 7 | `CPositionReconciler` if ambiguous | `EXECUTION_FAILED` / reconciled |
| 8 | Journal + monitor | — |

`OrderCheck` is used deliberately: it asks the server whether the request would
be accepted **without sending it**.

## 3. Request building

* market entry: `TRADE_ACTION_DEAL`, price from the live ask/bid, deviation
  `InpDeviationPoints`;
* pending entry: `TRADE_ACTION_PENDING` with `BUY_LIMIT`/`SELL_LIMIT`; a limit
  already through the market is refused (it is a market order in disguise);
* `sl` and `tp` are mandatory and validated for side;
* `type_filling` comes from the symbol's reported mask;
* `magic` and comment identify the engine.

## 4. Retry policy

| Broker answer | Class | Behaviour |
|---|---|---|
| `DONE`, `PLACED`, `DONE_PARTIAL` | success | proceed |
| `REQUOTE`, `PRICE_CHANGED`, `PRICE_OFF` | transient | retry after backoff, up to `InpMaxRetries` |
| `TOO_MANY_REQUESTS` | transient | retry with a longer delay |
| `TIMEOUT`, `CONNECTION` | ambiguous | **never retried**; reconcile first |
| everything else | permanent | fail with the mapped reason |

Backoff: `250 ms × {1, 2, 3}` (1000 ms base for rate limiting). No unbounded loop
exists.

## 5. Idempotency

Per fingerprint: `NONE → IN_FLIGHT → EXECUTED | FAILED`. Only `NONE` and
`FAILED` may execute. The table is persisted, so a restart cannot re-fire an
intent that already executed. When the table is full and holds no `FAILED`
record, the guard refuses rather than evicting live state.

## 6. Ambiguity

A `TIMEOUT` means *unknown*, not *failed*. The gateway calls
`CPositionReconciler::FindPosition(symbol, magic)`. If a position exists it is
adopted as `QME_EXEC_RECONCILED`; if not, the intent stays `UNKNOWN_STATE`,
which blocks a re-send pending operator attention.

## 7. Protective stop maintenance

`CTradeManager::ModifyProtection`:

* refuses `newSL <= 0` (would remove protection);
* for BUY, refuses `newSL < currentSL`; for SELL, refuses `newSL > currentSL`;
* verifies the stop is on the correct side of the market and outside the broker
  stops level;
* sends `TRADE_ACTION_SLTP` and reports the broker's answer.

`TightenStop` is a thin wrapper that does nothing unless the candidate actually
tightens.

## 8. Evidence

* `CTradeJournal` — append-only CSV in the common folder:
  time, event, signal, symbol, side, volume, prices, retcode, tickets, comment.
* `CExecutionMonitor` — built/sent/confirmed/failed/unknown/localReject/retries,
  last retcode, last latency.
* `CExecutionStatistics` — per-symbol attempts, fills, rejects, volume.
* `CTransactionHandler` — attributes `OnTradeTransaction` events by magic and
  logs deal/order identity.

## 9. What execution will never do

* send without SL and TP;
* retry a timeout;
* use the minimum lot when sizing produced zero;
* widen a stop;
* send a second order for the same intent;
* claim success without a broker retcode or a reconciled position.
