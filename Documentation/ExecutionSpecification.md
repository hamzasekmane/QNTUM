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
| 6 | Save the in-flight state before `COrderManager::Send` | no send on checkpoint failure |
| 7 | On ambiguous response keep intent in flight and fault controller | operator reconciliation required |
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
* Before sending, the current request price is rechecked for minimum RR and
  `OrderCalcProfit` estimates loss at SL in account currency against the equity
  budget. It excludes slippage, gaps, commissions and financing, and is untested
  on the target brokers; it does not guarantee a maximum realized loss.

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
`FAILED` may execute. A checkpoint is attempted before send and a successful
send is checkpointed again; a recovered in-flight record faults the controller.
The checkpoint is currently shared between accounts and instances and has not
been platform- or crash-tested, so persistence is not a production guarantee.
When the table is full and holds no `FAILED` record, the guard refuses.

## 6. Ambiguity

A `TIMEOUT`, connection error or send with no server answer means *unknown*.
The gateway retains the in-flight claim and the controller faults; a position
matching only symbol and magic is not proof of this order's execution. An
operator must reconcile the request, orders, deals and positions before any
restart/recovery procedure. There is no automated resolution workflow yet.

## 7. Protective stop maintenance

`CTradeManager::ModifyProtection`:

* refuses `newSL <= 0` (would remove protection);
* for BUY, refuses `newSL < currentSL`; for SELL, refuses `newSL > currentSL`;
* verifies the stop is on the correct side of the market and outside the broker
  stops level;
* sends `TRADE_ACTION_SLTP` and reports the broker's answer.

`TightenStop` is a thin wrapper that does nothing unless the candidate actually
tightens.

### 7.1 Break-even (`breakEvenAtR`)

Off by default. When `breakEvenAtR = N > 0`, `CEngine::ManagePositions` runs on
every timer tick and looks at each tracked, still-open position:

1. read the live `POSITION_SL`, `POSITION_TP` and `POSITION_PRICE_OPEN`;
2. keep the stored record in sync with the broker;
3. if the position has **no** stop, log an error and do nothing — a level is
   never invented;
4. compute the initial risk `|entry - SL|` and the open profit in the trade's
   direction; when the profit reaches `N x risk`, call
   `CTradeManager::TightenStop(ticket, entry, ...)`.

The stop therefore only ever moves toward the entry and never past the current
market. A position already at or beyond break-even is skipped, so the call is
idempotent.

### 7.2 Opposite-signal close (`closeOnOppositeSignal`)

Off by default. When enabled, `CEngine::CloseOppositePositions` runs **after** a
new entry has been confirmed, iterating the tracked positions on that symbol
whose side differs from the new plan. Before that it is only attempted once per
successful entry, and a failed close is logged as a warning rather than retried
or escalated. Executing the new order first is deliberate: a failed entry can
never leave the account flat with no replacement position.

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
