# QuantumMarketEngine — Risk Specification

## 1. Principles

1. **Risk is computed from the stop, never from the position.** Volume is derived
   from the distance to the protective stop.
2. **Rounding is always down.** `NormalizeVolume` rounds toward zero; if the
   result is below the broker minimum the trade is refused, never rounded up.
3. **A trade without a stop cannot exist.** Requests without SL/TP are refused
   by the builder and re-checked by the validator and the gateway.
4. **Risk can only shrink.** `CTradeManager` refuses any stop modification that
   widens risk.
5. **Every refusal is named.** `ENUM_QME_REJECT` + a sentence with the numbers.

## 2. Position sizing

```
valuePerPriceUnit = tickValue / tickSize
lossPerLot        = stopDistance * valuePerPriceUnit
riskMoney         = equity * riskPerTradePct / 100
volume            = NormalizeVolume(riskMoney / lossPerLot)     // rounds DOWN
actualRisk        = volume * lossPerLot                         // ≤ riskMoney
```

Guarantees enforced in `CRiskBudget`:

* `stopDistance <= 0` → `0.0` (caller must refuse);
* `riskMoney <= 0` → `0.0`;
* non-finite input → `0.0`;
* `volume` clamped to `[0, volMax]` and floored to `volStep`;
* `ActualRiskMoney ≤ riskMoney` always.

`CRiskEngine::Evaluate` treats a zero volume as `QME_REJ_VOLUME_INVALID` and
never substitutes the minimum lot.

## 3. Pre-trade checklist (17 gates)

`CPreTradeValidator::Validate` runs these in order; the **first** failure wins
and is reported with its numeric value.

| # | Gate | Reject reason |
|---|------|---------------|
| 1 | `analysisOnly` false | `DISABLED_BY_CONFIG` |
| 2 | plan identity, volume in range, SL valid, TP valid, RR ≥ `minRR` | `VOLUME_INVALID`, `SL_INVALID`, `TP_INVALID`, `RR` |
| 3 | account mode known and snapshot valid | `ACCOUNT_MODE`, `ACCOUNT_PERMISSION` |
| 4 | terminal/EA/account/symbol permissions + direction policy | `PERMISSION_*`, `DISABLED_BY_CONFIG` |
| 5 | symbol structurally tradable | `NOT_TRADABLE` |
| 6 | broker session open | `MARKET_CLOSED` |
| 7 | configured session allowed | `SESSION` |
| 8 | news blackout | `NEWS_WINDOW` |
| 9 | spread (absolute and vs ATR) | `SPREAD`, `STALE_DATA` |
| 10 | risk per trade ≤ `riskPerTradePct` | `RISK_PER_TRADE` |
| 11 | daily loss | `DAILY_LOSS` |
| 12 | drawdown | `DRAWDOWN` |
| 13 | consecutive losses | `CONSECUTIVE_LOSSES` |
| 14 | concurrent positions, per-symbol duplicates | `MAX_POSITIONS`, `DUPLICATE_POSITION` |
| 15 | symbol and portfolio notional | `SYMBOL_EXPOSURE`, `PORTFOLIO_EXPOSURE` |
| 16 | correlated directional cluster | `CORRELATION` |
| 17 | free margin | `MARGIN` |

`SRiskAssessment` records: volume, riskMoney, riskPct, rr, stopDistance,
slPoints, spreadCost, marginRequired, marginFreeAfter, both exposure
percentages, daily loss %, drawdown %, open positions, loss streak, checksRun,
checksFailed, the failing value, and the note.

## 4. Account-level guards

| Guard | Rule | Disabled when |
|---|---|---|
| `CDailyLossGuard` | `dailyPlPct > -maxDailyLossPct` | `maxDailyLossPct <= 0` |
| `CDrawdownGuard` | `drawdownPct < maxDrawdownPct` | `maxDrawdownPct <= 0` |
| `CConsecutiveLossGuard` | `streak < maxConsecutiveLosses` | `maxConsecutiveLosses <= 0` |

`CAccountState::SyncFromHistory` derives the loss streak from **broker deals**,
not from an internal counter, so a restart cannot reset it upward.

## 5. Exposure

Notional = `volume * contractSize * price` (exact for CFDs/stocks, consistent for
FX). Limits are a percentage of equity:

* per symbol (`maxSymbolExposurePct`, default 5%);
* portfolio (`maxPortfolioExposurePct`, default 12%).

If the broker does not report a contract size, the notional check is skipped and
the reason is stated in the assessment rather than assumed to pass.

## 6. Correlation

`CCorrelationRisk` is explicitly a **heuristic**, not a covariance estimate:

| Relationship | Score |
|---|---|
| same symbol | 1.00 |
| FX sharing a currency | 0.60 |
| FX with USD on opposite legs | 0.55 |
| same asset class | 0.50 |
| otherwise | 0.10 |

Only same-direction positions with a score ≥ 0.49 are summed. This prevents
"three long USD bets" being treated as three independent trades. It does not
claim statistical correlation.

## 7. Spread and session

* absolute cap in points (`maxSpreadPoints`, 0 = disabled);
* relative cap `spread / ATR ≤ maxSpreadAtrRatio` (default 0.15);
* zero spread is treated as missing data (`STALE_DATA`), not as a bargain.

## 8. News

`CNewsFilter` blocks only the windows the operator configures
(`InpNewsBlackoutWindows`, GMT, `HH:MM-HH:MM`, may cross midnight). It does not
fabricate an economic calendar. If a real feed is added it must plug into the
same contract.

## 9. What is explicitly forbidden

* Martingale, grid, averaging down, revenge trading — no such code path exists.
* Widening or removing a protective stop to "give the trade room".
* Increasing risk after a loss (all sizing is a fixed percentage of equity).
* Unlimited retries (capped, delayed, and forbidden after ambiguous answers).
* Trading an account whose type is unknown.
