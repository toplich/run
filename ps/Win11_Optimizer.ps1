<#
.SYNOPSIS
    Windows Laptop / Admin-VM Optimizer (for Windows PowerShell 5.1)
.DESCRIPTION
    Modular script for Windows optimization and privacy protection.
    Extended with an Optimize-AdminOnlyVM module for VMs used purely
    as an admin jump-box (browser + RDP/console access, nothing else).
#>

# ============================================
# CHECK AND ELEVATE TO ADMINISTRATOR
# ============================================

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-NOT $isAdmin) {
    Write-Host "This script requires Administrator privileges. Restarting..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = ".\Win11_optimise.ps1" }
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Write-Host "Running as Administrator - OK" -ForegroundColor Green

# ============================================
# MAIN FUNCTIONS
# ============================================

function Disable-Telemetry {
    Write-Host "`n=== DISABLING TELEMETRY & TRACKING ===" -ForegroundColor Magenta

    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" /v "value" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" /v "AutoConnectAllowedOEM" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Settings\FindMyDevice" /v "LocationSyncEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortanaAboveLock" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DODownloadMode" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v "DODownloadMode" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    Write-Host "[OK] Telemetry disabled" -ForegroundColor Green
}

function Disable-PrivacyServices {
    Write-Host "`n=== DISABLING TRACKING SERVICES ===" -ForegroundColor Magenta

    $services = @(
        "DiagTrack",
        "dmwappushservice",
        "WMPNetworkSvc",
        "RemoteRegistry",
        "lfsvc",
        "MapsBroker",
        "PcaSvc",
        "SysMain"
    )

    foreach ($svc in $services) {
        Stop-Service $svc -ErrorAction SilentlyContinue
        Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Disabled: $svc" -ForegroundColor DarkYellow
    }

    reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    Write-Host "[OK] Tracking services disabled" -ForegroundColor Green
}

function Disable-TrackingTasks {
    Write-Host "`n=== DISABLING SCHEDULED TRACKING TASKS ===" -ForegroundColor Magenta

    $taskNames = @(
        "Microsoft Compatibility Appraiser",
        "ProgramDataUpdater",
        "StartupAppTask",
        "Consolidator",
        "UsbCeip",
        "Microsoft-Windows-DiskDiagnosticDataCollector",
        "DmClient",
        "DmClientOnScenarioDownload",
        "Notifications",
        "MapsToastTask",
        "MapsUpdateTask",
        "BindingWorkItem",
        "Dummy",
        "Sqm-Tasks",
        "AnalyzeSystem",
        "QueueReporting"
    )

    foreach ($taskName in $taskNames) {
        Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  Disabled: $taskName" -ForegroundColor DarkYellow
    }

    Write-Host "[OK] Scheduled tracking tasks disabled" -ForegroundColor Green
}

function Remove-Bloatware {
    Write-Host "`n=== REMOVING BLOATWARE APPS ===" -ForegroundColor Magenta

    $bloatware = @(
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.Messaging",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal",
        "Microsoft.Office.OneNote",
        "Microsoft.OneConnect",
        "Microsoft.People",
        "Microsoft.Print3D",
        "Microsoft.SkypeApp",
        "Microsoft.Wallet",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsCamera",
        "Microsoft.WindowsCommunicationsApps",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxApp",
        "Microsoft.XboxGameCallableUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo"
    )

    foreach ($app in $bloatware) {
        Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
        Write-Host "  Removed: $app" -ForegroundColor DarkYellow
    }

    Write-Host "[OK] Bloatware apps removed" -ForegroundColor Green
}

function Optimize-Performance {
    Write-Host "`n=== PERFORMANCE OPTIMIZATION ===" -ForegroundColor Magenta

    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v "AllowGameDVR" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowSearchToUseLocation" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    powercfg /setactive SCHEME_BALANCED 2>&1 | Out-Null

    reg add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d "9012038010000000" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d "0" /f 2>&1 | Out-Null

    Write-Host "[OK] Performance optimization completed" -ForegroundColor Green
}

function Disable-OneDrive {
    Write-Host "`n=== REMOVING ONEDRIVE ===" -ForegroundColor Magenta

    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue

    $onedrive32 = "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
    $onedrive64 = "$env:SYSTEMROOT\System32\OneDriveSetup.exe"

    if (Test-Path $onedrive32) {
        Start-Process $onedrive32 -ArgumentList "/uninstall" -NoNewWindow -Wait
        Write-Host "  OneDrive removed (32-bit)" -ForegroundColor Green
    }
    if (Test-Path $onedrive64) {
        Start-Process $onedrive64 -ArgumentList "/uninstall" -NoNewWindow -Wait
        Write-Host "  OneDrive removed (64-bit)" -ForegroundColor Green
    }

    reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>&1 | Out-Null
    reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f 2>&1 | Out-Null
    reg delete "HKCU\SOFTWARE\Microsoft\OneDrive" /f 2>&1 | Out-Null
    reg delete "HKLM\SOFTWARE\Microsoft\OneDrive" /f 2>&1 | Out-Null

    Write-Host "[OK] OneDrive removed" -ForegroundColor Green
}

# ============================================
# NEW: ADMIN-ONLY VM MODULE
# For VMs used solely as an RDP/console jump-box (browser + terminal),
# no battery, no printers, no local users beyond the admin.
# Does NOT touch: TermService (RDP), Windows Defender, RpcSs, DcomLaunch,
# EventLog, Winmgmt (WMI), LanmanServer/Workstation (SMB access).
# ============================================

function Optimize-AdminOnlyVM {
    Write-Host "`n=== ADMIN-ONLY VM HARDENING & PERFORMANCE ===" -ForegroundColor Magenta

    # --- Services with no purpose on a headless/browser+console-only VM ---
    $vmServices = @(
        "Spooler",              # Print Spooler - no printers
        "Fax",                  # Fax service
        "WSearch",               # Windows Search indexer - not needed without file browsing workloads
        "TabletInputService",    # Tablet/touch input
        "WbioSrvc",              # Windows Biometric Service
        "PhoneSvc",              # Phone service
        "BthAvctpSvc",           # Bluetooth AVCTP
        "bthserv",               # Bluetooth Support Service
        "XblAuthManager",        # Xbox Live Auth
        "XblGameSave",           # Xbox Live Game Save
        "XboxNetApiSvc",         # Xbox Live Networking
        "Themes",                # Optional: keep off if you don't need custom desktop themes
        "RetailDemo"             # Retail Demo Service - irrelevant, occasionally present
    )

    foreach ($svc in $vmServices) {
        Stop-Service $svc -ErrorAction SilentlyContinue
        Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Disabled: $svc" -ForegroundColor DarkYellow
    }

    # --- Extra bloatware relevant to recent Win10/11 builds ---
    $extraBloatware = @(
        "Microsoft.Todos",
        "Microsoft.Clipchamp",
        "Microsoft.Copilot",
        "MicrosoftTeams",
        "Microsoft.549981C3F5F10",   # Cortana app package
        "Microsoft.WindowsFeedback",
        "Microsoft.GamingApp",
        "Clipchamp.Clipchamp"
    )
    foreach ($app in $extraBloatware) {
        Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
        Write-Host "  Removed: $app" -ForegroundColor DarkYellow
    }

    # --- Power plan: High performance (this is a VM, not a laptop - no battery to save) ---
    powercfg /setactive SCHEME_MIN 2>&1 | Out-Null   # SCHEME_MIN = High performance GUID alias
    Write-Host "  Power plan set to High performance" -ForegroundColor DarkYellow

    # --- Disable hibernation (frees disk space, irrelevant for a VM) ---
    powercfg /hibernate off 2>&1 | Out-Null
    Write-Host "  Hibernation disabled" -ForegroundColor DarkYellow

    # --- Visual effects: best performance (RDP renders client-side anyway) ---
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v "VisualFXSetting" /t REG_DWORD /d 2 /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop" /v "DragFullWindows" /t REG_SZ /d "0" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop" /v "FontSmoothing" /t REG_SZ /d "0" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d "0" /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarAnimations" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKCU\Software\Microsoft\Windows\DWM" /v "EnableAeroPeek" /t REG_DWORD /d 0 /f 2>&1 | Out-Null

    # --- Disable background apps globally ---
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v "GlobalUserDisabled" /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # --- Disable Widgets / News and Interests / Web search in Start ---
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v "AllowNewsAndInterests" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    # --- Windows Update: notify only, no forced auto-restart while an admin might be mid-session ---
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /t REG_DWORD /d 3 /f 2>&1 | Out-Null

    # --- RDP session tuning: disable wallpaper/theming server-side hints for lighter sessions ---
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "DisableWallPaper" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "DisableFullWindowDrag" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "DisableCursorBlinking" /t REG_DWORD /d 1 /f 2>&1 | Out-Null

    Write-Host "[OK] Admin-only VM hardening completed" -ForegroundColor Green
    Write-Host "  NOTE: Windows Defender was left untouched - this is an admin access point, keep it protected." -ForegroundColor Cyan
    Write-Host "  NOTE: RemoteRegistry was disabled by Disable-PrivacyServices; re-enable manually if remote reg tools are needed." -ForegroundColor Cyan
}

function Show-Status {
    Write-Host "`n=== CURRENT STATUS ===" -ForegroundColor Cyan

    $telemetry = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    if ($telemetry -eq 0) { Write-Host "Telemetry: DISABLED" -ForegroundColor Green } else { Write-Host "Telemetry: ENABLED (risk)" -ForegroundColor Red }

    $cortana = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
    if ($cortana -eq 0) { Write-Host "Cortana: DISABLED" -ForegroundColor Green } else { Write-Host "Cortana: ENABLED" -ForegroundColor Yellow }

    $doMode = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -ErrorAction SilentlyContinue).DODownloadMode
    if ($doMode -eq 0) { Write-Host "Delivery Optimization (P2P): DISABLED" -ForegroundColor Green } else { Write-Host "Delivery Optimization (P2P): ENABLED" -ForegroundColor Yellow }

    $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if (-not $oneDriveProcess) { Write-Host "OneDrive: REMOVED" -ForegroundColor Green } else { Write-Host "OneDrive: STILL RUNNING" -ForegroundColor Yellow }

    $powerScheme = (powercfg /getactivescheme)
    Write-Host "Power scheme: $powerScheme" -ForegroundColor Cyan

    $spooler = (Get-Service -Name Spooler -ErrorAction SilentlyContinue).StartType
    if ($spooler -eq "Disabled") { Write-Host "Print Spooler: DISABLED" -ForegroundColor Green } else { Write-Host "Print Spooler: $spooler" -ForegroundColor Yellow }
}

function Show-Menu {
    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║           WINDOWS LAPTOP / ADMIN-VM OPTIMIZER - MODULAR SCRIPT  ║
╚══════════════════════════════════════════════════════════════════╝

AVAILABLE FUNCTIONS:

  [1] Disable-Telemetry       - Disable telemetry (tracking)
  [2] Disable-PrivacyServices - Disable tracking services
  [3] Disable-TrackingTasks   - Disable scheduled tracking tasks
  [4] Remove-Bloatware        - Remove bloatware apps
  [5] Optimize-Performance    - Performance optimization (laptop-oriented)
  [6] Disable-OneDrive        - Remove OneDrive
  [7] Show-Status             - Show current status
  [8] ALL FUNCTIONS           - Full optimization (laptop profile)
  [9] Optimize-AdminOnlyVM    - Admin jump-box VM hardening ⭐
  [A] ALL + ADMIN-VM          - Full optimization + VM module
  [Q] Exit

"@
}

# ============================================
# COMMAND LINE PARAMETERS HANDLING
# ============================================

if ($args.Count -gt 0) {
    $Function = $args[1]
    switch ($Function.ToLower()) {
        "telemetry" { Disable-Telemetry }
        "privacy" { Disable-PrivacyServices }
        "tracking" { Disable-TrackingTasks }
        "bloatware" { Remove-Bloatware }
        "performance" { Optimize-Performance }
        "onedrive" { Disable-OneDrive }
        "status" { Show-Status }
        "adminvm" { Optimize-AdminOnlyVM }
        "all" {
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Remove-Bloatware
            Optimize-Performance
            Disable-OneDrive
        }
        "allvm" {
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Remove-Bloatware
            Optimize-Performance
            Disable-OneDrive
            Optimize-AdminOnlyVM
        }
        default { Write-Host "Unknown function. Options: telemetry, privacy, tracking, bloatware, performance, onedrive, status, adminvm, all, allvm" -ForegroundColor Red }
    }
    exit 0
}

# ============================================
# INTERACTIVE MODE
# ============================================

do {
    Show-Menu
    $choice = Read-Host "Select function"

    switch ($choice.ToLower()) {
        "1" { Disable-Telemetry }
        "2" { Disable-PrivacyServices }
        "3" { Disable-TrackingTasks }
        "4" { Remove-Bloatware }
        "5" { Optimize-Performance }
        "6" { Disable-OneDrive }
        "7" { Show-Status }
        "8" {
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Remove-Bloatware
            Optimize-Performance
            Disable-OneDrive
            Write-Host "`nFull optimization completed!" -ForegroundColor Green
        }
        "9" { Optimize-AdminOnlyVM }
        "a" {
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Remove-Bloatware
            Optimize-Performance
            Disable-OneDrive
            Optimize-AdminOnlyVM
            Write-Host "`nFull optimization + Admin-VM hardening completed!" -ForegroundColor Green
        }
        "q" { Write-Host "Exiting..." -ForegroundColor Yellow }
        default { Write-Host "Invalid choice" -ForegroundColor Red }
    }

    if (($choice.ToLower() -ne "q") -and ($choice.ToLower() -ne "8") -and ($choice.ToLower() -ne "a")) {
        Write-Host "`nPress Enter to continue..."
        Read-Host
    }

} while ($choice.ToLower() -ne "q")
