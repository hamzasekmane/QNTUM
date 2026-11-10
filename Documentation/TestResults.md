# Test Results — QuantumMarketEngine

> Evidence log. A result is recorded only when a suite was actually
> executed by the user in MetaEditor/Strategy Tester; static checker
> output is never recorded here as a test result.

## Execution round 1 (2026-11-10, user-run in MetaEditor)

`QME_Main.mq5`: compiled 0 errors / 0 warnings, then suites executed.
Failures reported (root causes and repairs in DefectRegister.md
D-024…D-033, details in RepairHistory.md):

| Suite | Failing assertions (as reported) | Root cause (one line) |
|---|---|---|
| Runtime (main EA) | `array out of range`, FvgEngine.mqh:97 | detectors `ArrayResize`d a fixed-size struct-member buffer |
| Test_Execution | analysisOnly yields the config reason | config block was checked last, after market/geometry refusals |
| Test_RepeatedSignals | both fingerprints restored; restored blocked inside window | the test never registered the second fingerprint, and expected a restarted (not preserved) cooldown; `Deserialize` also accepted malformed lines |
| Test_RestartRecovery | restored fingerprint respects its cooldown window | test expected a just-fired signal to be free after restart — the unsafe semantics; implementation preserved timestamps correctly |
| Test_Entry | buy RR respects the request; inverted zone refused; refusal carries a reason | `CEntryRig` never assigned `rr`, and silently repaired inverted zones via MathMax/MathMin |
| Test_Risk | 1.00 lot expected (actual 0.50); 0.33 expected (actual 0.16) | test expectations implied a 5 USD pip value its own mock spec does not have (200 USD/lot at the stop → 0.50/0.16); engine verified correct |
| Test_Expiry | an executed signal is never expired | `Check` exempted only terminal states; EXECUTED is live-but-post-execution and fell through to the time check (registry path filtered states separately, hence its pass) |
| Test_Structure | MSS flag honoured | `IsConfirmed` also required `lastEvent`, a field nothing ever sets — permanently false; the flag itself is now authoritative and the scanner syncs it from the detected event |
| Test_Zones | overlapping zones merge; merge counter; opposite side separate | test used a 60% threshold on 50% overlap geometry (documented metric: % of the smaller zone); merge itself was correct |

## Repair round (2026-11-10, this branch)

All nine groups repaired in implementation (see RepairHistory). Two
test files were corrected where the test contradicted the documented
semantics — `Test_RepeatedSignals` (registers both fingerprints now;
remaining-cooldown arithmetic) and `Test_RestartRecovery` (a just-fired
signal must STAY blocked after restart — stricter than before) — and
`Test_Risk` expectations now carry their derivation from the mock spec.
New coverage: `Test_FvgSafety` (crash regression), multi-fault
precedence in `Test_Execution`, SELL/degenerate zones in `Test_Entry`,
bearish/side-only MSS in `Test_Structure`, tolerance-gate/containment/
duplicate cases in `Test_Zones`, post-restart eligibility in both dedup
suites, metals/coarse-step/minimum-volume sizing in `Test_Risk`.

## Current status

| Item | Status |
|---|---|
| Re-run of the failing suites after repair | **NOT TESTED** (awaiting user execution) |
| Full suite from a clean state | **NOT TESTED** |
| `QME_Main.mq5` recompile after repair | **NOT TESTED** (source changed since the 0/0 compile) |
| DEMO forward / backtest | **NOT TESTED** |

Next execution round must recompile `QME_Main.mq5` and all 21 test
programs, then run the full suite and paste any failures back.
