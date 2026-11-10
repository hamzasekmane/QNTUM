# QuantumMarketEngine — Configuration Reference

All inputs are declared in `QME_Main.mq5` and validated by `CConfig::Init`.
**Every trading switch defaults to `false`; `InpAnalysisOnly` defaults to `true`.**

> Naming: in the terminal the inputs carry the `Inp` prefix
> (`InpMagicNumber`, `InpMinimumRiskReward`, `InpMaximumRetries`, …) so they
> can never shadow function parameters. The tables below use the underlying
> `SInputs` field names; the mapping is one-to-one in `BuildInputs`.

## 1. Runtime

| Input | Default | Meaning |
|---|---|---|
| `logLevel` | `QME_LOG_INFO` | `TRACE…CRITICAL` |
| `logToFile` | `true` | write a log file in the common folder |
| `logCycleDetail` | `false` | verbose per-cycle logging |
| `enableDashboard` | `true` | on-chart panel |
| `dashboardRefreshSec` | `2` | dashboard cadence |

## 2. Scope

| Input | Default | Meaning |
|---|---|---|
| `symbolList` | `EURUSD,GBPUSD,USDJPY,XAUUSD` | comma separated, max 32 |
| `magic` | `20261110` | identifies this engine's positions |
| `scanIntervalMs` | `5000` | minimum time between scans |
| `barsContext` | `400` | bars per context (floor 64) |

## 3. Timeframes

| Input | Default |
|---|---|
| `tfContext` | `D1` |
| `tfBias` | `H4` |
| `tfStructure` | `H1` |
| `tfSetup` | `M15` |
| `tfEntry` | `M5` |

## 4. Trading authorization

| Input | Default | Notes |
|---|---|---|
| `enableDemoTrading` | `false` | required for DEMO |
| `enableRealTrading` | `false` | required for REAL |
| `realTradingArmed` | `false` | second, independent REAL switch |
| `expectedRealAccountLogin` | `0` | **must** match the live login; `0` = never authorized |
| `analysisOnly` | `true` | overrides everything: no order is ever sent |

REAL requires all of: account type REAL/CONTEST **and** `enableRealTrading`
**and** `realTradingArmed` **and** `expectedRealAccountLogin == login`
**and** `analysisOnly == false` **and** terminal AutoTrading **and** EA algo
trading **and** account trading allowed **and** account expert trading allowed
**and** symbol tradable **and** direction allowed **and** every risk check.

An account whose type cannot be determined is never authorized.

## 5. Direction

| Input | Default |
|---|---|
| `allowBuy` | `true` |
| `allowSell` | `true` |

## 6. Risk

| Input | Default | Meaning |
|---|---|---|
| `riskPerTradePct` | `0.5` | % of equity at risk per trade (valid 0–10) |
| `maxDailyLossPct` | `3.0` | daily stop |
| `maxDrawdownPct` | `10.0` | equity drawdown stop |
| `maxPositions` | `3` | concurrent positions |
| `maxPositionsPerSymbol` | `1` | per-symbol capacity |
| `maxSymbolExposurePct` | `5.0` | notional per symbol |
| `maxPortfolioExposurePct` | `12.0` | total notional |
| `maxConsecutiveLosses` | `3` | loss streak stop |
| `minRR` | `1.5` | minimum reward:risk |
| `maxSpreadPoints` | `0.0` | 0 = disabled |
| `maxSpreadAtrRatio` | `0.15` | spread vs ATR |
| `sessionFilterEnabled` | `false` | enable session policy |
| `allowSessionAsia/London/NewYork/Overlap` | `true` | per-session permission |
| `newsFilterEnabled` | `false` | enable blackout |
| `newsBlackoutMinutes` | `30` | minutes added on both sides of every configured blackout window |
| `newsBlackoutWindows` | `""` | `HH:MM-HH:MM;HH:MM-HH:MM` in **GMT** |

## 7. Strategy

| Input | Default | Meaning |
|---|---|---|
| `minScore` | `55.0` | 0..100 |
| `minConfluence` | `0.40` | MTF agreement |
| `requireHtfAlignment` | `true` | bias must agree with setup |
| `maxSignalsPerDay` | `12` | max signals generated per server day, counted from engine start (not persisted across restarts) |
| `signalExpiryMinutes` | `240` | signal lifetime |
| `cooldownSecPerSymbol` | `900` | per-symbol rest after a trade |
| `zoneMaxAgeHours` | `72` | zone retention |
| `zoneMergeOverlapPct` | `60.0` | merge threshold |

## 8. Execution

| Input | Default | Meaning |
|---|---|---|
| `maxRetries` | `2` | transient retries only |
| `retryDelayMs` | `500` | base delay |
| `deviationPoints` | `20` | max slippage |
| `closeOnOppositeSignal` | `false` | after a *successful* new entry, close the tracked position on the same symbol that points the other way; off unless enabled |
| `breakEvenAtR` | `0.0` | when > 0, move the stop to the entry price once the trade has earned that many multiples of its initial risk (R). `0` disables it |
| `tradeJournalEnabled` | `true` | CSV evidence |
| `profileCycles` | `false` | measure per-stage cycle timings, reported at shutdown and in the heartbeat |

## 9. Persistence

| Input | Default | Meaning |
|---|---|---|
| `persistState` | `true` | checkpoint to file |
| `checkpointSec` | `30` | cadence (floor 5) |

State file: `MQL5/Files/Common/QME/qme_state.txt` (atomic write via `.tmp`).
Journal: `QME/qme_journal_<login>.csv`. Alerts: `QME/qme_alerts.csv`.

## 10. Recommended progression

1. `analysisOnly = true` — observe, read explanations, verify the dashboard.
2. DEMO: `analysisOnly = false`, `enableDemoTrading = true`.
3. Run `Tests/Validation/Test_DemoTrading.mq5` and
   `Tests/Validation/Test_RealAccountSafety.mq5` in the tester.
4. REAL only after weeks of DEMO evidence, with `expectedRealAccountLogin` set
   to the exact live account number, and `maxPositions = 1` for the first week.

No step in this progression is automated. The engine cannot enable itself.
