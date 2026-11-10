# Repair History — QuantumMarketEngine

> Append-only. Each entry: date, scope, what changed, evidence.

## 2026-11-10 — Round 1: first MetaEditor baseline (101 errors / 27 warnings)

Scope: root-cause repair of the entire baseline, no redesign.

1. **Capacities to `#define`** (Core/Constants.mqh): 24 `const int`
   capacity limits became preprocessor constants; this alone addresses
   ~45 "invalid index value" errors in 19 files.
2. **Structure pointers removed**: `CAccountContext::Ptr`,
   `CSymbolProfile::SpecPtr` (→ `SpecInto`), `CZoneBoard::PtrAt`
   (no callers). Copy-out by reference is now the only struct interface.
3. **Signature conflicts resolved**: duplicated `State()` removed;
   `CPositionStateStore::At` is `bool` in declaration and definition;
   `CRetryPolicy::DelayMs` declaration/definition aligned on
   `(retcode, attempt, baseMs = 250)`.
4. **`input` keyword**: `CEngine::Init` parameter renamed to `in`.
5. **Transaction timestamps**: `CTransactionHandler` no longer reads the
   nonexistent `MqlTradeTransaction.time`; uses `TimeCurrent()` refined
   by `DEAL_TIME`; symbol logged as string.
6. **Const correctness**: `ActiveCount` is `const` on zone board/engine.
7. **Scanner**: timeframe array no longer `const`; liquidity level
   initialised field by field.
8. **HistoryValidator**: array parameters use reference syntax with an
   `ArraySize` bounds check.
9. **CausalValidator**: struct-array aggregate initialiser replaced by
   three explicit event checks.
10. **OrderManager**: `Send` now ends with a defined failure result.
11. **Conversions**: mode cast to int, `FileSize` kept `ulong`, bucket
    clamp in integer arithmetic.
12. **Input renaming**: all 57 inputs in `QME_Main.mq5` renamed to the
    `Inp*` convention (e.g. `InpMagicNumber`, `InpMinimumRiskReward`),
    eliminating every shadowing warning; `SInputs` fields unchanged, so
    no `.mqh` caller was touched.
13. `Tools/mql5fields.py` learned `const` method declarations (its own
    false positives after change 6).

Evidence: three static checkers pass (see CompilationReport.md).
Compilation evidence: **none yet** — awaiting the round-2 MetaEditor log.

### Earlier history (previous branch, merged in PR #1)

- Full implementation of all layers, then checker-driven fix rounds:
  canonical snapshot `tf` loss, signal-lifecycle `INVALIDATED` table,
  `maxExecutionRetries` nonexistent field, filling-mode mask/enum
  confusion, missing `SDataQuality` argument, wrong-arity
  `CLocationEngine::Evaluate` call, dead inputs `newsBlackoutMinutes` /
  `maxSignalsPerDay` wired, broken `ZoneMerger`/`LiquidityMap` includes,
  and the vacuous include check in `mql5check.py`. Details in git log
  (commits `f5e477d`…`f502215`) and `Phase0_Audit.md` §8.

## 2026-11-10 — Round 2: second MetaEditor log (2 errors / 1 warning)

Down from 101/27. (1) Engine init log read `.symbol` from the account
snapshot, which has no such field — it now logs account login and server.
(2) `CRuntimeDiagnostics` received a const config but the authorization
accessors were non-const — `DemoTradingEnabled`, `RealTradingEnabled`,
`SessionAllowed` and `InBlackoutWindow` are const now (all read-only).
`Tools/mql5fields.py` additionally resolves method-call chains through
declared return types, so this defect class is caught statically from
now on (probe-verified). Awaiting the round-3 compile log.

## 2026-11-10 — Round 3: compilation PASS

User-compiled `QME_Main.mq5`: **0 errors, 0 warnings** (115 ms).
Progression across rounds: 101/27 → 2/1 → 0/0. The main Expert Advisor
is now valid, clean-compiling MQL5. Next evidence required: compile the
20 test programs, then execute them (Strategy Tester / DEMO), then a
DEMO forward run. No claim beyond compilation is made yet.

## 2026-11-10 — Test-failure repair round (first executed results)

The user executed the suites; nine failure groups were reported and
repaired by root cause (register D-024…D-031):

1. **P0 crash**: FVG/OrderBlock detectors resized fixed-size caller
   buffers — removed all resizing, capacity-bounded writes, new
   `Tests/Unit/Test_FvgSafety` regression suite.
2. **analysisOnly precedence**: the hard config block is now the first
   check in `CExecutionValidator::Local`; multi-fault test added.
3. **Dedup persistence**: `Deserialize` scratch-parses, rejects
   malformed lines (no timestamp, empty, duplicate), never wipes held
   state on garbage; two tests corrected to documented semantics
   (register both fingerprints; a just-fired signal STAYS blocked after
   restart) and extended.
4. **EntryRig**: inverted/degenerate zones refused with reason; `rr`
   derived from actual normalized geometry; SELL-side tests added.
5. **Risk sizing**: full audit against the mock spec — the engine was
   right (200 USD/lot at the stop); test expectations corrected with
   derivations, metals/coarse/minimum cases added. Risk limits unchanged.
6. **Expiry**: `Check` and `Process` share the pre-execution-only rule;
   EXECUTED/MONITORING can never expire.
7. **MSS**: flag is authoritative; scanner syncs it (plus side and
   lastEvent) from the detected event.
8. **Zones**: merge metric (% of smaller zone) documented in the test;
   threshold-gate, containment and duplicate cases added; merges now
   set `merged = true`.

Evidence: three static checkers pass; `TestResults.md` records the
round-1 failures and marks every re-run NOT TESTED until executed.
