# tools/pc-runners/runner-cpu-cap.ps1 - start the Windows PC's runner INSIDE a
# hard CPU and memory cap, so it and everything it starts can never pin the PC
# (docs/PC-RUNNERS.md).
#
# WHY. Below Normal priority alone lets a build take every idle cycle, and the
# maintainer asked that the Windows PC is never pinned at 100% by CI
# (2026-11-21). Windows enforces a hard cap through a job object: every process
# in the job together gets at most CpuPercent of the WHOLE machine (25% of six
# cores is a core and a half), however idle the rest is, and every process a
# member starts is a member too.
#
# WHY THIS SHAPE. The first version ran the runner as a service and had a
# SYSTEM task put its processes into the job afterwards. On the maintainer's PC
# (2026-11-21) Windows refused every assignment ("could not cap pid ..."), so
# the runner ran with no cap at all. Now nothing else starts the runner: this
# script, run at boot as NETWORK SERVICE by the scheduled task
# setup-windows-runner.ps1 registers, puts ITSELF into the job and only then
# starts run.cmd, which inherits the job. If it cannot join the job it stops
# and the runner never starts: the cap fails closed. KILL_ON_JOB_CLOSE ends the
# runner and its jobs when this script ends (Stop-ScheduledTask pauses it).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File runner-cpu-cap.ps1 -RunnerDir DIR [-CpuPercent 25] [-MemoryGB 8]
param(
  [Parameter(Mandatory = $true)][string]$RunnerDir,
  [int]$CpuPercent = 25,
  [int]$MemoryGB = 8
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class RunnerCap {
  [StructLayout(LayoutKind.Sequential)]
  struct CPU_RATE { public uint ControlFlags; public uint CpuRate; }
  [StructLayout(LayoutKind.Sequential)]
  struct BASIC_LIMIT {
    public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
    public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
  [StructLayout(LayoutKind.Sequential)]
  struct EXTENDED_LIMIT {
    public BASIC_LIMIT Basic; public IO_COUNTERS Io; public UIntPtr ProcessMemoryLimit;
    public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed;
  }
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern IntPtr CreateJobObject(IntPtr attrs, string name);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint size);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool QueryInformationJobObject(IntPtr job, int cls, IntPtr info, uint size, IntPtr ret);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
  [DllImport("kernel32.dll")]
  static extern IntPtr GetCurrentProcess();

  static void Fail(string what) {
    int e = Marshal.GetLastWin32Error();
    throw new Exception(what + " failed: Win32 error " + e + " (" + new System.ComponentModel.Win32Exception(e).Message + ")");
  }

  static void Set<T>(IntPtr job, int cls, T value, string what) {
    int size = Marshal.SizeOf(typeof(T));
    IntPtr p = Marshal.AllocHGlobal(size);
    try {
      Marshal.StructureToPtr(value, p, false);
      if (!SetInformationJobObject(job, cls, p, (uint)size)) Fail(what);
    } finally { Marshal.FreeHGlobal(p); }
  }

  // The job, its limits set, with this process in it; throws (with the
  // Win32 error) on any step that did not happen.
  public static IntPtr Join(string name, int cpuPercent, long memoryBytes) {
    IntPtr job = CreateJobObject(IntPtr.Zero, name);
    if (job == IntPtr.Zero) Fail("CreateJobObject");
    // JobObjectCpuRateControlInformation (15): ENABLE | HARD_CAP, in 1/100 of a percent
    Set(job, 15, new CPU_RATE { ControlFlags = 0x1 | 0x4, CpuRate = (uint)(cpuPercent * 100) }, "the CPU cap");
    // JobObjectExtendedLimitInformation (9): JOB_MEMORY (0x200), PRIORITY_CLASS (0x20)
    // at Below Normal (0x4000), KILL_ON_JOB_CLOSE (0x2000)
    var ext = new EXTENDED_LIMIT();
    ext.Basic.LimitFlags = 0x200 | 0x20 | 0x2000;
    ext.Basic.PriorityClass = 0x4000;
    ext.JobMemoryLimit = new UIntPtr((ulong)memoryBytes);
    Set(job, 9, ext, "the memory and priority limits");
    if (!AssignProcessToJobObject(job, GetCurrentProcess())) Fail("joining the job");
    bool inJob;
    if (!IsProcessInJob(GetCurrentProcess(), job, out inJob)) Fail("IsProcessInJob");
    if (!inJob) throw new Exception("this process is not in the job after joining it");
    return job;
  }

  // The process ids in the job now (JobObjectBasicProcessIdList, 3)
  public static List<int> Members(IntPtr job) {
    int size = 8 + 8 * 4096;
    IntPtr p = Marshal.AllocHGlobal(size);
    var ids = new List<int>();
    try {
      if (!QueryInformationJobObject(job, 3, p, (uint)size, IntPtr.Zero)) Fail("listing the job");
      int n = Marshal.ReadInt32(p, 4);
      for (int i = 0; i < n; i++) ids.Add((int)Marshal.ReadIntPtr(p, 8 + i * IntPtr.Size).ToInt64());
    } finally { Marshal.FreeHGlobal(p); }
    return ids;
  }
}
'@

$log = Join-Path $PSScriptRoot 'runner-cpu-cap.log'
$state = Join-Path $PSScriptRoot 'runner-cpu-cap.state'
function Note($msg) { Add-Content -Path $log -Value ("{0:u} {1}" -f (Get-Date), $msg) }

$runCmd = Join-Path $RunnerDir 'run.cmd'
if (-not (Test-Path $runCmd)) { Note "no $runCmd; not starting"; exit 1 }

# An unnamed job: a named one would need SeCreateGlobalPrivilege and could be
# held by an older install's SYSTEM task. setup-windows-runner.ps1 registers
# ONE runner per PC, so one job is the whole cap.
try {
  $job = [RunnerCap]::Join($null, $CpuPercent, [long]$MemoryGB * 1GB)
} catch {
  Note "NOT starting the runner: $($_.Exception.Message)"
  exit 1
}
Note "in the job (at most $CpuPercent% of the CPU and $MemoryGB GB, Below Normal); starting $runCmd"

$cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
while ($true) {
  $runner = Start-Process -FilePath $cmd -ArgumentList '/c', "`"$runCmd`"" -WorkingDirectory $RunnerDir `
    -NoNewWindow -PassThru
  while (-not $runner.HasExited) {
    # What is in the cap now, for anyone checking it (readable without admin)
    $ids = [RunnerCap]::Members($job)
    $names = foreach ($id in $ids) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { "$id $($p.ProcessName)" } }
    Set-Content -Path $state -Value (@(("{0:u} {1} process(es) capped at {2}% CPU, {3} GB" -f (Get-Date), $ids.Count, $CpuPercent, $MemoryGB)) + $names)
    Start-Sleep -Seconds 30
  }
  Note "the runner ended (exit $($runner.ExitCode)); starting it again in 30 s"
  Start-Sleep -Seconds 30
}
