# Execution idempotency validation — Phase 2

**Status: BLOCKED / NOT VALIDATED.** No broker or MT5 runtime was available; no execution intent was submitted.

Static repository tests have checks for repeated signal suppression, fingerprint retry behavior and an unknown execution state guard. These do not prove idempotency through registry eviction, terminal restart, repeated transaction events, or ambiguous broker outcomes.

| Scenario | Required assertion | Result |
|---|---|---|
| Same market snapshot repeated | No unbounded executable duplicate intent | NOT RUN |
| New closed bar / same setup revision | New evaluation may exist; cannot bypass intent identity | NOT RUN |
| Changed setup identity | Only distinct valid intent may pass all guards | NOT RUN |
| Registry eviction / restart | Prior submitted intent remains protected | NOT RUN |
| Unknown broker result | Reconcile orders/positions before retry | NOT RUN |
| Existing order/position | No duplicate order | NOT RUN |
| Repeated execution events | Idempotent transaction processing | NOT RUN |

A stable execution-intent identity independent of transient signal IDs is a required invariant. This report does not assert that every invariant is verified or that code was changed. No thresholds were adjusted. Until instrumented MT5/demo-simulator scenarios show single-intent/single-broker-order behavior and restart recovery, execution testing must stop on uncertainty and demo readiness remains NO-GO.
