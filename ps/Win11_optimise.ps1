<#
.SYNOPSIS
    Windows Laptop Optimizer (for Windows PowerShell 5.1)
.DESCRIPTION
    Modular script for Windows optimization and privacy protection
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
    
    # Telemetry level: 0 - Security (minimum)
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable advertising ID
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable WiFi Sense and network data collection
    reg add "HKLM\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" /v "value" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" /v "AutoConnectAllowedOEM" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable handwriting data sharing
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    
    # Disable Tailored Experiences
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable Find My Device
    reg add "HKLM\SOFTWARE\Microsoft\Settings\FindMyDevice" /v "LocationSyncEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable Cortana completely
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortanaAboveLock" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable P2P updates (Delivery Optimization)
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DODownloadMode" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v "DODownloadMode" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    Write-Host "[OK] Telemetry disabled" -ForegroundColor Green
}

function Disable-PrivacyServices {
    Write-Host "`n=== DISABLING TRACKING SERVICES ===" -ForegroundColor Magenta
    
    $services = @(
        "DiagTrack",           # Connected User Experiences and Telemetry
        "dmwappushservice",    # Device Management WAP Push
        "WMPNetworkSvc",       # Windows Media Player Network Sharing
        "RemoteRegistry",      # Remote Registry access
        "lfsvc",               # Geolocation Service
        "MapsBroker",          # Downloaded Maps Manager
        "PcaSvc",              # Program Compatibility Assistant
        "SysMain"              # Superfetch (saves resources)
    )
    
    foreach ($svc in $services) {
        Stop-Service $svc -ErrorAction SilentlyContinue
        Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Disabled: $svc" -ForegroundColor DarkYellow
    }
    
    # Disable Windows Error Reporting
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
    
    # Disable GameDVR
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v "AllowGameDVR" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Disable web search in Start Menu
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowSearchToUseLocation" /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    
    # Power plan: Balanced (for laptops)
    powercfg /setactive SCHEME_BALANCED 2>&1 | Out-Null
    
    # Disable animations (speeds up weak laptops)
    reg add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d "9012038010000000" /f 2>&1 | Out-Null
    reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d "0" /f 2>&1 | Out-Null
    
    Write-Host "[OK] Performance optimization completed" -ForegroundColor Green
}

function Disable-OneDrive {
    Write-Host "`n=== REMOVING ONEDRIVE ===" -ForegroundColor Magenta
    
    # Stop the process
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    
    # Remove OneDrive
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
    
    # Remove registry leftovers (FIXED SYNTAX)
    # Remove the Run entry if it exists
    reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>&1 | Out-Null
    
    # Remove the desktop namespace key if it exists
    reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f 2>&1 | Out-Null
    
    # Also remove common OneDrive registry keys
    reg delete "HKCU\SOFTWARE\Microsoft\OneDrive" /f 2>&1 | Out-Null
    reg delete "HKLM\SOFTWARE\Microsoft\OneDrive" /f 2>&1 | Out-Null
    
    Write-Host "[OK] OneDrive removed" -ForegroundColor Green
}

function Show-Status {
    Write-Host "`n=== CURRENT STATUS ===" -ForegroundColor Cyan
    
    $telemetry = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    if ($telemetry -eq 0) {
        Write-Host "Telemetry: DISABLED" -ForegroundColor Green
    } else {
        Write-Host "Telemetry: ENABLED (risk)" -ForegroundColor Red
    }
    
    $cortana = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
    if ($cortana -eq 0) {
        Write-Host "Cortana: DISABLED" -ForegroundColor Green
    } else {
        Write-Host "Cortana: ENABLED" -ForegroundColor Yellow
    }
    
    $doMode = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -ErrorAction SilentlyContinue).DODownloadMode
    if ($doMode -eq 0) {
        Write-Host "Delivery Optimization (P2P): DISABLED" -ForegroundColor Green
    } else {
        Write-Host "Delivery Optimization (P2P): ENABLED" -ForegroundColor Yellow
    }
    
    # Check OneDrive status
    $oneDriveProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    if (-not $oneDriveProcess) {
        Write-Host "OneDrive: REMOVED" -ForegroundColor Green
    } else {
        Write-Host "OneDrive: STILL RUNNING" -ForegroundColor Yellow
    }
}

function Show-Menu {
    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║           WINDOWS LAPTOP OPTIMIZER - MODULAR SCRIPT             ║
╚══════════════════════════════════════════════════════════════════╝

AVAILABLE FUNCTIONS:

  [1] Disable-Telemetry       - Disable telemetry (tracking) ⭐
  [2] Disable-PrivacyServices - Disable tracking services
  [3] Disable-TrackingTasks   - Disable scheduled tracking tasks
  [4] Remove-Bloatware        - Remove bloatware apps
  [5] Optimize-Performance    - Performance optimization
  [6] Disable-OneDrive        - Remove OneDrive
  [7] Show-Status             - Show current status
  [8] ALL FUNCTIONS           - Full optimization
  [Q] Exit

"@
}

# ============================================
# COMMAND LINE PARAMETERS HANDLING
# ============================================

# Check if called with -Function parameter
if ($args.Count -gt 0) {
    $Function = $args[1]  # Get value after -Function
    switch ($Function.ToLower()) {
        "telemetry" { Disable-Telemetry }
        "privacy" { Disable-PrivacyServices }
        "tracking" { Disable-TrackingTasks }
        "bloatware" { Remove-Bloatware }
        "performance" { Optimize-Performance }
        "onedrive" { Disable-OneDrive }
        "status" { Show-Status }
        "all" {
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Remove-Bloatware
            Optimize-Performance
            Disable-OneDrive
        }
        default { Write-Host "Unknown function. Options: telemetry, privacy, tracking, bloatware, performance, onedrive, status, all" -ForegroundColor Red }
    }
    exit 0
}

# ============================================
# INTERACTIVE MODE
# ============================================

do {
    Show-Menu
    $choice = Read-Host "Select function"
    
    switch ($choice) {
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
        "q" { Write-Host "Exiting..." -ForegroundColor Yellow }
        default { Write-Host "Invalid choice" -ForegroundColor Red }
    }
    
    if (($choice -ne "q") -and ($choice -ne "8")) {
        Write-Host "`nPress Enter to continue..."
        Read-Host
    }
    
} while ($choice -ne "q")
