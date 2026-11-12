# Quote-session gap validation follow-up

## Evidence and root cause
The supplied ICMarkets demo log gives actual adjacent M15 bar opens:

| Symbols | Older bar | Newer bar | Delta |
|---|---|---|---:|
| EURUSD, GBPUSD, USDJPY | 2026-11-06 23:45 | 2026-11-09 00:00 | 173,700 s (48 h 15 m) |
| XAUUSD | 2026-11-06 23:45 | 2026-11-09 01:00 | 177,300 s (49 h 15 m) |

These are the timestamps in the runtime diagnostic, not independently re-read from a broker history file. The previous implementation counted any large elapsed interval and rejected when `WorstGap() > closedBars/4`; it did not consult a symbol's quote schedule. The logged interval covers the weekend, but accepting it is now conditional on the broker's own `SymbolInfoSessionQuote` schedule proving no expected M15 interval overlaps a quote session.

## Change
`Data/QuoteSessions.mqh` iterates every expected missing bar and checks overlap with quote sessions from the relevant server-time weekday and the preceding weekday (to cover overnight sessions). Legitimate scheduled closures are accepted; any missing expected bar overlapping an open quote interval is rejected. An unavailable schedule is not treated as proof of closure and fails closed. This is broker/symbol-specific; no blanket weekend or gold whitelist is used. The same guard runs for every timeframe passed to `CDataQualityGuard`.

Freshness still uses the closed-bar boundary (`open + PeriodSeconds`) and retains the stale threshold. Scanner stage/quality reporting is unchanged from PR #9. Existing spread checks have not been weakened. GBPUSD's provided `2.0 vs 0.4 points` is 5.0x by direct division (the log's 5.7x may reflect unrounded values); this remains an abnormal spread indicator and is not suppressed. Existing data-quality `ok` mask does not itself make spread a hard veto, so downstream entry spread gates remain essential and were not changed here.

## Tests and limitations
Added deterministic MQL test fixtures for the supplied FX and gold timestamps, a missing bar during an explicit open quote session, and empty schedule data. The static repository test checks that these fixtures and the broker API path remain connected. The MQL fixtures require running the test program in MetaTrader; they were not executed here.

`python3 test_system.py`: 43/43 static checks passed. `git diff --check`: passed. `Tools/mql5check.py`, `mql5fields.py`, and `mql5calls.py` passed their structural/heuristic checks. MetaEditor/MT5 is unavailable here: no MQL compilation, broker session schedule query, live data scan, or proof of reaching `SignalEngine` is claimed. In particular, the expected live outcome is that the supplied weekend gaps pass only if this account's ICMarkets quote schedule covers all adjacent weekdays and confirms closures; otherwise they remain blocked with a specific reason.

Analysis-only remains default. No runtime permissions or real trading configuration were altered. The DEMO log explicitly says `analysisOnly=YES` and `armed=NO`; this patch does not enable DEMO or LIVE execution. Signal, risk, and execution stages must be validated separately after the scanner reports valid symbols.
