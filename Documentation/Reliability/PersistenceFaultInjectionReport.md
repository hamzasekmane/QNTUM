# Persistence fault injection report — Phase 2

**Status: BLOCKED — no MT5 runtime / isolated persistence harness available.** No production/user state was read, overwritten or deleted. No fault injection was attempted.

| Fault case | Result | Required evidence |
|---|---|---|
| Missing checkpoint | NOT RUN | Startup decision and fail-closed behavior in isolated sandbox. |
| Corrupt/truncated record | NOT RUN | Validation result, preserved backup and blocked execution. |
| Interrupted/atomic write | NOT RUN | Kill at write boundaries; old complete state or safe failure. |
| Older schema/invalid record | NOT RUN | Version handling and migration/denial logs. |
| Restart during recovery | NOT RUN | Recovery consistency and no partial execution state. |
| Existing broker position | NOT RUN | Reconciliation before any entry. |
| Unknown intent | NOT RUN | No retry before broker-state resolution. |

The repository's persistence components were inventoried, but no atomicity, backup preservation, schema, or restore behavior is certified from that inspection. Do not initialize empty state and continue if execution safety is unknown. Required: a separate isolated terminal/test data folder with synthetic files and mocked/tester broker state, archived before/after artifacts, fault point, terminal journal, and expected-state comparison. No persistence code change was made.
