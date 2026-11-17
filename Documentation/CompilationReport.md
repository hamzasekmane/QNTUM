# Compilation Report — QuantumMarketEngine

> Honest-status document. Labels: PASS / FAIL / BLOCKED / NOT TESTED.

## P0 spread-source remediation (2026-11-17, current branch)

Scope: scanner bid, ask, spread points and tick timestamp now come from a
single validated `MqlTick` retained by `CTickProcessor`, paired with the point
size captured for that symbol. Missing, stale (>300 seconds), invalid,
zero-spread and future ticks fail closed. `SYMBOL_SPREAD` is used only for a
debug discrepancy diagnostic. The existing spread-risk chain and absolute /
ATR caps were left unchanged.

| Verification | Status | Evidence |
|---|---|---|
| `python3 test_system.py` | **PASS** | 55/55 static checks, including canonical quote, fail-closed, multi-symbol, snapshot-to-risk flow, and unchanged cap regressions |
| `python3 Tools/mql5check.py` | **PASS (heuristic)** | 197 files scanned; no structural errors; explicitly not a compilation proof |
| `python3 Tools/mql5fields.py` | **PASS (heuristic)** | 0 suspicious member accesses |
| `python3 Tools/mql5calls.py` | **PASS (heuristic)** | 0 call-arity mismatches |
| `git diff --check` | **PASS** | no whitespace errors |
| Updated `Tests/Integration/Test_MarketPipeline.mqh` fixtures | **NOT TESTED** | Not run under MetaTrader 5 / Strategy Tester in this environment |
| MetaEditor compile of updated `QME_Main.mq5` and test programs | **NOT TESTED** | The historical compile result below predates this remediation and is not evidence for these edits |
| MT5 runtime / Strategy Tester | **NOT TESTED** | No runtime execution evidence for this change |

The deterministic fixtures cover positive canonical spread despite a zero raw
spread diagnostic, zero/missing/stale/invalid/future ticks, ask below bid,
per-symbol quote identity, and the live snapshot-to-risk propagation contract.
Static verification does not establish that the MQL5 integration fixtures
compile or execute on a terminal.

## Baseline (before repair)

- Source: user-supplied MetaEditor log for `QME_Main.mq5`, 2026-11-10.
- Result: **101 errors, 27 warnings** — FAIL.
- The compiler capped reporting at 101 errors, so the baseline is a
  lower bound, not a complete list.

## Repair round 1 (2026-11-10, branch arena/906b7dd1-qntum)

All 12 root causes from the baseline were repaired (see
`DefectRegister.md` D-001…D-017 and `RepairHistory.md`). Static
verification after the repair:

```
$ python3 Tools/mql5check.py
scanned 190 files (190 implemented, 0 empty)
OK: no structural errors detected (this is NOT a compilation proof)

$ python3 Tools/mql5fields.py
-- 0 suspicious member access(es); this is a heuristic, not a compiler

$ python3 Tools/mql5calls.py
-- 0 arity mismatch(es); this is a heuristic, not a compiler
```

## Historical status before the P0 remediation (2026-11-10)

The rows below describe the earlier revision only; see the dated P0 report above for current verification.

| Target | Status | Evidence |
|---|---|---|
| `QME_Main.mq5` MetaEditor compile (round 3) | **PASS** | user log 2026-11-10: `0 errors, 0 warnings, 115 ms elapsed` |
| 21 test `.mq5` programs compile | **NOT TESTED** | same |
| Static structure/member/arity checks | PASS (heuristics) | tool output above |
| Runtime behaviour, DEMO, backtest | **NOT TESTED** | — |

## Exact local compilation commands (Windows, adjust paths)

```bat
"C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"<repo>\QME_Main.mq5" /log
for %f in ("<repo>\Tests\*\Test_*.mq5") do "C:\Program Files\MetaTrader 5\metaeditor64.exe" /compile:"%f" /log
```

Paste the new log back and round 2 will be worked from it, in the same
root-cause order. Do not treat the static PASS rows as "it compiles".

## Repair round 2 (2026-11-10)

User-compiled `QME_Main.mq5` again: **2 errors, 1 warning** (down from
101/27). Both defects repaired: D-022 (account snapshot has no `symbol`)
and D-023 (authorization accessors not const). The fields checker was
extended to resolve method-call chains through declared return types
(`Snapshot().symbol` is now caught statically; probe-verified).

## Repair round 3 (2026-11-10) — compilation PASS

User-compiled `QME_Main.mq5` in MetaEditor with the round-2 repairs:

```
0 errors, 0 warnings, 115 ms elapsed, cpu='AVX2 + FMA3'
```

**`QME_Main.mq5` compiled cleanly at that revision.** This historical result
does not cover the P0 spread-source changes above. Remaining compile targets:
the test programs under `Tests/` have not been compiled for this remediation.
Runtime behaviour (DEMO, tester, backtest) remains NOT TESTED for this change.
