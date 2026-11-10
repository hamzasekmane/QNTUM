# QuantumMarketEngine — Testing Strategy

## 1. Honesty policy

> **No MQL5 compiler was available in the build environment** (no MetaEditor, no
> MT5 terminal, no Wine). Therefore:
>
> * no test result in this repository has been produced by running the tests;
> * nothing here claims the code compiles;
> * `Tools/mql5check.py` verifies structure only (include guards, balanced
>   braces, duplicate types, unknown identifiers, misplaced `input`), and prints
>   the disclaimer `this is NOT a compilation proof`.

The user must run the tests in MetaEditor/MT5. Exact commands are in
`DeploymentGuide.md`.

## 2. Test programs

Each test is an EA in `Tests/` that runs its assertions in `OnInit` and returns
`INIT_FAILED` when anything failed, so a failing suite is visible in the tester.

### Unit (pure logic, no market data)

| Program | Proves |
|---|---|
| `Test_Zones.mq5` | identity determinism, malformed/expired zone rejection, same-side merge, opposite-side separation, ranking monotonic in strength |
| `Test_Scoring.mq5` | 14 unique factor bits, empty input scores 0, full input scores high and capped, penalty reduces, less evidence scores lower, absurd evidence clamped |
| `Test_Entry.mq5` | stop/target on the correct side, RR honoured, inverted zone refused, zero ATR refused, `QmeStopIsValid`/`QmeTargetIsValid` |
| `Test_Risk.mq5` | sizing arithmetic, round-down, capped risk, degenerate inputs → 0, risk %, daily guard blocks a 4% loss |
| `Test_SignalLifecycle.mq5` | legal chain, six illegal transitions refused, terminal classification, refusal counter |
| `Test_Structure.mq5` | MSS flag handling, cleared event invalid, live evaluation compared to its own flag (skips without history) |
| `Test_Liquidity.mq5` | nearest above/below, absence returns false instead of a fake price |
| `Test_Canonical.mq5` | timeframe name round trip, digest determinism and length, bookkeeping fields excluded, state changes alter the digest, serialise/deserialise round trip, malformed lines refused, equivalence with and without price tolerance |

### Integration

| Program | Proves |
|---|---|
| `Test_MarketPipeline.mq5` | config → data → scanner → analysis coherence (skips without history) |
| `Test_MtfPipeline.mq5` | no zones → no candidates → no merged candidate; ≤1 per side |
| `Test_Execution.mq5` | builder refuses missing stop and inverted stop; `analysisOnly` blocks validation; idempotency claim/complete/reload |
| `Test_PositionRecovery.mq5` | position store round trip; phantom tickets marked closed against the broker |

### Regression

| Program | Proves |
|---|---|
| `Test_ExecutionFailures.mq5` | transient retried, budget respected, permanent not retried, timeout requires reconciliation, delays grow and stay bounded, retcode→reason mapping |
| `Test_RepeatedSignals.mq5` | cooldown blocks repeats, independent fingerprints, cooldown survives restart, empty fingerprint refused |
| `Test_PreviousSignals.mq5` | clean history audits clean; five crafted violations are each detected |

### Validation (safety)

| Program | Proves |
|---|---|
| `Test_DemoTrading.mq5` | default config never authorizes; DEMO needs the switch; missing terminal/EA permission blocks; direction policy; unknown mode never authorized |
| `Test_RealAccountSafety.mq5` | **ten cases**: REAL blocked when disabled, unarmed, no expected login, wrong login; authorized only when every gate passes; account permissions still gate; unknown mode blocked; DEMO refused when only REAL enabled; `analysisOnly` overrides everything; controller agrees |
| `Test_RestartRecovery.mq5` | full compose/apply round trip, phantom position detected, foreign document ignored, unknown version ignored |

## 3. Running

```text
MetaEditor -> open Tests/Unit/Test_Risk.mq5 -> F7 (compile)
MT5 -> Strategy Tester -> the compiled test -> any symbol -> Start
```

Or from a chart: attach the test EA; results appear in the Experts log and the
summary line reads

```
=== <suite>: N passed, M failed, K skipped ===
```

`SKIP` is not a pass: it means the environment lacked data (e.g. no history for
the symbol). A run with skips is inconclusive for those items.

## 4. Static verification (available without MT5)

```bash
cd QNTUM
python3 Tools/mql5check.py          # structural check, 184 files
python3 Tools/mql5fields.py         # member/field access heuristic
```

`mql5check.py` checks include guards, balance, duplicate types, unknown
identifiers and misplaced `input` declarations. `mql5fields.py` resolves every
`variable.member` access against the declared type (including base classes and
array members) and reports accesses the type does not have — the class of typo a
compiler would catch, catching what it can before MetaEditor is available.
Neither tool is a compiler.

Current result:

```
scanned 184 files (184 implemented, 0 empty)
OK: no structural errors detected (this is NOT a compilation proof)
```

## 5. What is still required before any REAL use

1. Compile `QME_Main.mq5` in MetaEditor with **0 errors, 0 warnings** (warnings
   must be reviewed, not ignored).
2. Run every test program; attach the logs.
3. Run the EA on a DEMO account for a meaningful period and inspect the journal
   CSV, the dashboard and the alert stream.
4. Verify restart recovery on DEMO by killing the terminal with a position open.
5. Only then consider REAL with `expectedRealAccountLogin` set to the exact live
   login and `maxPositions = 1`.
