# QuantumMarketEngine — Deployment Guide

## 0. Honesty statement (read first)

This repository was produced in an environment **without a MetaEditor, without an
MT5 terminal and without Wine**. Therefore:

* **the code has not been compiled by the author of these files**;
* no backtest or live result is reported anywhere;
* the only automated verification performed is structural:
  `python3 Tools/mql5check.py` → `scanned 184 files (184 implemented, 0 empty)` /
  `OK: no structural errors detected (this is NOT a compilation proof)`.

Treat the first compile as a required step, not a formality.

## 1. Layout

```
QNTUM/
  QME.mqh                 umbrella include (dependency order)
  QME_Main.mq5            the EA (inputs + event handlers)
  Core/ Data/ Account/ Analysis/ Zones/ Intelligence/
  Strategy/ Risk/ Execution/ Persistence/ Runtime/
  Monitoring/ Output/ Tests/ Documentation/ Tools/
```

Copy the whole tree into:

```
<terminal data folder>/MQL5/Experts/QNTUM/
```

`QME_Main.mq5` uses relative includes, so the folder structure must be preserved.

## 2. First compile

1. Open MetaEditor (`F4` from the terminal).
2. Open `MQL5/Experts/QNTUM/QME_Main.mq5`.
3. Compile (`F7`).
4. Expected: **0 errors**. Warnings must be read; do not ship with warnings you
   have not understood.
5. If the compiler reports an identifier or include error, the message names the
   file and line — fix at the source, do not comment out the include.

Command line equivalent (Windows):

```bat
"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"%APPDATA%\MetaQuotes\Terminal\<ID>\MQL5\Experts\QNTUM\QME_Main.mq5" /log
```

Compile a test suite the same way:

```bat
metaeditor64.exe /compile:"...\MQL5\Experts\QNTUM\Tests\Unit\Test_Risk.mq5" /log
```

## 3. First run (analysis mode)

1. Attach `QME_Main` to a chart of a symbol in `symbolList`
   (`EURUSD` recommended; the scanner handles the rest).
2. Keep **AutoTrading off**. The engine runs regardless and analyses.
3. Defaults are safe: `analysisOnly = true`, every trading switch `false`.
4. Verify in the Experts log:

```
QME 1.0.0 (phase 10)
starting on EURUSD M15
scanner ... symbol(s) initialised
initialised ... magic 20261110; runtime ANALYSIS (analysisOnly is enabled)
READY.
```

5. The dashboard appears top-left; `qme_vis_bias` top-right.

## 4. Evidence to inspect

| File | Location | Content |
|---|---|---|
| `qme_state.txt` | `MQL5/Files/Common/QME/` | checkpoint (atomic, versioned) |
| `qme_journal_<login>.csv` | same | every execution attempt |
| `qme_alerts.csv` | same | delivered alerts |
| Experts log | terminal | lifecycle, refusals, health |

## 5. Enabling DEMO trading

1. Set `analysisOnly = false`, `enableDemoTrading = true`.
2. Attach to a **DEMO** account only.
3. Confirm the log reads `runtime LIVE`.
4. Confirm each order in the journal has `sl` and `tp` populated.
5. Run `Tests/Validation/Test_DemoTrading.mq5` in the tester.

## 6. Enabling REAL trading (checklist)

Do not skip any line.

- [ ] The account really is the intended one; note its **login**.
- [ ] `expectedRealAccountLogin` = that login exactly.
- [ ] `enableRealTrading = true`.
- [ ] `realTradingArmed = true`.
- [ ] `analysisOnly = false`.
- [ ] `riskPerTradePct` ≤ 0.5, `maxPositions = 1` for the first week.
- [ ] Terminal **AutoTrading** is on.
- [ ] EA property **Allow Algo Trading** is on.
- [ ] Symbol allows trading in both directions you intend to use.
- [ ] `Tests/Validation/Test_RealAccountSafety.mq5` passes in the tester.
- [ ] Deploy on a VPS with a UPS or a stable host; a disconnect mid-order leaves
      an `UNKNOWN_STATE` that requires reconciliation, by design.

If any item is missing the engine will refuse every trade and say which gate
failed. That is the intended behaviour, not a bug.

## 7. Restart and recovery

1. State is checkpointed every `checkpointSec` and on `OnDeinit`.
2. On start, `CStateRecovery::Apply` restores account state, tracked positions,
   signal history, fingerprint cooldowns, executed intents and counters.
3. Positions are then reconciled with the broker: anything the broker no longer
   has is marked closed; anything the engine has without a stop is reported as a
   critical health issue.
4. Test it on DEMO: kill the terminal with a position open, restart, confirm the
   position is adopted and still protected.

## 8. Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| `INIT FAILED: configuration: ...` | an input is out of range | read the message; it names the input |
| `account trade mode is not DEMO/CONTEST/REAL` | account type unknown | trading stays disabled by design |
| `runtime ANALYSIS` although demo enabled | `analysisOnly` still true or demo switch off | fix the input, restart |
| All trades refused with `SPREAD` | spread cap too tight for the session | raise `maxSpreadPoints` or leave 0 and tune `maxSpreadAtrRatio` |
| `checkpoint failed` | common folder not writable | check permissions; persistence disables itself and logs |
| `UNKNOWN_STATE` in the journal | timeout/disconnect mid-send | do not re-send manually; reconcile, then restart |
| `unprotected-positions` health issue | a position exists without a stop | close it or attach a stop immediately; the engine will not manage an unprotected position silently |

## 9. What this deployment does not include

* No DLLs, no external services, no credentials, no network calls.
* No guarantee of profit; the risk controls limit loss, they do not create edge.
* No automatic REAL activation of any kind.
