# tools/pc-runners/setup-windows-runner.ps1 - make the maintainer's Windows PC
# a GitHub Actions runner for this repository's own branches, without getting
# in the way of the person using it (docs/PC-RUNNERS.md).
#
#   (in an elevated PowerShell)
#   powershell -ExecutionPolicy Bypass -File setup-windows-runner.ps1 -Repo OWNER/REPO -Token REGISTRATION-TOKEN
#
# The token comes from the repository's Settings > Actions > Runners > New
# self-hosted runner page (the --token value; it lapses after an hour).
# Running it again for the same repository replaces that runner.
#
# What it sets up, and why:
#   - the runner under NT AUTHORITY\NETWORK SERVICE, started at boot by a
#     scheduled task in session 0, which has no desktop the user sees, so a
#     job can never open a window on the screen; and the account is not the
#     user's, so a job cannot read their files.
#   - a HARD cap: that task runs runner-cpu-cap.ps1, which joins a Windows job
#     object limited to CpuPercent of the whole CPU (25% of six cores, a core
#     and a half) and MemoryGB and only then starts the runner, so the runner
#     and every process it starts are inside it and CI can never pin the PC.
#     It is not a service: a service starts outside the cap, and Windows would
#     not let the cap take it in afterwards (2026-11-21).
#   - Below Normal CPU priority and Low I/O priority for the runner's two
#     processes (Image File Execution Options). Windows gives a child process
#     its parent's class when that class is Below Normal, so every compiler
#     and test a job starts runs below the user's own programs.
#   - a PATH for jobs with the Build Tools' CMake and Ninja, Git's bash and a
#     `python3` (the lanes' bash steps call python3; Windows Python has none).
#   - two job hooks: one that refuses to start a job when C: has less than
#     MinFreeGB free, one that deletes the job's checkout when it ends.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Repo,
  [Parameter(Mandatory = $true)][string]$Token,
  [int]$MinFreeGB = 4,
  [int]$CpuPercent = 25,
  [int]$MemoryGB = 8,
  [string]$Root = 'C:\actions-runner'
)
$ErrorActionPreference = 'Stop'
$Labels = 'seth-pc'

function Die($msg) { Write-Error "setup-windows-runner: $msg"; exit 1 }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Die 'run it from an elevated PowerShell (Run as administrator)'
}
if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Die "OWNER/REPO looks wrong: $Repo" }

$freeGB = [math]::Floor((Get-PSDrive C).Free / 1GB)
if ($freeGB -lt ($MinFreeGB + 2)) { Die "only $freeGB GB free on C:; free some space first" }

# The tools the routed lanes use: Visual Studio 2022 (Build Tools will do)
# with its CMake and Ninja, Git for bash, and Python
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { Die 'Visual Studio 2022 or its Build Tools are not installed' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { Die 'Visual Studio has no C++ x86/x64 tools (the VCTools workload)' }
$cmakeBin = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
$ninjaBin = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
foreach ($p in @($cmakeBin, $ninjaBin)) { if (-not (Test-Path $p)) { Die "missing $p (add the C++ CMake tools component)" } }
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Die 'Git for Windows is not installed' }
$gitBin = Join-Path (Split-Path (Split-Path $git.Source)) 'bin'
if (-not (Test-Path (Join-Path $gitBin 'bash.exe'))) { Die "no bash.exe in $gitBin" }
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { Die 'Python is not installed' }
$pythonDir = Split-Path $python.Source

New-Item -ItemType Directory -Force -Path "$Root\bin", "$Root\hooks" | Out-Null
# `python3` for the lanes' bash steps: Git's bash runs an extensionless script
Set-Content -NoNewline -Encoding ascii -Path "$Root\bin\python3" -Value "#!/bin/sh`nexec python `"`$@`"`n"

Set-Content -Encoding ascii -Path "$Root\hooks\job-started.ps1" -Value @"
`$free = [math]::Floor((Get-PSDrive C).Free / 1GB)
if (`$free -lt $MinFreeGB) {
  Write-Output "::error::The PC runner has only `$free GB of disk free (it needs $MinFreeGB); not starting, so the PC's disk is never filled."
  exit 1
}
"@
Set-Content -Encoding ascii -Path "$Root\hooks\job-completed.ps1" -Value @'
# The checkout and build tree go when the job ends: the PC's disk is shared
# with the person using it.
if ($env:GITHUB_WORKSPACE -and (Test-Path $env:GITHUB_WORKSPACE)) {
  Get-ChildItem -Force $env:GITHUB_WORKSPACE | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
'@

# Below Normal CPU (5) and Low I/O (1) for the runner and everything it starts
foreach ($exe in 'Runner.Listener.exe', 'Runner.Worker.exe') {
  $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exe\PerfOptions"
  New-Item -Force -Path $key | Out-Null
  New-ItemProperty -Force -Path $key -Name CpuPriorityClass -PropertyType DWord -Value 5 | Out-Null
  New-ItemProperty -Force -Path $key -Name IoPriority -PropertyType DWord -Value 1 | Out-Null
}

$release = Invoke-RestMethod -UseBasicParsing https://api.github.com/repos/actions/runner/releases/latest
$version = $release.tag_name.TrimStart('v')
$assetName = "actions-runner-win-x64-$version.zip"
$asset = $release.assets | Where-Object { $_.name -eq $assetName }
if (-not $asset -or -not ($asset.digest -like 'sha256:*')) { Die "the runner release did not publish a sha256 digest for $assetName" }

$dir = Join-Path $Root ($Repo -replace '/', '-')
$task = 'GitHub runner (capped)'
# One runner per PC: the cap is per runner, and two would be two caps
$others = Get-ChildItem -Directory $Root -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -ne $dir -and (Test-Path (Join-Path $_.FullName '.runner')) }
if ($others) { Die "another runner is registered in $($others[0].FullName); remove it first (docs/PC-RUNNERS.md)" }

# Stop what an earlier install started: this script's task, and the first
# version's service and separate SYSTEM cap task (2026-11-21), which Windows
# would not let cap the service
foreach ($t in $task, 'GitHub runner CPU cap') {
  if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $t -Confirm:$false
  }
}
foreach ($svc in Get-Service 'actions.runner.*' -ErrorAction SilentlyContinue) {
  Stop-Service -Force $svc.Name -ErrorAction SilentlyContinue
  & "$env:SystemRoot\System32\sc.exe" delete $svc.Name | Out-Null
}
# Its registration is replaced by --replace below; the files go
if (Test-Path "$dir\.runner") { Write-Output "replacing the runner in $dir" }
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$zip = Join-Path $dir $assetName
Invoke-WebRequest -UseBasicParsing -OutFile $zip "https://github.com/actions/runner/releases/download/v$version/$assetName"
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
if ($hash -ne $asset.digest.Substring(7).ToLower()) { Die "checksum mismatch for $assetName" }
Expand-Archive -Path $zip -DestinationPath $dir
Remove-Item $zip

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
Set-Content -NoNewline -Encoding ascii -Path "$dir\.path" -Value (
  @("$Root\bin", $gitBin, $cmakeBin, $ninjaBin, $pythonDir, (Join-Path $pythonDir 'Scripts'), $machinePath) -join ';')

# Registered but NOT a service: only runner-cpu-cap.ps1 starts it, already
# inside the cap, so it can never run uncapped
Push-Location $dir
$name = "$env:COMPUTERNAME-$($Repo.Split('/')[1])".ToLower()
& .\config.cmd --unattended --replace --url "https://github.com/$Repo" --token $Token `
  --name $name --labels $Labels --work _work
if ($LASTEXITCODE -ne 0) { Pop-Location; Die 'config.cmd failed' }
Add-Content -Encoding ascii -Path "$dir\.env" -Value @(
  "ACTIONS_RUNNER_HOOK_JOB_STARTED=$Root\hooks\job-started.ps1",
  "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=$Root\hooks\job-completed.ps1")
Pop-Location

$capSrc = Join-Path $PSScriptRoot 'runner-cpu-cap.ps1'
if (-not (Test-Path $capSrc)) { Die 'runner-cpu-cap.ps1 must sit beside this script' }
Copy-Item -Force $capSrc "$Root\runner-cpu-cap.ps1"
Remove-Item -Force -ErrorAction SilentlyContinue "$Root\runner-cpu-cap.log", "$Root\runner-cpu-cap.state"

# NETWORK SERVICE runs the runner, writes its checkouts and the cap's log here
icacls $Root /grant 'NT AUTHORITY\NETWORK SERVICE:(OI)(CI)M' /T /Q | Out-Null

# The task: at every boot, as NETWORK SERVICE in session 0 (no window, not
# the user's account), runner-cpu-cap.ps1 joins the job and starts run.cmd.
# PowerShell by full path: Task Scheduler keeps the PATH it booted with, and
# on the maintainer's PC (2026-11-21) that PATH had lost System32, so a bare
# powershell.exe never started.
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$capArgs = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Root\runner-cpu-cap.ps1`" -RunnerDir `"$dir`" -CpuPercent $CpuPercent -MemoryGB $MemoryGB"
$action = New-ScheduledTaskAction -Execute $ps -Argument $capArgs -WorkingDirectory $dir
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\NETWORK SERVICE' -LogonType ServiceAccount -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 10 `
  -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -Force -TaskName $task -Action $action -Trigger $trigger -Principal $principal `
  -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $task

Write-Output ''
Write-Output "Done: $name is registered with $Repo under the labels self-hosted, Windows, X64, $Labels,"
Write-Output "and runs inside a cap of $CpuPercent% of the CPU and $MemoryGB GB ($Root\runner-cpu-cap.log, .state)."
Write-Output "It takes jobs only once the repository variable PC_RUNNERS_WINDOWS is 'on'."
Write-Output "Pause it:  Stop-ScheduledTask '$task'     Resume: Start-ScheduledTask '$task'"
