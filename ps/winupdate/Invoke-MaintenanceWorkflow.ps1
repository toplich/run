<# 
.SYNOPSIS
  Maintenance workflow: check updates, DISM, SFC, install updates, (optional) reboot, eventlog check, report.

.NOTES
  Local-debug first.
  Requires: Run as Administrator.
#>

[CmdletBinding()]
param(
  [int]$EventLogHoursBack = 6,
  [int]$RebootWaitTimeoutSec = 1800,   # 30 min
  [int]$RebootPollIntervalSec = 10,

  # IMPORTANT for local debugging: reboot is OFF by default
  [switch]$DoReboot,

  [switch]$ExportJson,
  [string]$ExportPath = "C:\Temp"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------- Logging (file + transcript) --------
$LogDir = Join-Path $ExportPath "MaintenanceLogs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir ("Maintenance_{0}_{1}.log" -f $env:COMPUTERNAME, $RunStamp)
$TranscriptFile = Join-Path $LogDir ("Maintenance_{0}_{1}.transcript.txt" -f $env:COMPUTERNAME, $RunStamp)

Start-Transcript -Path $TranscriptFile -Force | Out-Null

function Write-Log {
  param([Parameter(Mandatory)][string]$Message)
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] $Message"
  Write-Host $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run PowerShell as Administrator." }
}

function Invoke-ExternalCommand {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$Arguments
  )
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
  return [pscustomobject]@{
    FilePath  = $FilePath
    Arguments = $Arguments
    ExitCode  = $p.ExitCode
  }
}

function New-UpdateSession {
  try {
    return New-Object -ComObject "Microsoft.Update.Session"
  } catch {
    throw "Cannot create Windows Update COM session (Microsoft.Update.Session). Error: $($_.Exception.Message)"
  }
}

function Get-WindowsUpdates {
  # Always returns an array (possibly empty)
  $updates = @()

  try {
    $session  = New-UpdateSession
    $searcher = $session.CreateUpdateSearcher()
    $criteria = "IsInstalled=0 and IsHidden=0"
    $result = $searcher.Search($criteria)

    for ($i=0; $i -lt $result.Updates.Count; $i++) {
      $u = $result.Updates.Item($i)

      $kb = @()
      try { $kb = @($u.KBArticleIDs) } catch { $kb = @() }

      $catNames = @()
      try { $catNames = @($u.Categories | ForEach-Object { $_.Name }) } catch { $catNames = @() }

      $updates += [pscustomobject]@{
        Title          = $u.Title
        KBs            = ($kb -join ",")
        IsDownloaded   = [bool]$u.IsDownloaded
        RebootRequired = [bool]$u.RebootRequired
        Categories     = ($catNames -join ", ")
      }
    }
  } catch {
    # Keep script running; return empty array but log the issue
    Write-Log "WARNING: Get-WindowsUpdates failed: $($_.Exception.Message)"
    $updates = @()
  }

  return ,$updates
}

function Install-WindowsUpdates {
  param([switch]$DownloadIfNeeded)

  try {
    $session  = New-UpdateSession
    $searcher = $session.CreateUpdateSearcher()
    $criteria = "IsInstalled=0 and IsHidden=0"
    $searchResult = $searcher.Search($criteria)

    $availableCount = [int]$searchResult.Updates.Count
    if ($availableCount -eq 0) {
      return [pscustomobject]@{
        AvailableCount   = 0
        AttemptedCount   = 0
        SucceededCount   = 0
        FailedCount      = 0
        ResultCode       = "NoUpdates"
        RebootRequired   = $false
        HResult          = $null
      }
    }

    $updatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
    for ($i=0; $i -lt $availableCount; $i++) {
      $u = $searchResult.Updates.Item($i)
      if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }
      $null = $updatesToInstall.Add($u)
    }

    if ($DownloadIfNeeded) {
      try {
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $null = $downloader.Download()
      } catch {
        Write-Log "WARNING: Download step failed: $($_.Exception.Message)"
      }
    }

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $installResult = $installer.Install()

    $codeMap = @{
      0="NotStarted";1="InProgress";2="Succeeded";3="SucceededWithErrors";4="Failed";5="Aborted"
    }

    # Count per-update results
    $attempted = [int]$updatesToInstall.Count
    $succ = 0
    $fail = 0
    for ($i=0; $i -lt $attempted; $i++) {
      try {
        $ur = $installResult.GetUpdateResult($i)
        # OperationResultCode: 0..5 (same mapping)
        if ([int]$ur.ResultCode -eq 2 -or [int]$ur.ResultCode -eq 3) { $succ++ }
        elseif ([int]$ur.ResultCode -eq 4) { $fail++ }
      } catch {
        $fail++
      }
    }

    return [pscustomobject]@{
      AvailableCount   = $availableCount
      AttemptedCount   = $attempted
      SucceededCount   = $succ
      FailedCount      = $fail
      ResultCode       = $codeMap[[int]$installResult.ResultCode]
      RebootRequired   = [bool]$installResult.RebootRequired
      HResult          = ("0x{0:X8}" -f ($installResult.HResult -band 0xFFFFFFFF))
    }
  } catch {
    return [pscustomobject]@{
      AvailableCount   = $null
      AttemptedCount   = 0
      SucceededCount   = 0
      FailedCount      = 0
      ResultCode       = "Exception"
      RebootRequired   = $false
      HResult          = $null
      Error            = $_.Exception.Message
    }
  }
}

function Test-PendingReboot {
  $paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
  )
  foreach ($p in $paths) {
    if (Test-Path $p) { return $true }
  }

  try {
    $v = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($null -ne $v) { return $true }
  } catch {}
  return $false
}

function Wait-ForRebootCycle {
  param(
    [Parameter(Mandatory)][datetime]$StartTime,
    [int]$TimeoutSec,
    [int]$PollSec
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $os = Get-CimInstance Win32_OperatingSystem
      $lastBoot = $os.LastBootUpTime
      if ($lastBoot -gt $StartTime.AddSeconds(-30)) {
        return [pscustomobject]@{ RebootDetected = $true; LastBootUpTime = $lastBoot }
      }
    } catch {
      # During reboot remote calls can fail -> ignore
    }
    Start-Sleep -Seconds $PollSec
  }
  return [pscustomobject]@{ RebootDetected = $false; LastBootUpTime = $null }
}

function Get-CriticalEvents {
  param([Parameter(Mandatory)][datetime]$Since)

  $filter = @{
    LogName   = @("System","Application")
    Level     = 1,2  # 1=Critical, 2=Error
    StartTime = $Since
  }

  try {
    $events = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
      Select-Object TimeCreated, LogName, LevelDisplayName, ProviderName, Id, Message
    return ,@($events)
  } catch {
    Write-Log "WARNING: Get-WinEvent failed: $($_.Exception.Message)"
    return ,@()
  }
}

# ---------------- MAIN ----------------
try {
  Assert-Admin

  $workflowStart = Get-Date
  $sinceForEvents = (Get-Date).AddHours(-1 * $EventLogHoursBack)

  Write-Log "Maintenance workflow started on $env:COMPUTERNAME"
  Write-Log "Logs: $LogFile"
  Write-Log "Transcript: $TranscriptFile"

  $osInfo = Get-CimInstance Win32_OperatingSystem
  $basicInfo = [pscustomobject]@{
    ComputerName   = $env:COMPUTERNAME
    OS             = $osInfo.Caption
    Version        = $osInfo.Version
    LastBootUpTime = $osInfo.LastBootUpTime
    WorkflowStart  = $workflowStart
  }

  Write-Log "Checking available updates..."
  $updatesBefore = Get-WindowsUpdates
  Write-Log ("Updates found: {0}" -f @($updatesBefore).Count)

  Write-Log "Running DISM RestoreHealth..."
  $dism = Invoke-ExternalCommand -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth"
  Write-Log "DISM exit code: $($dism.ExitCode)"

  Write-Log "Running SFC /scannow..."
  $sfc = Invoke-ExternalCommand -FilePath "sfc.exe" -Arguments "/scannow"
  Write-Log "SFC exit code: $($sfc.ExitCode)"

  Write-Log "Installing updates..."
  $install = Install-WindowsUpdates -DownloadIfNeeded
  Write-Log ("Install Result: {0} | Attempted={1} Succeeded={2} Failed={3} | RebootRequired={4} | HResult={5}" -f `
    $install.ResultCode, $install.AttemptedCount, $install.SucceededCount, $install.FailedCount, $install.RebootRequired, $install.HResult)

  if ($install.ResultCode -eq "Exception") {
    Write-Log "WARNING: Install-WindowsUpdates exception: $($install.Error)"
  }

  $pendingReboot = Test-PendingReboot
  $needsReboot = [bool]$install.RebootRequired -or [bool]$pendingReboot

  $rebootInfo = $null
  if ($needsReboot) {
    Write-Log "Reboot required detected (WU=$($install.RebootRequired) PendingReboot=$pendingReboot)."

    if ($DoReboot) {
      Write-Log "DoReboot is ON -> restarting computer..."
      $rebootStart = Get-Date
      Restart-Computer -Force

      Write-Log "Waiting for reboot cycle (timeout ${RebootWaitTimeoutSec}s)..."
      $rebootInfo = Wait-ForRebootCycle -StartTime $rebootStart -TimeoutSec $RebootWaitTimeoutSec -PollSec $RebootPollIntervalSec
      Write-Log "RebootDetected=$($rebootInfo.RebootDetected) LastBootUpTime=$($rebootInfo.LastBootUpTime)"
    } else {
      Write-Log "DoReboot is OFF (local debug) -> skipping Restart-Computer."
    }
  } else {
    Write-Log "Reboot not required."
  }

  Write-Log "Reading critical/error events since $sinceForEvents ..."
  $events = Get-CriticalEvents -Since $sinceForEvents
  Write-Log ("Critical/Error events: {0}" -f @($events).Count)

  Write-Log "Re-checking updates after installation..."
  $updatesAfter = Get-WindowsUpdates
  Write-Log ("Updates remaining: {0}" -f @($updatesAfter).Count)

  $workflowEnd = Get-Date

  $report = [pscustomobject]@{
    BasicInfo              = $basicInfo
    UpdatesBeforeCount     = @($updatesBefore).Count
    UpdatesBefore          = $updatesBefore
    DISM                   = $dism
    SFC                    = $sfc
    Install                = $install
    PendingRebootDetected  = $pendingReboot
    NeedsReboot            = $needsReboot
    Reboot                 = $rebootInfo
    UpdatesAfterCount      = @($updatesAfter).Count
    UpdatesAfter           = $updatesAfter
    CriticalEventsCount    = @($events).Count
    CriticalEvents         = $events
    WorkflowEnd            = $workflowEnd
    DurationSec            = [int]([timespan]($workflowEnd - $workflowStart)).TotalSeconds
    LogFile                = $LogFile
    TranscriptFile         = $TranscriptFile
  }

  Write-Host ""
  Write-Host "===== MAINTENANCE SUMMARY ($env:COMPUTERNAME) ====="
  Write-Host ("Updates before: {0} | after: {1}" -f $report.UpdatesBeforeCount, $report.UpdatesAfterCount)
  Write-Host ("DISM exit: {0} | SFC exit: {1}" -f $report.DISM.ExitCode, $report.SFC.ExitCode)
  Write-Host ("Install: {0} | Attempted: {1} | Succeeded: {2} | Failed: {3}" -f $report.Install.ResultCode, $report.Install.AttemptedCount, $report.Install.SucceededCount, $report.Install.FailedCount)
  Write-Host ("NeedsReboot: {0} (PendingReboot={1}) | DoReboot: {2}" -f $report.NeedsReboot, $report.PendingRebootDetected, [bool]$DoReboot)
  Write-Host ("Critical/Error events: {0}" -f $report.CriticalEventsCount)
  Write-Host ("Duration (sec): {0}" -f $report.DurationSec)
  Write-Host ("LogFile: {0}" -f $report.LogFile)
  Write-Host ("Transcript: {0}" -f $report.TranscriptFile)

  if ($ExportJson) {
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    $file = Join-Path $ExportPath ("MaintenanceReport_{0}_{1}.json" -f $env:COMPUTERNAME, $RunStamp)
    $report | ConvertTo-Json -Depth 6 | Out-File -FilePath $file -Encoding UTF8
    Write-Log "Report exported: $file"
  }

  $report
}
finally {
  Stop-Transcript | Out-Null
}
