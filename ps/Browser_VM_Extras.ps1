#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Browser VM Performance Extras - companion to Win11-Browser_optomise.ps1
.DESCRIPTION
    Applies VM-specific Chrome/Edge group policies not covered by the
    "Just the Browser" AI/telemetry configuration: background process
    prevention, memory saver, hardware acceleration, notifications,
    and default startup behavior. Safe to run alongside/after the
    Just the Browser script - keys are in the same HKLM policy hives
    and do not conflict.
    All keys are applied via direct 'reg add' from this repo - no
    external downloads, no third-party dependency for this module.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-NOT $isAdmin) {
    Write-Host "This script requires Administrator privileges. Restarting..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = ".\Browser_VM_Extras.ps1" }
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Write-Host "Running as Administrator - OK" -ForegroundColor Green

function Optimize-ChromeVM {
    Write-Host "`n=== GOOGLE CHROME - VM PERFORMANCE POLICIES ===" -ForegroundColor Magenta

    $key = "HKLM\SOFTWARE\Policies\Google\Chrome"

    # Prevent Chrome from running background processes after all windows are closed
    reg add $key /v "BackgroundModeEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Memory Saver: automatically discard inactive tabs to free RAM (2 = enabled + aggressive)
    reg add $key /v "HighEfficiencyModeEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add $key /v "TabDiscardingExceptions" /t REG_SZ /d "" /f 2>&1 | Out-Null

    # Hardware acceleration off - avoids issues on VMs without real 3D GPU passthrough
    reg add $key /v "HardwareAccelerationModeEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Disable notifications by default (no need on an admin jump-box)
    reg add $key /v "DefaultNotificationsSetting" /t REG_DWORD /d 2 /f 2>&1 | Out-Null

    # Clean startup: always open to New Tab page, no restore of previous session junk
    reg add $key /v "RestoreOnStartup" /t REG_DWORD /d 5 /f 2>&1 | Out-Null

    # Disable password manager if you rely on an external vault
    reg add $key /v "PasswordManagerEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Metrics/crash reporting off (belt-and-suspenders alongside Just the Browser telemetry keys)
    reg add $key /v "MetricsReportingEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Block silent extension auto-install from the web store
    reg add $key /v "ExtensionInstallBlocklist\1" /t REG_SZ /d "*" /f 2>&1 | Out-Null

    Write-Host "[OK] Chrome VM performance policies applied" -ForegroundColor Green
}

function Optimize-EdgeVM {
    Write-Host "`n=== MICROSOFT EDGE - VM PERFORMANCE POLICIES ===" -ForegroundColor Magenta

    $key = "HKLM\SOFTWARE\Policies\Microsoft\Edge"

    # Prevent Edge from running background processes after all windows are closed
    reg add $key /v "BackgroundModeEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add $key /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Sleeping Tabs: discard inactive tabs to free RAM
    reg add $key /v "SleepingTabsEnabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # Hardware acceleration off - same reasoning as Chrome
    reg add $key /v "HardwareAccelerationModeEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Disable notifications by default
    reg add $key /v "DefaultNotificationsSetting" /t REG_DWORD /d 2 /f 2>&1 | Out-Null

    # Clean startup
    reg add $key /v "RestoreOnStartup" /t REG_DWORD /d 5 /f 2>&1 | Out-Null

    # Disable password manager if you rely on an external vault
    reg add $key /v "PasswordManagerEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Metrics reporting off
    reg add $key /v "MetricsReportingEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # Block silent extension auto-install
    reg add $key /v "ExtensionInstallBlocklist\1" /t REG_SZ /d "*" /f 2>&1 | Out-Null

    Write-Host "[OK] Edge VM performance policies applied" -ForegroundColor Green
}

function Show-Status {
    Write-Host "`n=== CURRENT STATUS ===" -ForegroundColor Cyan
    foreach ($b in @(
        @{Name="Chrome"; Key="HKLM:\SOFTWARE\Policies\Google\Chrome"},
        @{Name="Edge";   Key="HKLM:\SOFTWARE\Policies\Microsoft\Edge"}
    )) {
        $bg = (Get-ItemProperty -Path $b.Key -Name "BackgroundModeEnabled" -ErrorAction SilentlyContinue).BackgroundModeEnabled
        $hw = (Get-ItemProperty -Path $b.Key -Name "HardwareAccelerationModeEnabled" -ErrorAction SilentlyContinue).HardwareAccelerationModeEnabled
        Write-Host "$($b.Name): BackgroundMode=$bg HardwareAcceleration=$hw"
    }
}

# ============================================
# ENTRY POINT
# ============================================

if ($args.Count -gt 0) {
    switch ($args[0].ToLower()) {
        "chrome" { Optimize-ChromeVM }
        "edge" { Optimize-EdgeVM }
        "status" { Show-Status }
        "all" { Optimize-ChromeVM; Optimize-EdgeVM }
        default { Write-Host "Options: chrome, edge, status, all" -ForegroundColor Red }
    }
    exit 0
}

Optimize-ChromeVM
Optimize-EdgeVM
Write-Host "`nDone. Restart Chrome/Edge for changes to take effect." -ForegroundColor Green
Show-Status
