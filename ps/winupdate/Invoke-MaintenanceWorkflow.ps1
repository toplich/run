<#
.SYNOPSIS
  Maintenance workflow (LOCAL debug): check updates, DISM, SFC, install updates, optional reboot, eventlog check, report.

.NOTES
  - Run locally (console/RDP) as Administrator for debugging.
  - Later for remote execution via WinRM, recommended approach is: create scheduled task on target (SYSTEM) and trigger it.
  - Comments are in English by request.
#>

[CmdletBinding()]
param(
  [int]$EventLogHoursBack = 6,
  [int]$RebootWaitTimeoutSec = 1800,
  [int]$RebootPollIntervalSec = 10,
  [switch]$DoReboot,                 # OFF by default for local debugging
  [switch]$ExportJson,
  [string]$ExportPath = "C:\Temp",
  [string]$LogRoot = "C:\Temp\MaintenanceLogs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------- helpers ----------------

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run PowerShell as Administrator." }
}

function New-LogFiles {
  param([string]$Root)

  if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }

  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $name  = $env:COMPUTERNAME
  $log   = Join-Path $Root ("Maintenance_{0}_{1}.log" -f $name, $stamp)
  $trn   = Join-Path $Root ("Maintenance_{0}_{1}.transcript.txt" -f $name, $stamp)

  return [pscustomobject]@{ LogFile = $log; Transcript = $trn }
}

$script:LogFile = $null

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
  )
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[{0}] {1}: {2}" -f $ts, $Level, $Message

  Write-Host $line
  if ($script:LogFile) {
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
  }
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

# ---------------- Windows Update (COM) ----------------

function Get-WindowsUpdates {
  # Returns list of available (not installed, not hidden) updates via Windows Update API (COM)
  $session  = New-Object -ComObject "Microsoft.Update.Session"
  $searcher = $session.CreateUpdateSearcher()
  $criteria = "IsInstalled=0 and IsHidden=0"
  $result = $searcher.Search($criteria)

  $list = @()
  $count = 0
  try { $count = [int]$result.Updates.Count } catch { $count = 0 }

  for ($i=0; $i -lt $count; $i++) {
    $u = $result.Updates.Item($i)
    $kb = @()
    try { $kb = @($u.KBArticleIDs) } catch {}
    $cats = @()
    try { $cats = @($u.Categories) | ForEach-Object { $_.Name } } catch {}

    $list += [pscustomobject]@{
      Title          = $u.Title
      KBs            = ($kb -join ",")
      IsDownloaded   = [bool]$u.IsDownloaded
      RebootRequired = [bool]$u.RebootRequired
      Categories     = ($cats -join ", ")
    }
  }

  return $list
}

function Invoke-DefenderSignatureUpdateFallback {
  # Fallback for Defender definition updates if WU COM fails (common in remoting contexts)
  $mpCmd = Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe"
  if (-not (Test-Path $mpCmd)) {
    $mpCmd = Join-Path ${env:ProgramFiles(x86)} "Windows Defender\MpCmdRun.exe"
  }
  if (-not (Test-Path $mpCmd)) {
    return [pscustomobject]@{ Tried=$false; ExitCode=$null; Note="MpCmdRun.exe not found." }
  }

  Write-Log "Fallback: running Defender signature update via MpCmdRun.exe ..." "WARN"
  $p = Start-Process -FilePath $mpCmd -ArgumentList "-SignatureUpdate" -Wait -PassThru -NoNewWindow
  return [pscustomobject]@{ Tried=$true; ExitCode=$p.ExitCode; Note="MpCmdRun -SignatureUpdate executed." }
}

function Install-WindowsUpdates {
  param([switch]$DownloadIfNeeded)

  # Default result object (always has fields to avoid strict-mode surprises)
  $resultObj = [pscustomobject]@{
    AvailableCount  = 0
    AttemptedCount  = 0
    SucceededCount  = 0
    FailedCount     = 0
    ResultCode      = "Unknown"
    RebootRequired  = $false
    HResult         = ""
    Error           = ""
    DefenderFallback= $null
  }

  try {
    $session  = New-Object -ComObject "Microsoft.Update.Session"
    $searcher = $session.CreateUpdateSearcher()
    $criteria = "IsInstalled=0 and IsHidden=0"
    $searchResult = $searcher.Search($criteria)

    $available = 0
    try { $available = [int]$searchResult.Updates.Count } catch { $available = 0 }
    $resultObj.AvailableCount = $available

    if ($available -eq 0) {
      $resultObj.ResultCode = "NoUpdates"
      return $resultObj
    }

    $updatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
    for ($i=0; $i -lt $available; $i++) {
      $u = $searchResult.Updates.Item($i)
      if (-not $u.EulaAccepted) { $u.AcceptEula() | Out-Null }
      $null = $updatesToInstall.Add($u)
    }

    $resultObj.AttemptedCount = $available

    if ($DownloadIfNeeded) {
      try {
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $null = $downloader.Download()
      } catch {
        Write-Log ("Download step failed: {0}" -f $_.Exception.Message) "WARN"
        # Continue to install attempt; some environments still proceed.
      }
    }

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $installResult = $installer.Install()

    $codeMap = @{
      0="NotStarted";1="InProgress";2="Succeeded";3="SucceededWithErrors";4="Failed";5="Aborted"
    }

    $resultObj.ResultCode     = $codeMap[[int]$installResult.ResultCode]
    $resultObj.RebootRequired = [bool]$installResult.RebootRequired

    # Count succeeded/failed per-update
    $succ = 0; $fail = 0
    for ($i=0; $i -lt $available; $i++) {
      $uRes = $installResult.GetUpdateResult($i)
      # OperationResultCode: 0 NotStarted, 1 InProgress, 2 Succeeded, 3 SucceededWithErrors, 4 Failed, 5 Aborted
      if ([int]$uRes.ResultCode -eq 2 -or [int]$uRes.ResultCode -eq 3) { $succ++ }
      elseif ([int]$uRes.ResultCode -eq 4 -or [int]$uRes.ResultCode -eq 5) { $fail++ }
    }
    $resultObj.SucceededCount = $succ
    $resultObj.FailedCount    = $fail

    try {
      $resultObj.HResult = ("0x{0:X8}" -f ($installResult.HResult -band 0xFFFFFFFF))
    } catch {
      $resultObj.HResult = ""
    }

    return $resultObj
  }
  catch {
    $msg = $_.Exception.Message
    $resultObj.ResultCode = "Exception"
    $resultObj.Error = $msg

    # If it's access denied, attempt Defender fallback (common case: only Defender definitions are pending)
    if ($msg -match "0x80070005" -or $msg -match "E_ACCESSDENIED" -or $msg -match "Zugriff verweigert") {
      $resultObj.DefenderFallback = Invoke-DefenderSignatureUpdateFallback
    }

    return $resultObj
  }
}

function Test-PendingReboot {
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

  while ((Get-Date) -lt $deadline) {
    try {
      $os = Get-CimInstance Win32_OperatingSystem
      $lastBoot = $os.LastBootUpTime
      if ($lastBoot -gt $StartTime.AddSeconds(-30)) {
        return [pscustomobject]@{ RebootDetected = $true; LastBootUpTime = $lastBoot }
      }
    } catch {
      # During reboot this may fail; ignore
    }
    Start-Sleep -Seconds $PollSec
  }

  return [pscustomobject]@{ RebootDetected = $false; LastBootUpTime = $null }
}

function Get-CriticalEvents {
  param([Parameter(Mandatory)][datetime]$Since)
  $filter = @{
    LogName    = @("System","Application")
    Level      = 1,2
    StartTime  = $Since
  }
  $events = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, LogName, LevelDisplayName, ProviderName, Id, Message

  return @($events)
}

# ---------------- MAIN ----------------

Assert-Admin

$workflowStart = Get-Date
$sinceForEvents = (Get-Date).AddHours(-1 * $EventLogHoursBack)

$lf = New-LogFiles -Root $LogRoot
$script:LogFile = $lf.LogFile

Start-Transcript -Path $lf.Transcript -Force | Out-Null

try {
  Write-Log "Maintenance workflow started on $env:COMPUTERNAME"
  Write-Log "Logs: $($lf.LogFile)"
  Write-Log "Transcript: $($lf.Transcript)"

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
  $updatesBeforeCount = @($updatesBefore).Count
  Write-Log ("Updates found: {0}" -f $updatesBeforeCount)

  Write-Log "Running DISM RestoreHealth..."
  $dism = Invoke-ExternalCommand -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth"
  Write-Log "DISM exit code: $($dism.ExitCode)"

  Write-Log "Running SFC /scannow..."
  $sfc = Invoke-ExternalCommand -FilePath "sfc.exe" -Arguments "/scannow"
  Write-Log "SFC exit code: $($sfc.ExitCode)"

  Write-Log "Installing updates..."
  $install = Install-WindowsUpdates -DownloadIfNeeded
  if ($install.ResultCode -eq "Exception") {
    Write-Log ("Install-WindowsUpdates exception: {0}" -f $install.Error) "WARN"
  }
  if ($install.DefenderFallback) {
    Write-Log ("Defender fallback tried={0} exit={1} note={2}" -f `
      $install.DefenderFallback.Tried, $install.DefenderFallback.ExitCode, $install.DefenderFallback.Note) "WARN"
  }

  Write-Log ("Install Result: {0} | Attempted={1} Succeeded={2} Failed={3} | RebootRequired={4} | HResult={5}" -f `
    $install.ResultCode, $install.AttemptedCount, $install.SucceededCount, $install.FailedCount, $install.RebootRequired, $install.HResult)

  $pendingReboot = Test-PendingReboot
  $needsReboot = [bool]($install.RebootRequired -or $pendingReboot)

  $rebootInfo = $null
  if ($needsReboot) {
    Write-Log ("Reboot required detected (WU={0} PendingReboot={1})." -f $install.RebootRequired, $pendingReboot) "WARN"
    if ($DoReboot) {
      Write-Log "DoReboot is ON -> restarting computer..."
      $rebootStart = Get-Date
      Restart-Computer -Force

      Write-Log "Waiting for reboot cycle..."
      $rebootInfo = Wait-ForRebootCycle -StartTime $rebootStart -TimeoutSec $RebootWaitTimeoutSec -PollSec $RebootPollIntervalSec
      Write-Log "RebootDetected=$($rebootInfo.RebootDetected) LastBootUpTime=$($rebootInfo.LastBootUpTime)"
    } else {
      Write-Log "DoReboot is OFF (local debug) -> skipping Restart-Computer." "WARN"
    }
  } else {
    Write-Log "Reboot not required."
  }

  Write-Log "Reading critical/error events since $sinceForEvents ..."
  $events = Get-CriticalEvents -Since $sinceForEvents
  $eventsCount = @($events).Count
  Write-Log ("Critical/Error events: {0}" -f $eventsCount)

  Write-Log "Re-checking updates after installation..."
  $updatesAfter = Get-WindowsUpdates
  $updatesAfterCount = @($updatesAfter).Count
  Write-Log ("Updates remaining: {0}" -f $updatesAfterCount)

  $workflowEnd = Get-Date

  $report = [pscustomobject]@{
    BasicInfo             = $basicInfo
    UpdatesBeforeCount    = $updatesBeforeCount
    UpdatesBefore         = $updatesBefore
    DISM                  = $dism
    SFC                   = $sfc
    Install               = $install
    PendingRebootDetected = $pendingReboot
    NeedsReboot           = $needsReboot
    Reboot                = $rebootInfo
    UpdatesAfterCount     = $updatesAfterCount
    UpdatesAfter          = $updatesAfter
    CriticalEventsCount   = $eventsCount
    CriticalEvents        = $events
    WorkflowEnd           = $workflowEnd
    DurationSec           = [int]([timespan]($workflowEnd - $workflowStart)).TotalSeconds
    LogFile               = $lf.LogFile
    TranscriptFile        = $lf.Transcript
  }

  Write-Host ""
  Write-Host "===== MAINTENANCE SUMMARY ($env:COMPUTERNAME) ====="
  Write-Host ("Updates before: {0} | after: {1}" -f $report.UpdatesBeforeCount, $report.UpdatesAfterCount)
  Write-Host ("DISM exit: {0} | SFC exit: {1}" -f $report.DISM.ExitCode, $report.SFC.ExitCode)
  Write-Host ("Install: {0} | Attempted: {1} | Succeeded: {2} | Failed: {3}" -f `
    $report.Install.ResultCode, $report.Install.AttemptedCount, $report.Install.SucceededCount, $report.Install.FailedCount)
  Write-Host ("NeedsReboot: {0} (PendingReboot={1}) | DoReboot: {2}" -f $report.NeedsReboot, $report.PendingRebootDetected, [bool]$DoReboot)
  Write-Host ("Critical/Error events: {0}" -f $report.CriticalEventsCount)
  Write-Host ("Duration (sec): {0}" -f $report.DurationSec)
  Write-Host ("LogFile: {0}" -f $report.LogFile)
  Write-Host ("Transcript: {0}" -f $report.TranscriptFile)

  if ($ExportJson) {
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    $file = Join-Path $ExportPath ("MaintenanceReport_{0}_{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd_HHmmss"))
    $report | ConvertTo-Json -Depth 8 | Out-File -FilePath $file -Encoding UTF8
    Write-Log "Report exported: $file"
  }

  $report
}
finally {
  Stop-Transcript | Out-Null
}
