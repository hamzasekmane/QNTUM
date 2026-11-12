# Persistence and recovery reliability audit

## Components and current evidence

Persistence modules include `CheckpointManager`, `StateStore`, `StateSerializer`, `StateRecovery`, `RuntimeMemory`, `SignalHistoryStore`, and `PositionStateStore`. Runtime engine integrates save/restore. Existing `Documentation/ReleaseCandidateAudit.md` and `ReleaseReviewMatrix.csv` record earlier review concerns and a conservative NO-GO decision; they are context, not proof of current runtime behavior.

Static source inventory confirms account/server/magic-scoped state logic and conservative refusal around unresolved legacy state in regression checks. Static test coverage also checks restart recovery program pairing. No terminal was available to perform writes, crash injection, broker reconciliation, schema migration or filesystem atomicity validation.

## Critical unresolved validation

| Scenario | Status | Required evidence |
|---|---|---|
| Normal shutdown/restart | Not runtime-tested here | MT5 save/restore with exact state comparison. |
| Crash / interrupted write | Not tested | Terminate during each write boundary; verify old complete state or fail-closed. |
| Corrupt/truncated/missing checkpoint | Not tested in runtime | Recovery must preserve backup and block execution if safety state unknown. |
| Older schema / partial restore | Not tested | Explicit version migration and completeness assertions. |
| Account/server/symbol/magic isolation | Static regression present | Two-scope runtime fixtures and persisted-path verification. |
| Existing broker positions and submitted/unknown intents | Not tested | Demo/strategy tester reconciliation scenarios before retry/entry. |

Do not silently reset to empty state after unrecoverable restore failure. Any repair must preserve existing state/backups and be tested before changing recovery behavior. No persistence implementation was altered.
