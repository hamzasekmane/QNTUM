# Candidate validity and retry audit

## Proven root cause
The collector creates `SCandidateHypothesis` only after validating entry geometry, then sets both `h.entry.valid=true` (in `CEntryTypes::Validate`) and `h.valid=true`. The clusterer selects and merges only `hyps[i].valid`, copies its score factors/evidence booleans, populates `mc.cand`, and sets `mc.cand.valid=true`. However it initialized `mc.valid=false` and never changed it. `CSetupEngine::Evaluate` checks **`mc.valid`**, not `mc.cand.valid`, and returned `QME_REJ_INTERNAL / candidate not marked valid` before data/confluence checks, entry confirmation, or scoring. Thus the logged score 0.0 is expected: score calculation is after setup and entry gates.

The defect is a forgotten transport-level validity assignment in `CCandidateClusterer::Merge`, not an invalid hypothesis from `CandidateCollector`, and not a reason to remove the setup guard. The fix now derives both validity fields from the primary hypothesis, its validated entry, and populated positive entry/SL/TP. An invalid merged candidate is not emitted.

`CEntryEngine::Confirm` runs only after the setup verdict succeeds. Scoring runs after entry confirmation. The new integration fixture builds a zone and invokes the actual collector, clusterer, setup gate and scoring engine; also checks invalid hypotheses are filtered and manually invalid merged candidates remain rejected.

## Repeat rejection identity
The signal fingerprint is stable for symbol/side/timeframe/zone/setup closed-bar time, while `MakeId` includes a monotonically increasing sequence. Consequently same-bar repeated scans made different IDs for the same fingerprint. Execution deduplication registers only sent/unknown execution outcomes, correctly protecting orders but not rejected setup diagnostics. The signal registry retains rejected rows; added a specific lookup for terminal `QME_REJ_INTERNAL` fingerprints. Such a fingerprint is suppressed before allocating another signal ID until the setup bar changes. Existing live-fingerprint and execution idempotency behavior remains unchanged.

## Before / after stage evidence
Observed before (user-supplied MT5 log): candidates were being built; setup rejected each with `INTERNAL candidate not marked valid`; score remained `0.0`; the same plans reappeared about every five seconds under new IDs. Therefore this was not a no-candidate scanner failure.

New bounded logs (one per 30 seconds per stage) report:
- `CandidateCollect ... valid=YES entryValid=YES zone=...`
- `CandidateMerge ... candidateValid=YES mergedValid=YES evidenceFactors=...`
- `SetupGate ... candidateValid=YES mergedValid=YES dq=...`

These are expected message formats, not a claimed post-fix MT5 capture. No MetaTrader terminal/compiler is available in this environment, so the actual post-fix counts, setup outcome and scoring reach remain unverified. The deterministic MQL integration fixture is added but not run here.

## XAUUSD Good Friday D1 gap
The supplied `2026-04-02` to `2026-04-06` D1 interval includes 2026-04-03, Good Friday. `SymbolInfoSessionQuote` is a recurring weekly schedule and cannot evidence historical holiday closure. No broker tick/bar file or authoritative ICMarkets symbol-specific holiday record is supplied, so the holiday classification cannot be reliably verified. The history quality veto remains in place; this gap is not whitelisted. A future holiday calendar must be broker/symbol/date-specific and fail closed if not evidenced.

## Validation and safety
Static suite: see current test command result in PR. MQL tests and MetaEditor compilation were not executed. Analysis-only and real-account authorization defaults remain unchanged. No live orders were sent; no risk or execution checks were altered.
