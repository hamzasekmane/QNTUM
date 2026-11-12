# MT5 runtime execution plan (isolated, no broker)

Runtime is **not executed**. The Windows host, terminal build, compiled EAs, and local test data are not available in the current environment. This is a safe runbook for a Windows operator; do not interpret it as a pass.

## Preconditions

1. Complete `WindowsValidationEnvironment.md` and `NativeCompilationInstructions.md`; use a dedicated local MT5 terminal/data folder, not an ordinary trading profile.
2. Leave terminal disconnected from all accounts. Do not enter credentials or connect to a broker. Disable Algo Trading globally. Do not attach `QME_Main` to any chart.
3. Run only the 21 dedicated test EAs, one at a time in Strategy Tester. Source wrappers call their suite directly from `OnInit`; do not use a chart. The inspected wrappers call test functions and do not contain `OrderSend`/`CTrade.Buy/Sell` calls, but independently review each compiled test and included helper before execution. Stop if a suite attempts or could route a broker order.
4. Do not use real or demo login, remote agents, cloud agents or optimization. Use the local tester agent and isolated synthetic/local history only. Do not download history by connecting an account. A suite needing unavailable market data must be reported SKIP/BLOCKED, never converted to PASS.
5. Run tests that may write persistence only under an isolated data folder and synthetic state. Back up that test folder before destructive fault-injection cases.

## Test run procedure

In MT5 Strategy Tester select one test EA from the isolated copy (path below `MQL5\Experts\QME_Validation\<commit>\Tests\...`), select local agent, optimization off, visual mode off unless the test explicitly requires it, and an appropriate local symbol/timeframe only for data-dependent tests. Prefer self-contained unit suites first. Start test and save the full tester Journal/Experts output plus report under `ValidationLogs\Runtime\<suite>`. Capture terminal build, test EA path/hash, symbol, timeframe, model, date range, history availability and any skips. Repeat for each of 21 suites, preserving original assertions and logs.

At minimum collect each `CTestKit` per-assertion `PASS`/`FAIL`/`SKIP` lines and terminal final status. A suite passes only if the tester shows successful EA initialization and `CTestKit` reports zero failures; report skips separately, and fail certification if a mandatory assertion was skipped. Some market-pipeline suites require deterministic market history; document exact fixture source and date interval. Do not substitute random/current market data for a reproducibility fixture.

## Suggested test order

1. `Tests/Unit/*` (10 self-contained candidates; confirm dependencies per suite).
2. `Tests/Regression/*` (3).
3. `Tests/Integration/*` (4; inspect for file/account state and use isolated synthetic/local data).
4. `Tests/Validation/Test_RealAccountSafety` (only as a non-trading validation suite, disconnected; abort on any account/order side effect).
5. `Test_DemoTrading` and `Test_RestartRecovery` only after reviewing their full source/include dependencies; do not authorize trading or connect an account. Recovery fault cases use disposable isolated state.

## Tester configuration template

Use Strategy Tester UI and manually set an EA, local agent, optimization OFF, and no login/account. Save settings per test in `ValidationLogs\Runtime\settings\<suite>.set` when supported. Do not launch a command-line terminal config containing login/password fields. If an INI config is used, keep it non-secret, local-agent-only, and verify the terminal does not auto-connect before running. A template is intentionally not populated with a broker account, symbol feed, deposit or credentials because those would imply test conditions not verified here.

## Reproducibility / test data

- Record repository commit and hashes of copied `.mq5`/`.mqh`/`.ex5` targets.
- Prefer test-owned synthetic arrays/fixtures for unit suites.
- For data-driven tests, use a fixed, licensed local history export with source, symbol mapping, timeframe and timestamp range documented. Keep data outside Git and do not include account identifiers.
- Preserve logs unedited; include test settings, tester Journal, Experts log, terminal build and terminal data-folder identifier (not credentials).
- Expected result comes from suite assertions / expected failure conditions. Record `PASS`, `FAIL`, `SKIP`, or `BLOCKED` with concrete evidence. Do not infer success from process exit or absence of visible chart errors.
