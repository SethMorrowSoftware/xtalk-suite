# tools/pc-runners/runner-cpu-cap.ps1 - keep the Windows PC's runner, and
# everything it starts, inside a hard CPU and memory cap (docs/PC-RUNNERS.md).
#
# WHY. Below Normal priority alone lets a build take every idle cycle, and
# the maintainer asked that the Windows PC is never pinned at 100% by CI
# (2026-11-21). Windows enforces a hard cap through a job object: every
# process in the job together gets at most CpuPercent of the WHOLE machine
# (25% of six cores is a core and a half), however idle the rest is, and a
# process a member starts is a member too. The runner is a service the SCM
# starts, so nothing can start it inside a job; this script, run as SYSTEM
# at boot by the scheduled task setup-windows-runner.ps1 registers, creates
# the job and puts the runner's processes (RunnerService, Runner.Listener,
# Runner.Worker and every descendant) into it, then checks every 15 s so a
# restarted runner, or one that updated itself, is capped again.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File runner-cpu-cap.ps1 [-CpuPercent 25] [-MemoryGB 8] [-Once]
param(
  [int]$CpuPercent = 25,
  [int]$MemoryGB = 8,
  [switch]$Once
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
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
  static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll")]
  static extern bool CloseHandle(IntPtr h);

  static void Set<T>(IntPtr job, int cls, T value) {
    int size = Marshal.SizeOf(typeof(T));
    IntPtr p = Marshal.AllocHGlobal(size);
    try {
      Marshal.StructureToPtr(value, p, false);
      if (!SetInformationJobObject(job, cls, p, (uint)size))
        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    } finally { Marshal.FreeHGlobal(p); }
  }

  public static IntPtr Create(string name, int cpuPercent, long memoryBytes) {
    IntPtr job = CreateJobObject(IntPtr.Zero, name);
    if (job == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    // JobObjectCpuRateControlInformation (15): ENABLE | HARD_CAP, in 1/100 of a percent
    Set(job, 15, new CPU_RATE { ControlFlags = 0x1 | 0x4, CpuRate = (uint)(cpuPercent * 100) });
    // JobObjectExtendedLimitInformation (9): JOB_MEMORY (0x200) and PRIORITY_CLASS (0x20),
    // Below Normal (0x4000) for every member
    var ext = new EXTENDED_LIMIT();
    ext.Basic.LimitFlags = 0x200 | 0x20;
    ext.Basic.PriorityClass = 0x4000;
    ext.JobMemoryLimit = new UIntPtr((ulong)memoryBytes);
    Set(job, 9, ext);
    return job;
  }

  // 1 = put in the job now, 0 = already in it, -1 = could not
  public static int Ensure(IntPtr job, int pid) {
    // PROCESS_SET_QUOTA | PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION
    IntPtr h = OpenProcess(0x0100 | 0x0001 | 0x1000, false, pid);
    if (h == IntPtr.Zero) return -1;
    try {
      bool inJob;
      if (IsProcessInJob(h, job, out inJob) && inJob) return 0;
      return AssignProcessToJobObject(h, job) ? 1 : -1;
    } finally { CloseHandle(h); }
  }
}
'@

$job = [RunnerCap]::Create('Global\ghrunner-cpu-cap', $CpuPercent, [long]$MemoryGB * 1GB)
$log = Join-Path $PSScriptRoot 'runner-cpu-cap.log'
function Note($msg) { Add-Content -Path $log -Value ("{0:u} {1}" -f (Get-Date), $msg) }
Note "job object up: at most $CpuPercent% of the CPU and $MemoryGB GB for the runner and its jobs"

while ($true) {
  $all = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name
  $roots = $all | Where-Object { $_.Name -in 'RunnerService.exe', 'Runner.Listener.exe', 'Runner.Worker.exe' }
  $pids = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($r in $roots) { [void]$pids.Add([int]$r.ProcessId) }
  do {                                   # and every descendant
    $grew = $false
    foreach ($p in $all) {
      if ($pids.Contains([int]$p.ParentProcessId) -and $pids.Add([int]$p.ProcessId)) { $grew = $true }
    }
  } while ($grew)
  foreach ($procId in $pids) {
    $got = [RunnerCap]::Ensure($job, $procId)
    if ($got -eq 1) { Note "capped pid $procId" }
    elseif ($got -lt 0) { Note "could not cap pid $procId" }
  }
  if ($Once) { break }
  Start-Sleep -Seconds 15
}
