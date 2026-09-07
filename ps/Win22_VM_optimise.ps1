#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Server 2022 performance/optimization script for VMware vSphere/ESXi guest VMs.

.DESCRIPTION
    Applies a broad set of guest-OS-side tunings recommended for Windows Server 2022
    running as a VMware virtual machine: power management, network adapter (VMXNET3)
    tuning, storage/TRIM, time sync, telemetry/scheduled task cleanup, visual effects,
    page file, event logs, and optional (opt-in, higher-risk) hardening-adjacent tweaks.

    Design goals:
      - Safe-by-default: anything that reduces security or could break specific
        workloads is gated behind an explicit switch parameter (off by default).
      - Idempotent: re-running the script should not error or double-apply changes.
      - Logged: every action is written to a transcript + console with clear tags.
      - VMware-aware: skips VMware Tools steps gracefully if VMware Tools isn't
        installed (e.g. testing on bare metal or another hypervisor).

.PARAMETER IncludeAggressive
    Enables extra tweaks that are commonly recommended but carry more risk/trade-offs:
    disabling Windows Search service, disabling Print Spooler, disabling IPv6 on
    adapters, disabling NetBIOS over TCP/IP. Review before use on production DCs/
    file/print servers.

.PARAMETER DisableWindowsUpdateAutomaticRestart
    Prevents automatic reboots after Windows Update installs (does NOT disable
    updates themselves). Recommended for servers with scheduled maintenance windows.

.PARAMETER FixedPageFileGB
    If specified, sets a fixed-size page file (in GB) on C:\ instead of leaving it
    system-managed. Leave unset to keep Windows-managed sizing (generally fine on
    Server 2022 with VMware memory ballooning in play).

.PARAMETER SkipReboot
    Suppresses the "changes require reboot" prompt/summary line (script never
    reboots automatically on its own either way).

.NOTES
    Run this INSIDE the guest OS (elevated PowerShell), not on the ESXi host.
    Test in a snapshot/clone first. Review the -IncludeAggressive section before
    using on domain controllers, file servers, or print servers.

    Author: generated for Stevit (ukrgsm.com infra)
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeAggressive,
    [switch]$DisableWindowsUpdateAutomaticRestart,
    [int]$FixedPageFileGB,
    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'
$logDir  = 'C:\ProgramData\WS2022-VMware-Optimize'
$logFile = Join-Path $logDir ("optimize-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null

$script:RebootNeeded = $false

function Write-Step {
    param([string]$Message, [string]$Tag = 'INFO')
    $color = switch ($Tag) {
        'OK'   { 'Green' }
        'SKIP' { 'DarkYellow' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host "[$Tag] $Message" -ForegroundColor $color
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord','String','QWord','Binary','ExpandString','MultiString')]
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Disable-ServiceSafely {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Step "Service '$Name' not found, skipping." 'SKIP'
        return
    }
    try {
        if ($svc.Status -ne 'Stopped') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        Write-Step "Service '$Name' stopped and disabled." 'OK'
    } catch {
        Write-Step "Could not disable service '$Name': $($_.Exception.Message)" 'WARN'
    }
}

Write-Step "=== Windows Server 2022 / VMware guest optimization starting ===" 'INFO'
Write-Step "Log file: $logFile" 'INFO'

# ---------------------------------------------------------------------------
# 0. Detect VMware guest environment
# ---------------------------------------------------------------------------
$isVMwareGuest = $false
try {
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($bios.SerialNumber -match 'VMware' -or $cs.Manufacturer -match 'VMware') {
        $isVMwareGuest = $true
    }
} catch {}

if ($isVMwareGuest) {
    Write-Step "Detected VMware virtual hardware." 'OK'
} else {
    Write-Step "VMware virtual hardware not detected — continuing anyway (some steps will self-skip)." 'WARN'
}

$vmwareToolsSvc = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue
$hasVMwareTools = $null -ne $vmwareToolsSvc

# ---------------------------------------------------------------------------
# 1. Power management — force High Performance (avoid CPU throttling from
#    guest-side power plans; ESXi already handles physical power management)
# ---------------------------------------------------------------------------
Write-Step "--- Power plan ---" 'INFO'
try {
    $highPerf = powercfg -list | Select-String 'High performance'
    if ($highPerf) {
        $guid = ($highPerf.ToString() -split '\s+')[3]
        powercfg -setactive $guid | Out-Null
        Write-Step "Active power plan set to High performance." 'OK'
    } else {
        # Duplicate the built-in High performance GUID (present even if hidden) and activate it
        powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        Write-Step "High performance power plan created and activated." 'OK'
    }
    powercfg -change -monitor-timeout-ac 0
    powercfg -change -disk-timeout-ac 0
    powercfg -change -standby-timeout-ac 0
    powercfg -change -hibernate-timeout-ac 0
    powercfg -hibernate off
    Write-Step "Sleep/hibernate/timeouts disabled (not applicable for a server VM)." 'OK'
} catch {
    Write-Step "Power plan configuration failed: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 2. VMware Tools — time sync tuning
#    Best practice: let the guest sync only at specific events (boot/resume/
#    snapshot), not continuously — continuous VMware Tools sync fights with
#    w32time and causes clock drift/jumps. Use w32time against a real NTP
#    source (or the domain hierarchy) for ongoing sync instead.
# ---------------------------------------------------------------------------
Write-Step "--- Time synchronization ---" 'INFO'
if ($hasVMwareTools) {
    $vmwareToolsExe = @(
        "$env:ProgramFiles\VMware\VMware Tools\VMwareToolboxCmd.exe",
        "${env:ProgramFiles(x86)}\VMware\VMware Tools\VMwareToolboxCmd.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($vmwareToolsExe) {
        try {
            & $vmwareToolsExe timesync disable | Out-Null
            Write-Step "Disabled continuous VMware Tools periodic time sync (boot/resume sync still applies via VMX)." 'OK'
        } catch {
            Write-Step "Could not toggle VMware Tools time sync via CLI: $($_.Exception.Message)" 'WARN'
        }
    } else {
        Write-Step "VMwareToolboxCmd.exe not found; skipping VMware Tools time-sync toggle." 'SKIP'
    }

    # Registry fallback / explicit disable of periodic sync (tools.syncTime)
    $vmToolsRegPath = 'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools\TimeSync'
    if (Test-Path 'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools') {
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools' -Name 'Disabled' -Value 1
    }
} else {
    Write-Step "VMware Tools service not detected — skipping VMware time-sync steps. Install open-vm-tools/VMware Tools for guest optimizations (balloon driver, heartbeat, quiesced snapshots, clean shutdown)." 'WARN'
}

# If domain-joined, w32time already syncs from the domain hierarchy — leave it.
# If NOT domain-joined, point w32time at reliable external NTP servers.
try {
    $partOfDomain = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    if (-not $partOfDomain) {
        w32tm /config /manualpeerlist:"pool.ntp.org,0x8 time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update | Out-Null
        Restart-Service w32time -Force
        Write-Step "Standalone server: w32time configured against pool.ntp.org / time.windows.com." 'OK'
    } else {
        Write-Step "Domain-joined: leaving w32time on the domain hierarchy (recommended)." 'OK'
    }
} catch {
    Write-Step "w32time configuration failed: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 3. Network adapter tuning (VMXNET3)
#    Disable offloads/features known to occasionally cause issues on VMXNET3
#    under load, and enable RSS for multi-queue scaling. These are the common
#    VMware KB-recommended toggles — adjust if your workload benefits from
#    offloading (test before/after with your actual traffic pattern).
# ---------------------------------------------------------------------------
Write-Step "--- Network adapter (VMXNET3) tuning ---" 'INFO'
$vmxnetAdapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'vmxnet3' -and $_.Status -eq 'Up' }

if ($vmxnetAdapters) {
    foreach ($nic in $vmxnetAdapters) {
        Write-Step "Tuning adapter: $($nic.Name) ($($nic.InterfaceDescription))" 'INFO'
        try { Enable-NetAdapterRss -Name $nic.Name -ErrorAction SilentlyContinue } catch {}
        try { Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Large Send Offload V2 (IPv4)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue } catch {}
        try { Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Large Send Offload V2 (IPv6)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue } catch {}
        try { Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Recv Segment Coalescing (IPv4)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue } catch {}
        try { Set-NetAdapterAdvancedProperty -Name $nic.Name -DisplayName "Recv Segment Coalescing (IPv6)" -DisplayValue "Disabled" -ErrorAction SilentlyContinue } catch {}
        Write-Step "Applied RSS-on / LSO-off / RSC-off where supported by this adapter's advanced properties." 'OK'
    }
} else {
    Write-Step "No 'Up' VMXNET3 adapters found — skipping NIC-specific tuning (safe if using E1000E or adapter is down)." 'SKIP'
}

# TCP stack: enable modern congestion provider, disable legacy heuristics that
# can misfire on virtual NICs.
try {
    Set-NetTCPSetting -SettingName InternetCustom -CongestionProvider CUBIC -ErrorAction SilentlyContinue
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    netsh int tcp set global chimney=disabled | Out-Null
    Write-Step "TCP global settings: autotuning=normal, RSS=enabled, chimney offload=disabled." 'OK'
} catch {
    Write-Step "TCP global tuning failed: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 4. Storage — TRIM/UNMAP + disable scheduled defrag
#    VMware thin-provisioned/SAN-backed disks benefit from UNMAP reclaiming
#    space; scheduled defrag is pointless and I/O-wasteful on virtual disks.
# ---------------------------------------------------------------------------
Write-Step "--- Storage / TRIM ---" 'INFO'
try {
    # DisableDeleteNotify = 0 means TRIM/UNMAP IS enabled (confusingly named)
    fsutil behavior set DisableDeleteNotify 0 | Out-Null
    Write-Step "TRIM/UNMAP (DisableDeleteNotify=0) confirmed enabled for all volumes." 'OK'
} catch {
    Write-Step "Could not set fsutil DisableDeleteNotify: $($_.Exception.Message)" 'WARN'
}

try {
    Get-ScheduledTask -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    Write-Step "Scheduled defrag task disabled (irrelevant/harmful on virtual disks)." 'OK'
} catch {
    Write-Step "Could not disable ScheduledDefrag task: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 5. Memory — Superfetch/SysMain off (server workloads rarely benefit; also
#    reduces background disk I/O that competes with the VMware balloon driver)
# ---------------------------------------------------------------------------
Write-Step "--- Memory / SysMain ---" 'INFO'
Disable-ServiceSafely -Name 'SysMain'

# ---------------------------------------------------------------------------
# 6. Visual effects — set for best performance (server has no interactive
#    desktop workload to justify Aero-style effects)
# ---------------------------------------------------------------------------
Write-Step "--- Visual effects ---" 'INFO'
try {
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type String
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type Binary
    Write-Step "Visual effects set to 'Best performance'." 'OK'
} catch {
    Write-Step "Visual effects tuning failed: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 7. Server Manager — stop auto-launch at logon (saves resources on RDP/
#    console logons, purely cosmetic/annoyance fix)
# ---------------------------------------------------------------------------
Write-Step "--- Server Manager auto-start ---" 'INFO'
try {
    Get-ScheduledTask -TaskName 'ServerManager' -TaskPath '\Microsoft\Windows\Server Manager\' -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
    Write-Step "Server Manager will no longer auto-launch at logon." 'OK'
} catch {
    Write-Step "Server Manager auto-start tweak failed: $($_.Exception.Message)" 'WARN'
}

# Disable "Shutdown Event Tracker" prompt (annoyance on a server VM you manage directly)
try {
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' -Name 'ShutdownReasonOn' -Value 0
    Write-Step "Shutdown Event Tracker dialog disabled." 'OK'
} catch {
    Write-Step "Could not disable Shutdown Event Tracker: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 8. Telemetry / scheduled tasks cleanup (safe subset — does not touch
#    Windows Update, Defender, or licensing-related tasks)
# ---------------------------------------------------------------------------
Write-Step "--- Telemetry & scheduled task cleanup ---" 'INFO'
try {
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0
    Write-Step "Telemetry level set to 0 (Security/Enterprise minimum, requires LTSC/Enterprise-equivalent SKU to fully take effect)." 'OK'
} catch {
    Write-Step "Telemetry policy write failed: $($_.Exception.Message)" 'WARN'
}

$tasksToDisable = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
)
foreach ($taskPath in $tasksToDisable) {
    $name = Split-Path $taskPath -Leaf
    $path = (Split-Path $taskPath -Parent) + '\'
    $task = Get-ScheduledTask -TaskName $name -TaskPath $path -ErrorAction SilentlyContinue
    if ($task) {
        Disable-ScheduledTask -TaskName $name -TaskPath $path -ErrorAction SilentlyContinue | Out-Null
        Write-Step "Disabled scheduled task: $taskPath" 'OK'
    } else {
        Write-Step "Task not present, skipping: $taskPath" 'SKIP'
    }
}

# ---------------------------------------------------------------------------
# 9. Page file — leave system-managed unless a fixed size was requested
# ---------------------------------------------------------------------------
Write-Step "--- Page file ---" 'INFO'
if ($PSBoundParameters.ContainsKey('FixedPageFileGB')) {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $cs.AutomaticManagedPagefile = $false
        $cs | Put-CimInstance | Out-Null
        $pf = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
        $sizeMB = $FixedPageFileGB * 1024
        if ($pf) {
            Set-CimInstance -InputObject $pf -Property @{ InitialSize = $sizeMB; MaximumSize = $sizeMB } | Out-Null
        } else {
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name = 'C:\pagefile.sys'; InitialSize = $sizeMB; MaximumSize = $sizeMB
            } | Out-Null
        }
        Write-Step "Fixed page file set to ${FixedPageFileGB}GB on C:\." 'OK'
        $script:RebootNeeded = $true
    } catch {
        Write-Step "Fixed page file configuration failed: $($_.Exception.Message)" 'WARN'
    }
} else {
    Write-Step "Leaving page file system-managed (recommended default; revisit only if you see pagefile-related warnings)." 'INFO'
}

# ---------------------------------------------------------------------------
# 10. Event logs — bump size so rotation doesn't lose data on a busy VM
# ---------------------------------------------------------------------------
Write-Step "--- Event log sizing ---" 'INFO'
try {
    wevtutil sl Application /ms:104857600  # 100 MB
    wevtutil sl System      /ms:104857600
    wevtutil sl Security    /ms:262144000  # 250 MB
    Write-Step "Application/System logs set to 100MB, Security to 250MB max size." 'OK'
} catch {
    Write-Step "Event log resize failed: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 11. Windows Update — optionally suppress automatic restarts only
#     (updates themselves are NOT disabled — that would be a security risk)
# ---------------------------------------------------------------------------
Write-Step "--- Windows Update behavior ---" 'INFO'
if ($DisableWindowsUpdateAutomaticRestart) {
    try {
        Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1
        Write-Step "Automatic post-update reboots suppressed while users are logged on (patching schedule remains your responsibility)." 'OK'
    } catch {
        Write-Step "Windows Update policy write failed: $($_.Exception.Message)" 'WARN'
    }
} else {
    Write-Step "Skipped (pass -DisableWindowsUpdateAutomaticRestart to enable). Updates themselves are never disabled by this script." 'SKIP'
}

# ---------------------------------------------------------------------------
# 12. VMware Tools & Defender exclusions — reduce false-positive AV overhead
#     on VMware Tools' own processes/paths (only added if paths exist)
# ---------------------------------------------------------------------------
Write-Step "--- Defender exclusions for VMware Tools ---" 'INFO'
if ($hasVMwareTools) {
    try {
        $vmwareToolsPath = "$env:ProgramFiles\VMware\VMware Tools"
        if (Test-Path $vmwareToolsPath) {
            Add-MpPreference -ExclusionPath $vmwareToolsPath -ErrorAction SilentlyContinue
            Write-Step "Added Defender exclusion for: $vmwareToolsPath" 'OK'
        }
    } catch {
        Write-Step "Could not add Defender exclusion (Defender may be managed by policy/third-party AV): $($_.Exception.Message)" 'WARN'
    }
} else {
    Write-Step "VMware Tools not present — skipping exclusion." 'SKIP'
}

# ---------------------------------------------------------------------------
# 13. SMBv1 — disable legacy, insecure protocol (near-universally safe unless
#     you have ancient devices/NAS that require it)
# ---------------------------------------------------------------------------
Write-Step "--- SMBv1 ---" 'INFO'
try {
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
    Write-Step "SMBv1 protocol disabled." 'OK'
} catch {
    Write-Step "SMBv1 disable failed (may already be absent): $($_.Exception.Message)" 'SKIP'
}

# ===========================================================================
# AGGRESSIVE / OPT-IN SECTION — only runs with -IncludeAggressive
# Review carefully: these can affect DCs, print servers, or LAN-only setups.
# ===========================================================================
if ($IncludeAggressive) {
    Write-Step "=== Aggressive optimizations (-IncludeAggressive) ===" 'WARN'

    # Print Spooler — safe to disable unless this box is a print server
    Disable-ServiceSafely -Name 'Spooler'

    # Windows Search indexing — server workloads rarely need content indexing;
    # skip this on file servers where users rely on search.
    Disable-ServiceSafely -Name 'WSearch'

    # NetBIOS over TCP/IP — disable on all adapters (legacy name resolution,
    # not needed on networks with functioning DNS)
    try {
        $nics = Get-CimInstance -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"
        foreach ($nic in $nics) {
            $nic | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } | Out-Null
        }
        Write-Step "NetBIOS over TCP/IP disabled on all IP-enabled adapters." 'OK'
    } catch {
        Write-Step "NetBIOS disable failed: $($_.Exception.Message)" 'WARN'
    }

    # IPv6 — disable only if your network is confirmed IPv4-only end-to-end
    try {
        Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        Write-Step "IPv6 binding disabled on all adapters (verify nothing on your network depends on it, incl. NetBird/WireGuard-style tooling)." 'OK'
    } catch {
        Write-Step "IPv6 disable failed: $($_.Exception.Message)" 'WARN'
    }

    Write-Step "Aggressive section complete." 'WARN'
} else {
    Write-Step "Skipping aggressive section (run with -IncludeAggressive to enable Print Spooler/WSearch/NetBIOS/IPv6 changes)." 'SKIP'
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Step "=== Optimization pass complete ===" 'INFO'
Write-Step "Full log saved to: $logFile" 'INFO'
if ($script:RebootNeeded -and -not $SkipReboot) {
    Write-Step "A reboot is recommended to fully apply page file / feature changes." 'WARN'
}
Write-Step "Recommended next steps: reboot the VM, then verify VMware Tools status, network throughput, and application behavior before treating this as production-final." 'INFO'

Stop-Transcript | Out-Null
