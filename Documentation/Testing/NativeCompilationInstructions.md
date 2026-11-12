# Native MQL5 compilation instructions

Compilation has **not** been performed in this Linux environment. Follow only on a Windows host with the terminal-matched MetaEditor detected as described in `MetaEditorBuildDetection.md`. Build logs belong in the isolated copy's `ValidationLogs` directory, not the source checkout.

## Setup and paths

Use the isolated copy prepared by `WindowsValidationEnvironment.md`, e.g.:

```powershell
$Validation = 'C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<id>\MQL5\Experts\QME_Validation\<git-commit>'
$Editor = 'C:\Program Files\MetaTrader 5\metaeditor64.exe' # replace with verified matching path
$LogDir = Join-Path $Validation 'ValidationLogs\Compile'
New-Item -ItemType Directory -Force $LogDir | Out-Null
```

MetaEditor command line supports `/compile:<file>` and `/log:<file>`. Compile from the copied source tree so the relative `#include` directory layout is preserved:

```powershell
$Main = Join-Path $Validation 'QME_Main.mq5'
$MainLog = Join-Path $LogDir 'QME_Main.compile.log'
$p = Start-Process -FilePath $Editor -ArgumentList @("/compile:`"$Main`"", "/log:`"$MainLog`"") -Wait -PassThru
"MetaEditor process exit code: $($p.ExitCode)" | Set-Content (Join-Path $LogDir 'QME_Main.process.txt')
Get-Content $MainLog
```

MetaEditor may return a process code that is not a reliable compile verdict across installations. Acceptance requires inspecting the full log for the exact success summary and zero unexplained warnings/errors, and confirming the expected `.ex5` was freshly produced. Never treat the process exit code alone as proof.

## Compile all 23 test EAs (and the benchmark EA)

```powershell
$Targets = @(
 'Tests/Integration/Test_Execution.mq5',
 'Tests/Integration/Test_MarketPipeline.mq5',
 'Tests/Integration/Test_MtfPipeline.mq5',
 'Tests/Integration/Test_PositionRecovery.mq5',
 'Tests/Regression/Test_ExecutionFailures.mq5',
 'Tests/Regression/Test_PreviousSignals.mq5',
 'Tests/Regression/Test_RepeatedSignals.mq5',
 'Tests/Unit/Test_Canonical.mq5',
 'Tests/Unit/Test_Entry.mq5',
 'Tests/Unit/Test_Expiry.mq5',
 'Tests/Unit/Test_FvgSafety.mq5',
 'Tests/Unit/Test_HashIndex.mq5',
 'Tests/Unit/Test_AdvancedAlgorithms.mq5',
 'Tests/Unit/Test_Instrumentation.mq5',
 'Tests/Unit/Test_Liquidity.mq5',
 'Tests/Unit/Test_Risk.mq5',
 'Tests/Unit/Test_Scoring.mq5',
 'Tests/Unit/Test_SignalLifecycle.mq5',
 'Tests/Unit/Test_Structure.mq5',
 'Tests/Unit/Test_Zones.mq5',
 'Tests/Validation/Test_DemoTrading.mq5',
 'Tests/Validation/Test_RealAccountSafety.mq5',
 'Tests/Validation/Test_RestartRecovery.mq5'
)
$Summary = Join-Path $LogDir 'all-targets-summary.txt'
foreach ($rel in @('QME_Main.mq5') + $Targets + @('Tools/Benchmarks/Benchmark_SignalHash.mq5')) {
  $file = Join-Path $Validation ($rel -replace '/', '\')
  if (!(Test-Path -LiteralPath $file)) { throw "Missing compile target $file" }
  $safe = ($rel -replace '[\\/.]','_')
  $log = Join-Path $LogDir "$safe.compile.log"
  $p = Start-Process -FilePath $Editor -ArgumentList @("/compile:`"$file`"", "/log:`"$log`"") -Wait -PassThru
  "TARGET=$rel PROCESS_EXIT=$($p.ExitCode) LOG=$log" | Add-Content $Summary
  if (!(Test-Path $log)) { throw "No compiler log for $rel" }
}
```

Review **all 25** logs and summary manually. Confirm each `.ex5` timestamp/hash is current; compile from correct MetaEditor. Archive logs unchanged. Record every warning/error by path and line, cause, severity, repair and full rebuild result. Do not edit source simply to silence warnings. If any compiler is missing, report BLOCKED; do not substitute the Python static tools.
