<# 
.SYNOPSIS
  Maintenance workflow: check updates, DISM, SFC, install updates, reboot if needed, eventlog check, report.

.NOTES
  Local-debug first. Later you can wrap it with Invoke-Command (WinRM).
  Requires: Run as Administrator.
#>

[CmdletBinding()]
param(
  [int]$EventLogHoursBack = 6,
  [int]$RebootWaitTimeoutSec = 1800,   # 30 min
  [int]$RebootPollIntervalSec = 10,
  [switch]$ExportJson,
  [string]$ExportPath = "C:\Temp"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run PowerShell as Administrator." }
}

function Write-Log {
  param([string]$Message)
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Write-Host "[$ts] $Message"
}

function Invoke-ExternalCommand {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$Arguments
  )
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
  return [pscustomobject]@{
    FilePath = $FilePath
    Arguments = $Arguments
    ExitCode = $p.ExitCode
  }
}

function Get-WindowsUpdates {
  # Returns list of updates (not installed) using Windows Update API
  $session  = New-Object -ComObject "Microsoft.Update.Session"
  $searcher = $session.CreateUpdateSearcher()
  # Not installed, not hidden
  $criteria = "IsInstalled=0 and IsHidden=0"
  $result = $searcher.Search($criteria)

  $updates = @()
  for ($i=0; $i -lt $result.Updates.Count; $i++) {
    $u = $result.Updates.Item($i)
    $kb = @()
    try { $kb = @($u.KBArticleIDs) } catch {}
    $updates += [pscustomobject]@{
      Title = $u.Title
      KBs   = ($kb -join ",")
      IsDownloaded = [bool]$u.IsDownloaded
      RebootRequired = [bool]$u.RebootRequired
      Categories = (@($u.Categories) | ForEach-Object { $_.Name }) -join ", "
    }
  }
  return $updates
}

function Install-WindowsUpdates {
  param([switch]$DownloadIfNeeded)

  $session  = New-Object -ComObject "Microsoft.Update.Session"
  $searcher = $session.CreateUpdateSearcher()
  $criteria = "IsInstalled=0 and IsHidden=0"
  $searchResult = $searcher.Search($criteria)

  if ($searchResult.Updates.Count -eq 0) {
    return [pscustomobject]@{
      InstalledCount = 0
      ResultCode = "NoUpdates"
      RebootRequired = $false
      HResult = $null
    }
  }

  # Build collection
  $updatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
  for ($i=0; $i -lt $searchResult.Updates.Count; $i++) {
    $u = $searchResult.Updates.Item($i)

    # Accept EULA if needed
    if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }

    $null = $updatesToInstall.Add($u)
  }

  if ($DownloadIfNeeded) {
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updatesToInstall
    $dl = $downloader.Download()
    # Continue even if some failed; install may still proceed for others
  }

  $installer = $session.CreateUpdateInstaller()
  $installer.Updates = $updatesToInstall
  $installResult = $installer.Install()

  # ResultCode: 0=NotStarted,1=InProgress,2=Succeeded,3=SucceededWithErrors,4=Failed,5=Aborted
  $codeMap = @{
    0="NotStarted";1="InProgress";2="Succeeded";3="SucceededWithErrors";4="Failed";5="Aborted"
  }

  return [pscustomobject]@{
    InstalledCount = $installResult.Updates.Count
    ResultCode = $codeMap[[int]$installResult.ResultCode]
    RebootRequired = [bool]$installResult.RebootRequired
    HResult = ("0x{0:X8}" -f ($installResult.HResult -band 0xFFFFFFFF))
  }
}

function Test-PendingReboot {
  # Common pending reboot indicators
  $paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
  )
  foreach ($p in $paths) {
    if (Test-Path $p) { return $true }
  }
  return $false
}

function Wait-ForRebootCycle {
  param(
    [Parameter(Mandatory)][datetime]$StartTime,
    [int]$TimeoutSec,
    [int]$PollSec
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)

  # Wait until system time is newer than start + some seconds (meaning it rebooted) OR until uptime reset
  # Uptime via WMI:
  while ((Get-Date) -lt $deadline) {
    try {
      $os = Get-CimInstance Win32_OperatingSystem
      $lastBoot = $os.LastBootUpTime
      if ($lastBoot -gt $StartTime.AddSeconds(-30)) {
        return [pscustomobject]@{ RebootDetected = $true; LastBootUpTime = $lastBoot }
      }
    } catch {
      # During reboot, CIM may fail; ignore and continue
    }
    Start-Sleep -Seconds $PollSec
  }
  return [pscustomobject]@{ RebootDetected = $false; LastBootUpTime = $null }
}

function Get-CriticalEvents {
  param(
    [Parameter(Mandatory)][datetime]$Since
  )
  $filter = @{
    LogName = @("System","Application")
    Level   = 1,2  # 1=Critical, 2=Error
    StartTime = $Since
  }
  $events = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, LogName, LevelDisplayName, ProviderName, Id, Message

  return $events
}

# ---------------- MAIN ----------------
Assert-Admin

$workflowStart = Get-Date
$sinceForEvents = (Get-Date).AddHours(-1 * $EventLogHoursBack)

Write-Log "Maintenance workflow started on $env:COMPUTERNAME"
Write-Log "Collecting basic system info..."

$osInfo = Get-CimInstance Win32_OperatingSystem
$basicInfo = [pscustomobject]@{
  ComputerName = $env:COMPUTERNAME
  OS = $osInfo.Caption
  Version = $osInfo.Version
  LastBootUpTime = $osInfo.LastBootUpTime
  WorkflowStart = $workflowStart
}

Write-Log "Checking available updates..."
$updatesBefore = Get-WindowsUpdates
Write-Log ("Updates found: {0}" -f $updatesBefore.Count)

Write-Log "Running DISM RestoreHealth..."
$dism = Invoke-ExternalCommand -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth"
Write-Log "DISM exit code: $($dism.ExitCode)"

Write-Log "Running SFC /scannow..."
$sfc = Invoke-ExternalCommand -FilePath "sfc.exe" -Arguments "/scannow"
Write-Log "SFC exit code: $($sfc.ExitCode)"

Write-Log "Installing updates..."
$install = Install-WindowsUpdates -DownloadIfNeeded
Write-Log "Install Result: $($install.ResultCode), RebootRequired=$($install.RebootRequired), HResult=$($install.HResult)"

$pendingReboot = Test-PendingReboot
$needsReboot = $install.RebootRequired -or $pendingReboot

$rebootInfo = $null
if ($needsReboot) {
  Write-Log "Reboot required -> restarting computer..."
  $rebootStart = Get-Date
  Restart-Computer -Force

  # After this line, in local session you may lose console if remote; for local it continues only if script is scheduled.
  # For LOCAL DEBUG: comment Restart-Computer and test reboot detection with a manual reboot.

  Write-Log "Waiting for reboot cycle (timeout ${RebootWaitTimeoutSec}s)..."
  $rebootInfo = Wait-ForRebootCycle -StartTime $rebootStart -TimeoutSec $RebootWaitTimeoutSec -PollSec $RebootPollIntervalSec
  Write-Log "RebootDetected=$($rebootInfo.RebootDetected) LastBootUpTime=$($rebootInfo.LastBootUpTime)"
} else {
  Write-Log "Reboot not required."
}

Write-Log "Reading critical/error events since $sinceForEvents ..."
$events = Get-CriticalEvents -Since $sinceForEvents
Write-Log ("Critical/Error events: {0}" -f ($events.Count))

Write-Log "Re-checking updates after installation..."
$updatesAfter = Get-WindowsUpdates
Write-Log ("Updates remaining: {0}" -f $updatesAfter.Count)

$workflowEnd = Get-Date

$report = [pscustomobject]@{
  BasicInfo = $basicInfo
  UpdatesBeforeCount = $updatesBefore.Count
  UpdatesBefore = $updatesBefore
  DISM = $dism
  SFC  = $sfc
  Install = $install
  PendingRebootDetected = $pendingReboot
  Reboot = $rebootInfo
  UpdatesAfterCount = $updatesAfter.Count
  UpdatesAfter = $updatesAfter
  CriticalEventsCount = $events.Count
  CriticalEvents = $events
  WorkflowEnd = $workflowEnd
  DurationSec = [int]([timespan]($workflowEnd - $workflowStart)).TotalSeconds
}

Write-Host ""
Write-Host "===== MAINTENANCE SUMMARY ($env:COMPUTERNAME) ====="
Write-Host ("Updates before: {0} | after: {1}" -f $report.UpdatesBeforeCount, $report.UpdatesAfterCount)
Write-Host ("DISM exit: {0} | SFC exit: {1}" -f $report.DISM.ExitCode, $report.SFC.ExitCode)
Write-Host ("Install: {0} | RebootRequired: {1} | PendingReboot: {2}" -f $report.Install.ResultCode, $needsReboot, $report.PendingRebootDetected)
Write-Host ("Critical/Error events: {0}" -f $report.CriticalEventsCount)
Write-Host ("Duration (sec): {0}" -f $report.DurationSec)

if ($ExportJson) {
  if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
  $file = Join-Path $ExportPath ("MaintenanceReport_{0}_{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss"))
  $report | ConvertTo-Json -Depth 6 | Out-File -FilePath $file -Encoding UTF8
  Write-Log "Report exported: $file"
}

return $report
