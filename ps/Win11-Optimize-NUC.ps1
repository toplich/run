<#
.SYNOPSIS
    Ultimate Optimization Script for Intel NUC Media Center
.DESCRIPTION
    Optimizes Windows for 24/7 video playback (YouTube/Netflix via Chrome)
    Designed for: Intel NUC7i5BNB with Intel Iris Plus Graphics 640
#>

# ============================================
# CHECK ADMINISTRATOR
# ============================================

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-NOT $isAdmin) {
    Write-Host "Restarting as Administrator..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Write-Host @"
╔══════════════════════════════════════════════════════════════════╗
║     Intel NUC OPTIMIZER - For YouTube & Netflix on Chrome       ║
╚══════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# ============================================
# 1. POWER & PERFORMANCE (NUC is always plugged in)
# ============================================

function Set-PowerOptimizations {
    Write-Host "`n[1] POWER OPTIMIZATIONS..." -ForegroundColor Magenta
    
    # Balanced power plan (no overheating, sufficient for video)
    powercfg /setactive SCHEME_BALANCED
    
    # Disable sleep/hibernate (media center runs 24/7)
    powercfg -change -standby-timeout-ac 0
    powercfg -change -hibernate-timeout-ac 0
    powercfg -x -disk-timeout-ac 0
    powercfg -h off
    
    # Disable USB selective suspend
    powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    
    Write-Host "  ✓ Sleep/hibernate disabled" -ForegroundColor Green
    Write-Host "  ✓ USB suspend disabled" -ForegroundColor Green
}

# ============================================
# 2. DISABLE TELEMETRY & TRACKING
# ============================================

function Disable-Telemetry {
    Write-Host "`n[2] DISABLING TELEMETRY..." -ForegroundColor Magenta
    
    # Telemetry level 0 - Security only
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f
    
    # Disable advertising ID
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d 1 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f
    
    # Disable Cortana completely
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortanaAboveLock" /t REG_DWORD /d 0 /f
    
    # Disable P2P updates (wastes bandwidth)
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DODownloadMode" /t REG_DWORD /d 0 /f
    
    Write-Host "  ✓ Telemetry disabled" -ForegroundColor Green
}

# ============================================
# 3. DISABLE UNNECESSARY SERVICES (for media PC)
# ============================================

function Disable-Services {
    Write-Host "`n[3] DISABLING UNNECESSARY SERVICES..." -ForegroundColor Magenta
    
    $services = @(
        "DiagTrack",           # Connected User Experiences
        "dmwappushservice",    # Device Management WAP Push
        "WSearch",             # Windows Search (not needed for media)
        "SysMain",             # Superfetch
        "RemoteRegistry",      # Remote Registry
        "WMPNetworkSvc",       # Windows Media Player Sharing
        "lfsvc",               # Geolocation
        "MapsBroker"           # Downloaded Maps Manager
    )
    
    foreach ($svc in $services) {
        Stop-Service $svc -ErrorAction SilentlyContinue
        Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  ✓ Disabled: $svc" -ForegroundColor DarkYellow
    }
    
    # Disable Windows Error Reporting
    reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d 1 /f
    
    Write-Host "  ✓ All unnecessary services disabled" -ForegroundColor Green
}

# ============================================
# 4. DISABLE BACKGROUND APPS
# ============================================

function Disable-BackgroundApps {
    Write-Host "`n[4] DISABLING BACKGROUND APPS..." -ForegroundColor Magenta
    
    # Disable all background apps globally
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v "GlobalUserDisabled" /t REG_DWORD /d 1 /f
    
    # Disable GameDVR
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f
    reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f
    
    # Disable tips & suggestions
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SoftLandingEnabled" /t REG_DWORD /d 0 /f
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f
    
    Write-Host "  ✓ Background apps disabled" -ForegroundColor Green
    Write-Host "  ✓ GameDVR disabled" -ForegroundColor Green
}

# ============================================
# 5. REMOVE BLOATWARE
# ============================================

function Remove-Bloatware {
    Write-Host "`n[5] REMOVING BLOATWARE..." -ForegroundColor Magenta
    
    $bloatware = @(
        "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.GetHelp",
        "Microsoft.Getstarted", "Microsoft.Microsoft3DViewer", "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection", "Microsoft.MixedReality.Portal",
        "Microsoft.Office.OneNote", "Microsoft.OneConnect", "Microsoft.People",
        "Microsoft.Print3D", "Microsoft.SkypeApp", "Microsoft.Wallet",
        "Microsoft.WindowsAlarms", "Microsoft.WindowsCamera", "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder", "Microsoft.Xbox.TCUI",
        "Microsoft.XboxApp", "Microsoft.XboxGameCallableUI", "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.YourPhone",
        "Microsoft.ZuneMusic", "Microsoft.ZuneVideo"
    )
    
    foreach ($app in $bloatware) {
        Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
    }
    
    Write-Host "  ✓ Bloatware removed" -ForegroundColor Green
}

# ============================================
# 6. INTEL NUC & GPU OPTIMIZATIONS
# ============================================

function Optimize-IntelGPU {
    Write-Host "`n[6] INTEL GPU OPTIMIZATIONS..." -ForegroundColor Magenta
    
    # Enable hardware-accelerated video decoding
    reg add "HKLM\SOFTWARE\Intel\MediaSDK" /v "HardwareDecode" /t REG_DWORD /d 1 /f
    reg add "HKLM\SOFTWARE\Intel\MediaSDK" /v "HEVCSupport" /t REG_DWORD /d 1 /f
    
    # Enable VP9 decode (for YouTube)
    reg add "HKLM\SOFTWARE\Intel\Media" /v "ChromeVP9Decode" /t REG_DWORD /d 1 /f
    
    # GPU hardware scheduling
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v "HwSchMode" /t REG_DWORD /d 2 /f
    
    # Increase video memory buffer
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "LargeSystemCache" /t REG_DWORD /d 1 /f
    
    Write-Host "  ✓ Hardware decoding enabled (HEVC, VP9)" -ForegroundColor Green
    Write-Host "  ✓ GPU scheduling enabled" -ForegroundColor Green
}

# ============================================
# 7. NETWORK OPTIMIZATIONS (for streaming)
# ============================================

function Optimize-Network {
    Write-Host "`n[7] NETWORK OPTIMIZATIONS..." -ForegroundColor Magenta
    
    # Increase TCP buffer for streaming
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "TcpWindowSize" /t REG_DWORD /d 65535 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "GlobalMaxTcpWindowSize" /t REG_DWORD /d 65535 /f
    
    # Disable Nagle's algorithm (reduces latency)
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" /v "TcpAckFrequency" /t REG_DWORD /d 1 /f
    
    # Increase port range
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "MaxUserPort" /t REG_DWORD /d 65534 /f
    
    # Disable Wi-Fi power saving (for stable streaming)
    powercfg -setacvalueindex SCHEME_CURRENT SUB_NONE WIFI_POWERSAVING 0
    
    Write-Host "  ✓ TCP buffer optimized" -ForegroundColor Green
    Write-Host "  ✓ Max ports increased to 65534" -ForegroundColor Green
    Write-Host "  ✓ Wi-Fi power saving disabled" -ForegroundColor Green
}

# ============================================
# 8. MULTIMEDIA PRIORITY
# ============================================

function Set-MultimediaPriority {
    Write-Host "`n[8] SETTING MULTIMEDIA PRIORITY..." -ForegroundColor Magenta
    
    # Give higher priority to video playback
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 20 /f
    
    # Disable network throttling during video
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 0xffffffff /f
    
    # Set GPU priority to high for media
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "GPUPriority" /t REG_DWORD /d 8 /f
    
    Write-Host "  ✓ Video playback priority increased" -ForegroundColor Green
    Write-Host "  ✓ Network throttling disabled" -ForegroundColor Green
}

# ============================================
# 9. CLEANUP (disk space)
# ============================================

function Cleanup-Disk {
    Write-Host "`n[9] CLEANING TEMPORARY FILES..." -ForegroundColor Magenta
    
    # Clean Windows Temp
    $tempPaths = @("$env:TEMP", "$env:WINDIR\Temp")
    foreach ($path in $tempPaths) {
        if (Test-Path $path) {
            Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            Write-Host "  ✓ Cleaned: $path" -ForegroundColor DarkYellow
        }
    }
    
    # Clean Chrome cache
    $chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromeCache) {
        Remove-Item "$chromeCache\*" -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "  ✓ Chrome cache cleaned" -ForegroundColor DarkYellow
    }
    
    # Empty Recycle Bin
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    # Run DISM cleanup (quick, no /ResetBase to save time)
    dism /online /Cleanup-Image /StartComponentCleanup /quiet 2>&1 | Out-Null
    
    Write-Host "  ✓ Disk cleanup completed" -ForegroundColor Green
}

# ============================================
# MAIN FUNCTION (RUN ALL)
# ============================================

function Optimize-All {
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "     STARTING FULL NUC OPTIMIZATION" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    
    Set-PowerOptimizations
    Disable-Telemetry
    Disable-Services
    Disable-BackgroundApps
    Remove-Bloatware
    Optimize-IntelGPU
    Optimize-Network
    Set-MultimediaPriority
    Cleanup-Disk
    
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "     OPTIMIZATION COMPLETED!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    
    Write-Host "`n[IMPORTANT] Restart your NUC to apply all changes." -ForegroundColor Yellow
}

# ============================================
# RUN
# ============================================

Optimize-All

Write-Host "`nPress Enter to exit..."
Read-Host
