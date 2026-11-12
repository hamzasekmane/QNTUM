# MetaEditor and MT5 build detection

## Current result

**BLOCKED:** this execution host is Linux (`uname` identified Linux x86_64); no `powershell`, `pwsh`, MetaEditor, MT5 terminal or Wine was found, and no common-path search returned MT5 binaries. Exact Windows, terminal and MetaEditor builds are unknown. No build detection was simulated.

## Detect installations on the Windows validation host

PowerShell discovery (does not launch/log in):

```powershell
$roots = @(
  "$env:ProgramFiles\MetaTrader 5",
  "$env:ProgramFiles\MetaTrader 5\terminal64.exe",
  "$env:ProgramFiles(x86)\MetaTrader 5",
  "$env:LOCALAPPDATA\Programs\MetaTrader 5",
  "$env:APPDATA\MetaQuotes\Terminal"
) | Where-Object { Test-Path $_ }
$roots
Get-ChildItem "$env:ProgramFiles","$env:ProgramFiles(x86)",$env:LOCALAPPDATA -Filter terminal64.exe -Recurse -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty FullName
Get-ChildItem "$env:ProgramFiles","$env:ProgramFiles(x86)",$env:LOCALAPPDATA -Filter metaeditor64.exe -Recurse -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty FullName
```

Recursive search can be slow. Prefer the installed terminal's shortcut target and the MetaTrader `File → Open Data Folder` menu. The terminal **installation path** contains the binaries; the **data path** is usually a separate hashed directory under `%APPDATA%\MetaQuotes\Terminal\<id>`.

For each installation, record these executable paths and file metadata:

```powershell
$Terminal = 'C:\path\to\terminal64.exe'
$Editor   = 'C:\path\to\metaeditor64.exe'
Get-Item $Terminal,$Editor | Select-Object FullName,Length,LastWriteTime,
  @{N='FileVersion';E={$_.VersionInfo.FileVersion}},
  @{N='ProductVersion';E={$_.VersionInfo.ProductVersion}}
Get-FileHash $Terminal,$Editor -Algorithm SHA256
```

**Build numbers:** open the corresponding terminal and MetaEditor and record **Help → About** exactly (screenshots or copied text). File version metadata is supplementary; do not substitute it for the product build displayed by the application. Ensure the MetaEditor is the one shipped with the selected terminal installation. Record terminal and MetaEditor build separately, plus Windows build, installation path, data path and SHA256. A vendor-branded/broker terminal may have distinct paths/builds; do not combine its editor with another terminal.

## Environment access validation

From the repository root, record `git rev-parse HEAD`, `git status --short`, count tracked MQL sources (`(git ls-files '*.mq5' '*.mqh').Count` should be 192), and test every path exists/readable before copying. Verify the isolated terminal copy has the same count and source hashes. Preserve the existing checkout and all uncommitted audit documents. Do not store or expose terminal login/password data.
