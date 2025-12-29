#requires -Version 5.1
<#
  Maintenance workflow for a "normal" Windows Server (remote executed via WinRM).
  Steps:
    - Ensure PSWindowsUpdate module
    - Check available updates
    - DISM RestoreHealth
    - SFC /scannow
    - Install updates
    - If reboot required: reboot + wait handled by orchestrator (caller)
    - Collect EventLog Critical/Error after maintenance start
    - Output structured report object (JSON-friendly)
#>

[CmdletBinding()]
param(
  [string]$ReportRoot = "C:\MaintenanceReports",
  [switch]$InstallPSWindowsUpdate,
  [int]$EventLogLookbackHours = 24
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-ReportFolder {
  param([string]$Root)
  if (-not (Test-Path $Root)) { New-Item -Path $Root -ItemType Directory -Force | Out-Null }
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $path  = Join-Path $Root $env:COMPUTERNAME
  if (-not (Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
  $runPath = Join-Path $path $stamp
  New-Item -Path $runPath -ItemType Directory -Force | Out-Null
  return $runPath
}

function Invoke-External {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter()][string[]]$Arguments = @()
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = ($Arguments -join " ")
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow  = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  [pscustomobject]@{
    ExitCode = $p.ExitCode
    StdOut   = $stdout
    StdErr   = $stderr
  }
}

function Ensure-PSWindowsUpdate {
  param([switch]$DoInstall)
  $mod = Get-Module -ListAvailable -Name PSWindowsUpdate | Select-Object -First 1
  if ($mod) { return $true }

  if (-not $DoInstall) {
    return $false
  }

  # Enable TLS 1.2 for PSGallery on older systems
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

  # Ensure NuGet provider
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
  }

  # Trust PSGallery if needed (optional; in strict env you may skip and preconfigure)
  try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}

  Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers
  return $true
}

function Get-UpdatePreview {
  Import-Module PSWindowsUpdate -ErrorAction Stop
  # List only (do not install)
  $list = Get-WindowsUpdate -MicrosoftUpdate -IgnoreUserInput -ErrorAction Stop
  return $list
}

function Install-Updates {
  Import-Module PSWindowsUpdate -ErrorAction Stop
  # Install updates. No auto-reboot: we want orchestrator to control reboot & waiting.
  $result = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreUserInput -Confirm:$false -AutoReboot:$false -Verbose:$false
  return $result
}

function Get-RebootRequiredFlag {
  $paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
  )
  foreach ($p in $paths) {
    if (Test-Path $p) { return $true }
  }
  return $false
}

function Get-EventLogIssues {
  param([datetime]$Since)

  $filters = @(
    @{ LogName="System";      Level=1; StartTime=$Since }, # Critical
    @{ LogName="System";      Level=2; StartTime=$Since }, # Error
    @{ LogName="Application"; Level=1; StartTime=$Since },
    @{ LogName="Application"; Level=2; StartTime=$Since }
  )

  $events = foreach ($f in $filters) {
    try {
      Get-WinEvent -FilterHashtable $f -ErrorAction Stop |
        Select-Object TimeCreated, LogName, LevelDisplayName, Id, ProviderName, Message
    } catch {
      # If a log is inaccessible, continue
    }
  }

  # Keep output compact
  $events |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 200
}

# -------- MAIN --------
$startedAt = Get-Date
$reportDir = New-ReportFolder -Root $ReportRoot

$report = [ordered]@{
  ComputerName        = $env:COMPUTERNAME
  StartedAt           = $startedAt.ToString("s")
  ReportDir           = $reportDir
  Steps               = @()
  UpdatePreview       = @()
  UpdateInstallResult = @()
  Dism                = $null
  Sfc                 = $null
  RebootRequired      = $false
  EventLogIssues      = @()
  FinishedAt          = $null
  Success             = $false
}

# Step: ensure module
$hasWU = Ensure-PSWindowsUpdate -DoInstall:$InstallPSWindowsUpdate
$report.Steps += [pscustomobject]@{ Step="Ensure-PSWindowsUpdate"; Ok=$hasWU; Note=($(if($hasWU){"Module available"}else{"Missing: run with -InstallPSWindowsUpdate or preinstall"})) }

if (-not $hasWU) {
  $report.FinishedAt = (Get-Date).ToString("s")
  $report.Success = $false
  $json = $report | ConvertTo-Json -Depth 6
  $json | Out-File -FilePath (Join-Path $reportDir "report.json") -Encoding UTF8
  Write-Output $report
  exit 2
}

# Step: preview updates
try {
  $upd = Get-UpdatePreview
  $report.UpdatePreview = $upd | Select-Object Title, KB, Size, MsrcSeverity, Categories
  $report.Steps += [pscustomobject]@{ Step="Get-Updates"; Ok=$true; Count=($upd | Measure-Object).Count }
} catch {
  $report.Steps += [pscustomobject]@{ Step="Get-Updates"; Ok=$false; Error=$_.Exception.Message }
  throw
}

# Step: DISM
try {
  $dismRes = Invoke-External -FilePath "dism.exe" -Arguments @("/Online","/Cleanup-Image","/RestoreHealth")
  $report.Dism = $dismRes
  $ok = ($dismRes.ExitCode -eq 0)
  $report.Steps += [pscustomobject]@{ Step="DISM_RestoreHealth"; Ok=$ok; ExitCode=$dismRes.ExitCode }
  $dismRes.StdOut | Out-File (Join-Path $reportDir "dism_stdout.txt") -Encoding UTF8
  $dismRes.StdErr | Out-File (Join-Path $reportDir "dism_stderr.txt") -Encoding UTF8
} catch {
  $report.Steps += [pscustomobject]@{ Step="DISM_RestoreHealth"; Ok=$false; Error=$_.Exception.Message }
  throw
}

# Step: SFC
try {
  $sfcRes = Invoke-External -FilePath "sfc.exe" -Arguments @("/scannow")
  $report.Sfc = $sfcRes
  # sfc exit codes can be non-trivial; treat 0 as OK, others as warning
  $report.Steps += [pscustomobject]@{ Step="SFC_ScanNow"; Ok=($sfcRes.ExitCode -eq 0); ExitCode=$sfcRes.ExitCode }
  $sfcRes.StdOut | Out-File (Join-Path $reportDir "sfc_stdout.txt") -Encoding UTF8
  $sfcRes.StdErr | Out-File (Join-Path $reportDir "sfc_stderr.txt") -Encoding UTF8
} catch {
  $report.Steps += [pscustomobject]@{ Step="SFC_ScanNow"; Ok=$false; Error=$_.Exception.Message }
  throw
}

# Step: install updates (if any)
try {
  if (($report.UpdatePreview | Measure-Object).Count -gt 0) {
    $inst = Install-Updates
    $report.UpdateInstallResult = $inst | Select-Object Title, KB, Result, RebootRequired
    $report.Steps += [pscustomobject]@{ Step="Install-Updates"; Ok=$true; Installed=($inst | Measure-Object).Count }
  } else {
    $report.Steps += [pscustomobject]@{ Step="Install-Updates"; Ok=$true; Note="No updates available" }
  }
} catch {
  $report.Steps += [pscustomobject]@{ Step="Install-Updates"; Ok=$false; Error=$_.Exception.Message }
  throw
}

# Step: reboot required flag
$reboot = Get-RebootRequiredFlag
$report.RebootRequired = $reboot
$report.Steps += [pscustomobject]@{ Step="RebootRequired"; Ok=$true; Value=$reboot }

# Step: event log issues (after start time)
$since = (Get-Date).AddHours(-[math]::Abs($EventLogLookbackHours))
$issues = Get-EventLogIssues -Since $since
$report.EventLogIssues = $issues
$report.Steps += [pscustomobject]@{ Step="Collect-EventLogs"; Ok=$true; Count=($issues | Measure-Object).Count }

$report.FinishedAt = (Get-Date).ToString("s")
$report.Success = $true

# Save report
($report | ConvertTo-Json -Depth 8) | Out-File -FilePath (Join-Path $reportDir "report.json") -Encoding UTF8

Write-Output ([pscustomobject]$report)
exit 0
