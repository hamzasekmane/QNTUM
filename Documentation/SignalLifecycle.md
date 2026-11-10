# QuantumMarketEngine — Signal Lifecycle

## 1. States

| State | Meaning | Terminal |
|---|---|---|
| `QME_SIG_DETECTED` | a candidate zone + side exists | no |
| `QME_SIG_EVALUATING` | setup/entry/score evaluation in progress | no |
| `QME_SIG_APPROVED` | risk accepted; a plan exists | no |
| `QME_SIG_EXECUTION_PENDING` | sent to the broker | no |
| `QME_SIG_EXECUTED` | broker confirmed | no |
| `QME_SIG_MONITORING` | position open and managed | no |
| `QME_SIG_CLOSED` | finished normally | **yes** |
| `QME_SIG_REJECTED` | refused by setup, entry, quality or risk | **yes** |
| `QME_SIG_EXPIRED` | time/price/zone expiry | **yes** |
| `QME_SIG_INVALIDATED` | the market invalidated the idea | **yes** |
| `QME_SIG_EXECUTION_FAILED` | broker refused or ambiguous | **yes** |
| `QME_SIG_CANCELLED` | operator/config cancellation | **yes** |

## 2. Legal transitions

```
DETECTED ──> EVALUATING ──> APPROVED ──> EXECUTION_PENDING ──> EXECUTED ──> MONITORING ──> CLOSED
    │            │              │                │                 │
    │            │              │                │                 └──> INVALIDATED
    │            │              │                └──> EXECUTION_FAILED
    │            │              └──> REJECTED / EXPIRED / CANCELLED
    │            └──> REJECTED / EXPIRED / INVALIDATED
    └──> EXPIRED / CANCELLED
```

Enforced by `CSignalLifecycle::Allowed(from, to)`. Everything not listed is
refused. In particular:

* nothing returns from a terminal state;
* `DETECTED → EXECUTED` is impossible (no skipping risk);
* `APPROVED → DETECTED` is impossible (no backwards movement).

## 3. Enforcement

`CSignalLifecycle::Transition(signal, to, reason, note, now)` is the **only**
mutator. It:

1. asks `Allowed(from, to)`;
2. on refusal increments `Refused()`, logs, and returns `false` — the signal is
   untouched;
3. on success updates `state`, `updated`, `reject`, `rejectNote` and writes a
   `CEventLedger` record.

`CDecisionEngine` and `CEngine` both go through
`ApplyState()` → `CSignalLifecycle` → `CSignalRegistry::Update`. There is no
direct assignment to `signal.state` anywhere else.

## 4. Expiry

`CSignalExpiry` terminates a signal when:

* `now >= expires` (`InpSignalExpiryMinutes`);
* the zone that produced it is no longer active;
* price has already passed the stop (the idea is dead, not "cheap").

Expiry is evaluated before execution, so an expired signal can never be sent.

## 5. Repeats and deduplication

Two independent mechanisms:

1. **Registry** — at most one *live* signal per fingerprint
   `symbol|tf|side|zone|bar`.
2. **Deduplicator** — a fingerprint may not re-fire inside
   `InpCooldownSecPerSymbol`, and its state is persisted, so a restart does not
   re-open the door.

`CIdempotencyGuard` is the third layer, at execution level: one broker request
per intent, even across restarts.

## 6. What a signal carries

```
id, fingerprint, symbol, side, tf, entryType, state,
entry, stopLoss, takeProfit1, takeProfit2, rr,
score, confidence (MTF confluence — NOT a probability),
zoneId, source, factorMask, breakdown,
execState, positionTicket, orderTicket, dealTicket, mode
```

`confidence` is deliberately named for what it is. A calibrated probability is
produced separately by `CProbabilityModel`, which refuses to answer below 50
samples rather than guessing.

## 7. Observability

* `CSignalEngine::Stats()` → funnel counters.
* `CSignalHistoryStore` → bounded history of every signal with its final state
  and reason (persisted, restored on start).
* `CExplanationEngine::Decision()` → the sentence a human can read.
* `CReplayEngine` → audits recorded decisions for rule violations.
