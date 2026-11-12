# Windows native validation environment

**Current status: ENVIRONMENT BLOCKED.** This report specifies reproducible Windows setup; it does not claim that setup or a build ran.

## Inspection performed in this workspace

- Current host reports Linux x86_64, not Windows. `pwsh`, `powershell.exe`, `metaeditor64.exe`, `terminal64.exe`, and `wine` were not found.
- A bounded search of common installation locations found no MetaEditor/MT5 terminal binaries. Therefore Windows edition, MT5 installation, terminal build and MetaEditor build cannot be detected here.
- The base HEAD is `f52ff27918bcefed06f923f46fa99e985c2f7012`; the working tree now contains 198 `.mq5`/`.mqh` files including untracked algorithm/test/benchmark additions. All are present/readable in this Linux workspace; Windows accessibility remains unverified.
- Existing untracked audit reports were preserved. Source files have now been modified in the current algorithm-integration work; no reset/stash/checkout was performed. Use the working-tree copy procedure below, not `git ls-files` alone, so untracked source/test files are included.

## Required Windows host

Use a dedicated Windows 10/11 x64 VM or workstation, with a licensed MetaTrader 5 terminal and its matching MetaEditor installation. Use a dedicated Windows user and a separate terminal data folder for QME validation. Do not sign in to any live account; ideally launch the terminal in a clean isolated profile, do not save credentials, and leave all QME trading switches at analysis-only ON / demo OFF / real OFF / real arming OFF. Runtime test programs are EAs; review each suite and run only the test harnesses in Strategy Tester, not on a live chart.

## Prepare an isolated copy (PowerShell)

Run in PowerShell from the cloned repository root. Set `$TerminalData` to the terminal's **File → Open Data Folder** path (not the installation directory); `$TerminalData` must be for an isolated validation terminal. This copies files into a separate Expert Advisor folder and does not edit the Git checkout.

```powershell
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path '.').Path.TrimEnd('\\','/')
$TerminalData = 'C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<isolated-terminal-id>'
$Dest = Join-Path $TerminalData 'MQL5\Experts\QME_Validation'
$SourceFiles = @(Get-ChildItem -LiteralPath $Repo -Recurse -File | Where-Object {
  $_.Extension -in @('.mq5','.mqh') -and $_.FullName -notmatch '[\\/]\.git[\\/]'
})
if ($SourceFiles.Count -ne 198) { throw "Expected 198 working-tree MQL sources; found $($SourceFiles.Count)" }
$Head = (git -C $Repo rev-parse HEAD).Trim()
$Validation = Join-Path $Dest ($Head + '-working-tree')
New-Item -ItemType Directory -Force -Path $Validation | Out-Null
foreach ($item in $SourceFiles) {
  $rel = $item.FullName.Substring($Repo.Length).TrimStart('\\','/')
  $stream = [System.IO.File]::OpenRead($item.FullName); $stream.Dispose()
  $dst = Join-Path $Validation $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item -LiteralPath $item.FullName -Destination $dst
  $sourceHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
  $copyHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
  if ($sourceHash -ne $copyHash) { throw "Hash mismatch after copy: $rel" }
}
New-Item -ItemType Directory -Force -Path (Join-Path $Validation 'ValidationLogs') | Out-Null
"HEAD=$Head" | Set-Content (Join-Path $Validation 'ValidationLogs\source-revision.txt')
"MQL sources copied and SHA256-verified: $($SourceFiles.Count)" | Add-Content (Join-Path $Validation 'ValidationLogs\source-revision.txt')
```

The script deliberately includes tracked and untracked working-tree MQL sources, omits `.git`, and verifies each copied source by SHA256. If the expected count changes after later edits, update it only after reviewing `git status` and the recursive file inventory. Do not copy `.git` into the terminal.

## Record the environment

1. Record Windows edition/build: `Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, OsArchitecture`.
2. Find the terminal installation via MetaTrader shortcut → **Open file location**, then find `terminal64.exe`; use the terminal's **File → Open Data Folder** to identify the data folder.
3. In terminal **Help → About**, record terminal product build and installation path. Do not infer the MT5 build from Windows file version alone.
4. Open the matching `metaeditor64.exe` from the same installation; record Help → About/version and executable path. Do not mix executables/data folders from different installations.
5. Save screenshots/text evidence and full logs in `ValidationLogs`. Do not store account credentials or account-specific data.
6. Verify 198 `.mq5`/`.mqh` files exist in the copy and all 23 test targets plus the main EA and benchmark EA compile targets are present. If any count differs, stop and reconcile the working tree.

The exact current detection limitation and build-number procedure are in `MetaEditorBuildDetection.md`.
