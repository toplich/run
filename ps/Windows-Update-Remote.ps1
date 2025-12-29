# Maintenance-Workflow-Remote.ps1
# Runs on a target server (invoked remotely via WinRM).
# Produces a short report and returns an object with the results.

[CmdletBinding()]
param(
    [int]$EventLogHoursBack = 24,
    [string]$ReportRoot = "C:\Temp\MaintenanceReports",
    [int]$RebootTimeoutSec = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-ReportFolder {
    param([string]$Root)

    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $folder = Join-Path $Root ("Maintenance_" + $env:COMPUTERNAME + "_" + $stamp)
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    return $folder
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$Arguments,
        [int]$TimeoutSec = 0
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    if ($TimeoutSec -gt 0) {
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            throw "Command timeout after $TimeoutSec sec: $FilePath $Arguments"
        }
    } else {
        $p.WaitForExit() | Out-Null
    }

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout.Trim()
        StdErr   = $stderr.Trim()
        Command  = "$FilePath $Arguments"
    }
}

function Get-WindowsUpdates {
    # Uses Windows Update Agent COM API (no external modules).
    $session  = New-Object -ComObject "Microsoft.Update.Session"
    $searcher = $session.CreateUpdateSearcher()

    # If the machine is set to use WSUS by policy, WUA will follow that policy.
    # You requested "Windows Update or WSUS" check; this simply uses system configuration.
    $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    $updates = @()
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $u = $result.Updates.Item($i)
        $kb = @()
        try { $kb = @($u.KBArticleIDs) } catch {}

        $updates += [pscustomobject]@{
            Title        = $u.Title
            KBs          = ($kb -join ",")
            Categories   = (@($u.Categories | ForEach-Object { $_.Name }) -join "; ")
            IsDownloaded = [bool]$u.IsDownloaded
            RebootReq    = [bool]$u.RebootRequired
        }
    }

    [pscustomobject]@{
        Count   = $result.Updates.Count
        Updates = $updates
    }
}

function Install-WindowsUpdates {
    param(
        [Parameter(Mandatory)] $UpdatesSearchResult
    )

    $session = New-Object -ComObject "Microsoft.Update.Session"

    $toInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"
    foreach ($u in $UpdatesSearchResult.Updates) {
        # We need the actual COM updates, so we re-search and match by title.
        # This keeps the report object simple while still installing correctly.
        # Alternative: keep COM objects in memory (not serializable over remoting).
    }

    $searcher = $session.CreateUpdateSearcher()
    $raw = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    for ($i = 0; $i -lt $raw.Updates.Count; $i++) {
        $upd = $raw.Updates.Item($i)
        # Auto-accept EULA if needed
        if ($upd.EulaAccepted -eq $false) {
            $upd.AcceptEula()
        }
        [void]$toInstall.Add($upd)
    }

    if ($toInstall.Count -eq 0) {
        return [pscustomobject]@{
            InstalledCount = 0
            ResultCode     = "NotApplicable"
            RebootRequired = $false
            HResult        = 0
        }
    }

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $toInstall
    $dl = $downloader.Download()

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $toInstall
    $inst = $installer.Install()

    # ResultCode: 2 = Succeeded, 3 = SucceededWithErrors, 4 = Failed, 5 = Aborted
    [pscustomobject]@{
        InstalledCount = $inst.UpdatesInstalled
        ResultCode     = [string]$inst.ResultCode
        RebootRequired = [bool]$inst.RebootRequired
        HResult        = $inst.HResult
    }
}

function Get-CriticalEventLog {
    param(
        [int]$HoursBack
    )

    $start = (Get-Date).AddHours(-1 * $HoursBack)

    $providers = @("System", "Application")
    $events = foreach ($log in $providers) {
        try {
            Get-WinEvent -FilterHashtable @{
                LogName   = $log
                Level     = @([int]1, [int]2)  # 1=Critical, 2=Error
                StartTime = $start
            } -ErrorAction Stop |
            Select-Object TimeCreated, LogName, LevelDisplayName, Id, ProviderName, Message
        } catch {
            [pscustomobject]@{
                TimeCreated      = Get-Date
                LogName          = $log
                LevelDisplayName = "Error"
                Id               = 0
                ProviderName     = "MaintenanceScript"
                Message          = "Failed to read event log '$log': $($_.Exception.Message)"
            }
        }
    }

    return $events | Sort-Object TimeCreated -Descending
}

# -------------------- MAIN --------------------
$reportFolder = New-ReportFolder -Root $ReportRoot
$reportJson   = Join-Path $reportFolder "report.json"
$reportTxt    = Join-Path $reportFolder "report.txt"
$transcript   = Join-Path $reportFolder "transcript.txt"

Start-Transcript -Path $transcript -Force | Out-Null

$startedAt = Get-Date
$os = Get-CimInstance Win32_OperatingSystem
$summary = [ordered]@{
    ComputerName         = $env:COMPUTERNAME
    StartedAt            = $startedAt
    OS                   = "$($os.Caption) ($($os.Version))"
    LastBootUpTime       = $os.LastBootUpTime
    Steps                = @()
    Updates              = $null
    UpdateInstallResult  = $null
    RebootPlanned        = $false
    RebootPerformed      = $false
    PostEventLogHoursBack= $EventLogHoursBack
    PostCriticalEvents   = @()
    Errors               = @()
    FinishedAt           = $null
    DurationSec          = $null
    ReportFolder         = $reportFolder
}

try {
    # Step 1: Check updates
    $step = [ordered]@{ Name="CheckUpdates"; Started=(Get-Date); Finished=$null; Ok=$true; Details=$null }
    try {
        $upd = Get-WindowsUpdates
        $summary.Updates = $upd
        $step.Details = "Found $($upd.Count) update(s)."
    } catch {
        $step.Ok = $false
        $step.Details = $_.Exception.Message
        $summary.Errors += "CheckUpdates: $($_.Exception.Message)"
    }
    $step.Finished = Get-Date
    $summary.Steps += [pscustomobject]$step

    # Step 2: DISM RestoreHealth
    $step = [ordered]@{ Name="DISM_RestoreHealth"; Started=(Get-Date); Finished=$null; Ok=$true; Details=$null }
    try {
        $dism = Invoke-ExternalCommand -FilePath "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth"
        $step.Ok = ($dism.ExitCode -eq 0)
        $step.Details = "ExitCode=$($dism.ExitCode)"
        Set-Content -Path (Join-Path $reportFolder "dism_stdout.txt") -Value $dism.StdOut -Force
        Set-Content -Path (Join-Path $reportFolder "dism_stderr.txt") -Value $dism.StdErr -Force
    } catch {
        $step.Ok = $false
        $step.Details = $_.Exception.Message
        $summary.Errors += "DISM: $($_.Exception.Message)"
    }
    $step.Finished = Get-Date
    $summary.Steps += [pscustomobject]$step

    # Step 3: SFC
    $step = [ordered]@{ Name="SFC_ScanNow"; Started=(Get-Date); Finished=$null; Ok=$true; Details=$null }
    try {
        $sfc = Invoke-ExternalCommand -FilePath "sfc.exe" -Arguments "/scannow"
        # SFC often returns 0 on success; still keep output for review.
        $step.Ok = ($sfc.ExitCode -eq 0)
        $step.Details = "ExitCode=$($sfc.ExitCode)"
        Set-Content -Path (Join-Path $reportFolder "sfc_stdout.txt") -Value $sfc.StdOut -Force
        Set-Content -Path (Join-Path $reportFolder "sfc_stderr.txt") -Value $sfc.StdErr -Force
    } catch {
        $step.Ok = $false
        $step.Details = $_.Exception.Message
        $summary.Errors += "SFC: $($_.Exception.Message)"
    }
    $step.Finished = Get-Date
    $summary.Steps += [pscustomobject]$step

    # Step 4: Install updates
    $step = [ordered]@{ Name="InstallUpdates"; Started=(Get-Date); Finished=$null; Ok=$true; Details=$null }
    try {
        $install = Install-WindowsUpdates -UpdatesSearchResult $summary.Updates
        $summary.UpdateInstallResult = $install
        $step.Details = "Installed=$($install.InstalledCount), ResultCode=$($install.ResultCode), RebootRequired=$($install.RebootRequired), HResult=$($install.HResult)"
        $summary.RebootPlanned = [bool]$install.RebootRequired
    } catch {
        $step.Ok = $false
        $step.Details = $_.Exception.Message
        $summary.Errors += "InstallUpdates: $($_.Exception.Message)"
    }
    $step.Finished = Get-Date
    $summary.Steps += [pscustomobject]$step

    # Step 5: Planned reboot (if required)
    if ($summary.RebootPlanned) {
        $step = [ordered]@{ Name="Reboot"; Started=(Get-Date); Finished=$null; Ok=$true; Details=$null }
        try {
            $summary.RebootPerformed = $true
            $step.Details = "Reboot initiated by maintenance workflow."
            # Reboot immediately. Caller (orchestrator) should wait for WinRM to come back.
            Restart-Computer -Force
        } catch {
            $step.Ok = $false
            $step.Details = $_.Exception.Message
            $summary.Errors += "Reboot: $($_.Exception.Message)"
        }
        $step.Finished = Get-Date
        $summary.Steps += [pscustomobject]$step
    }

    # Step 6: Post-check event logs (note: if reboot happened, this part may run only if called again after boot)
    $step = [ordered]@{ Name="PostEventLog"; Started=(Get-Date); Finished=$null; Ok=$true; Details=$null }
    try {
        $events = Get-CriticalEventLog -HoursBack $EventLogHoursBack
        $summary.PostCriticalEvents = @($events)
        $step.Details = "Collected $($events.Count) critical/error event(s) in last $EventLogHoursBack hour(s)."
        $events | Export-Csv -Path (Join-Path $reportFolder "eventlog_critical_error.csv") -NoTypeInformation -Force -Encoding UTF8
    } catch {
        $step.Ok = $false
        $step.Details = $_.Exception.Message
        $summary.Errors += "PostEventLog: $($_.Exception.Message)"
    }
    $step.Finished = Get-Date
    $summary.Steps += [pscustomobject]$step
}
finally {
    $finishedAt = Get-Date
    $summary.FinishedAt  = $finishedAt
    $summary.DurationSec = [int]([TimeSpan]($finishedAt - $startedAt)).TotalSeconds

    # Save JSON report
    ($summary | ConvertTo-Json -Depth 6) | Set-Content -Path $reportJson -Force -Encoding UTF8

    # Save short TXT summary
    $txt = @()
    $txt += "Maintenance Report - $($summary.ComputerName)"
    $txt += "Started:  $($summary.StartedAt)"
    $txt += "Finished: $($summary.FinishedAt)"
    $txt += "Duration: $($summary.DurationSec) sec"
    $txt += "OS:       $($summary.OS)"
    $txt += "LastBoot: $($summary.LastBootUpTime)"
    $txt += ""
    if ($summary.Updates) {
        $txt += "Updates found: $($summary.Updates.Count)"
    }
    if ($summary.UpdateInstallResult) {
        $txt += "Install result: Installed=$($summary.UpdateInstallResult.InstalledCount), ResultCode=$($summary.UpdateInstallResult.ResultCode), RebootRequired=$($summary.UpdateInstallResult.RebootRequired), HResult=$($summary.UpdateInstallResult.HResult)"
    }
    $txt += "Reboot planned/performed: $($summary.RebootPlanned) / $($summary.RebootPerformed)"
    $txt += "Critical/Error events (last $EventLogHoursBack h): $(@($summary.PostCriticalEvents).Count)"
    if ($summary.Errors.Count -gt 0) {
        $txt += ""
        $txt += "Errors:"
        $summary.Errors | ForEach-Object { $txt += " - $_" }
    }

    $txt -join "`r`n" | Set-Content -Path $reportTxt -Force -Encoding UTF8

    Stop-Transcript | Out-Null
}

# Return as object
[pscustomobject]$summary
