<#
.SYNOPSIS
    Disk Cleanup Pro - Advanced disk space cleaner for Windows
.DESCRIPTION
    Safely removes temporary files, cache, logs, and other junk to free up disk space.
    Run as Administrator for best results.
#>

# ============================================
# CHECK ADMINISTRATOR RIGHTS
# ============================================

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-NOT $isAdmin) {
    Write-Host "This script requires Administrator privileges. Restarting..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = ".\DiskCleanup.ps1" }
    Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}

Write-Host "Running as Administrator - OK" -ForegroundColor Green

# ============================================
# FUNCTIONS
# ============================================

function Get-DiskUsage {
    Write-Host "`n=== CURRENT DISK USAGE ===" -ForegroundColor Cyan
    
    $drives = Get-PSDrive -PSProvider FileSystem
    foreach ($drive in $drives) {
        $free = [math]::Round($drive.Free / 1GB, 2)
        $used = [math]::Round(($drive.Used / 1GB), 2)
        $total = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)
        $percentFree = [math]::Round(($drive.Free / ($drive.Free + $drive.Used)) * 100, 2)
        
        if ($percentFree -lt 10) {
            Write-Host "  $($drive.Name): $free GB free / $total GB total (${percentFree}% free) [CRITICAL]" -ForegroundColor Red
        } elseif ($percentFree -lt 20) {
            Write-Host "  $($drive.Name): $free GB free / $total GB total (${percentFree}% free) [LOW]" -ForegroundColor Yellow
        } else {
            Write-Host "  $($drive.Name): $free GB free / $total GB total (${percentFree}% free)" -ForegroundColor Green
        }
    }
}

function Clean-TemporaryFiles {
    Write-Host "`n=== CLEANING TEMPORARY FILES ===" -ForegroundColor Magenta
    
    # Windows Temp folders
    $tempPaths = @(
        "$env:TEMP",
        "$env:WINDIR\Temp",
        "C:\Windows\Temp",
        "$env:LOCALAPPDATA\Temp"
    )
    
    $totalFreed = 0
    
    foreach ($path in $tempPaths) {
        if (Test-Path $path) {
            $sizeBefore = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            try {
                Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                $sizeAfter = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $freed = [math]::Round(($sizeBefore - $sizeAfter) / 1MB, 2)
                $totalFreed += $freed
                Write-Host "  Cleaned: $path ($freed MB)" -ForegroundColor DarkYellow
            } catch {
                Write-Host "  Warning: Could not clean all files in $path" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "[OK] Temporary files cleaned (freed approximately $totalFreed MB)" -ForegroundColor Green
}

function Clean-Prefetch {
    Write-Host "`n=== CLEANING PREFETCH FILES ===" -ForegroundColor Magenta
    
    $prefetchPath = "$env:WINDIR\Prefetch"
    if (Test-Path $prefetchPath) {
        $sizeBefore = (Get-ChildItem $prefetchPath -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Get-ChildItem $prefetchPath -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $sizeAfter = (Get-ChildItem $prefetchPath -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $freed = [math]::Round(($sizeBefore - $sizeAfter) / 1MB, 2)
        Write-Host "  Cleaned: Prefetch ($freed MB)" -ForegroundColor DarkYellow
        Write-Host "[OK] Prefetch files cleaned" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Prefetch folder not found" -ForegroundColor Yellow
    }
}

function Clean-RecycleBin {
    Write-Host "`n=== CLEANING RECYCLE BIN ===" -ForegroundColor Magenta
    
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Recycle Bin emptied" -ForegroundColor Green
}

function Clean-DownloadsFolder {
    Write-Host "`n=== CLEANING DOWNLOADS FOLDER ===" -ForegroundColor Magenta
    
    $downloadsPath = "$env:USERPROFILE\Downloads"
    $daysOld = 30
    
    if (Test-Path $downloadsPath) {
        $cutoffDate = (Get-Date).AddDays(-$daysOld)
        $oldFiles = Get-ChildItem $downloadsPath -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        if ($oldFiles) {
            $sizeBefore = ($oldFiles | Measure-Object -Property Length -Sum).Sum
            $oldFiles | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $freed = [math]::Round($sizeBefore / 1GB, 2)
            Write-Host "  Removed files older than $daysOld days ($freed GB)" -ForegroundColor DarkYellow
            Write-Host "[OK] Downloads folder cleaned (old files only)" -ForegroundColor Green
        } else {
            Write-Host "  No files older than $daysOld days found" -ForegroundColor DarkYellow
            Write-Host "[OK] Nothing to clean in Downloads" -ForegroundColor Green
        }
    } else {
        Write-Host "[SKIP] Downloads folder not found" -ForegroundColor Yellow
    }
}

function Clean-BrowserCache {
    Write-Host "`n=== CLEANING BROWSER CACHE ===" -ForegroundColor Magenta
    
    $browsers = @{
        "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
        "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        "Firefox" = "$env:APPDATA\Mozilla\Firefox\Profiles"
    }
    
    $totalFreed = 0
    
    foreach ($browser in $browsers.Keys) {
        $path = $browsers[$browser]
        if (Test-Path $path) {
            if ($browser -eq "Firefox") {
                # Firefox has random profile folder names
                $profiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\cache" -ErrorAction SilentlyContinue
                foreach ($profile in $profiles) {
                    $sizeBefore = (Get-ChildItem $profile -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    Remove-Item "$profile\*" -Force -Recurse -ErrorAction SilentlyContinue
                    $freed = [math]::Round($sizeBefore / 1MB, 2)
                    $totalFreed += $freed
                    Write-Host "  Cleaned: Firefox cache ($freed MB)" -ForegroundColor DarkYellow
                }
            } else {
                $sizeBefore = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Remove-Item "$path\*" -Force -Recurse -ErrorAction SilentlyContinue
                $freed = [math]::Round($sizeBefore / 1MB, 2)
                $totalFreed += $freed
                Write-Host "  Cleaned: $browser cache ($freed MB)" -ForegroundColor DarkYellow
            }
        }
    }
    
    Write-Host "[OK] Browser cache cleaned (freed approximately $totalFreed MB)" -ForegroundColor Green
}

function Clean-DeliveryOptimization {
    Write-Host "`n=== CLEANING DELIVERY OPTIMIZATION FILES ===" -ForegroundColor Magenta
    
    $doPath = "$env:WINDIR\SoftwareDistribution\Download"
    if (Test-Path $doPath) {
        $sizeBefore = (Get-ChildItem $doPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Get-ChildItem $doPath -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        $sizeAfter = (Get-ChildItem $doPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $freed = [math]::Round(($sizeBefore - $sizeAfter) / 1MB, 2)
        Write-Host "  Cleaned: Delivery Optimization cache ($freed MB)" -ForegroundColor DarkYellow
        Write-Host "[OK] Delivery Optimization files cleaned" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Delivery Optimization folder not found" -ForegroundColor Yellow
    }
}

function Clean-WindowsLogs {
    Write-Host "`n=== CLEANING WINDOWS LOGS ===" -ForegroundColor Magenta
    
    # Clean Event Logs
    wevtutil el | ForEach-Object {
        try {
            wevtutil cl $_ -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Host "  Cleaned: Windows Event Logs" -ForegroundColor DarkYellow
    
    # Clean CBS logs
    $cbsLogs = "$env:WINDIR\Logs\CBS"
    if (Test-Path $cbsLogs) {
        Get-ChildItem $cbsLogs -Filter "*.log" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "  Cleaned: CBS logs" -ForegroundColor DarkYellow
    }
    
    Write-Host "[OK] Windows logs cleaned" -ForegroundColor Green
}

function Clean-DISM {
    Write-Host "`n=== RUNNING DISM CLEANUP ===" -ForegroundColor Magenta
    
    Write-Host "  This may take a few minutes..." -ForegroundColor DarkYellow
    
    # Remove old Windows updates and components
    dism /online /Cleanup-Image /StartComponentCleanup /ResetBase /quiet 2>&1 | Out-Null
    
    # Analyze and clean WinSxS
    dism /online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-Null
    
    Write-Host "[OK] DISM cleanup completed" -ForegroundColor Green
}

function Clean-DuplicateFiles {
    Write-Host "`n=== FINDING DUPLICATE FILES (Preview Mode) ===" -ForegroundColor Magenta
    
    Write-Host "  Scanning for duplicates in Downloads and Desktop..." -ForegroundColor DarkYellow
    
    $paths = @(
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop"
    )
    
    $duplicates = @{}
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            $files = Get-ChildItem $path -File -Recurse -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $key = "$($file.Name)_$($file.Length)"
                if ($duplicates.ContainsKey($key)) {
                    $duplicates[$key] += , $file.FullName
                } else {
                    $duplicates[$key] = @($file.FullName)
                }
            }
        }
    }
    
    $duplicateCount = 0
    $duplicateSize = 0
    
    foreach ($key in $duplicates.Keys) {
        if ($duplicates[$key].Count -gt 1) {
            $duplicateCount++
            $fileInfo = Get-Item $duplicates[$key][0] -ErrorAction SilentlyContinue
            if ($fileInfo) {
                $duplicateSize += $fileInfo.Length * ($duplicates[$key].Count - 1)
            }
        }
    }
    
    $duplicateSizeGB = [math]::Round($duplicateSize / 1GB, 2)
    Write-Host "  Found approximately $duplicateCount duplicate file groups" -ForegroundColor DarkYellow
    Write-Host "  Potential space waste: $duplicateSizeGB GB" -ForegroundColor DarkYellow
    Write-Host "  (Automatic removal not enabled - use manual cleanup tool)" -ForegroundColor Yellow
}

function Run-FullCleanup {
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "     STARTING FULL DISK CLEANUP" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    
    Get-DiskUsage
    Clean-TemporaryFiles
    Clean-Prefetch
    Clean-RecycleBin
    Clean-DownloadsFolder
    Clean-BrowserCache
    Clean-DeliveryOptimization
    Clean-WindowsLogs
    Clean-DISM
    Clean-DuplicateFiles
    
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "     DISK CLEANUP COMPLETED" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Get-DiskUsage
    
    Write-Host "`n[INFO] It is recommended to restart your computer for best results." -ForegroundColor Yellow
}

function Show-Menu {
    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║                 DISK CLEANUP PRO - FREE UP SPACE                 ║
╚══════════════════════════════════════════════════════════════════╝

AVAILABLE FUNCTIONS:

  [1] Show current disk usage
  [2] Clean temporary files (Windows Temp)
  [3] Clean Prefetch files
  [4] Empty Recycle Bin
  [5] Clean Downloads folder (files older than 30 days)
  [6] Clean browser cache (Chrome, Edge, Firefox)
  [7] Clean Delivery Optimization cache
  [8] Clean Windows logs
  [9] Run DISM cleanup (removes old Windows components)
  [10] Find duplicate files (preview only)
  [11] FULL DISK CLEANUP (all of the above)
  [Q] Exit

"@
}

# ============================================
# COMMAND LINE PARAMETERS
# ============================================

param(
    [Parameter(Position=0)]
    [string]$Function = ""
)

if ($Function) {
    switch ($Function.ToLower()) {
        "status" { Get-DiskUsage }
        "temp" { Clean-TemporaryFiles }
        "prefetch" { Clean-Prefetch }
        "recycle" { Clean-RecycleBin }
        "downloads" { Clean-DownloadsFolder }
        "browser" { Clean-BrowserCache }
        "windowslogs" { Clean-WindowsLogs }
        "dism" { Clean-DISM }
        "full" { Run-FullCleanup }
        default { Write-Host "Unknown function. Options: status, temp, prefetch, recycle, downloads, browser, windowslogs, dism, full" -ForegroundColor Red }
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
        "1" { Get-DiskUsage }
        "2" { Clean-TemporaryFiles }
        "3" { Clean-Prefetch }
        "4" { Clean-RecycleBin }
        "5" { Clean-DownloadsFolder }
        "6" { Clean-BrowserCache }
        "7" { Clean-DeliveryOptimization }
        "8" { Clean-WindowsLogs }
        "9" { Clean-DISM }
        "10" { Clean-DuplicateFiles }
        "11" { Run-FullCleanup }
        "q" { Write-Host "Exiting..." -ForegroundColor Yellow }
        default { Write-Host "Invalid choice" -ForegroundColor Red }
    }
    
    if (($choice -ne "q") -and ($choice -ne "11")) {
        Write-Host "`nPress Enter to continue..."
        Read-Host
    }
    
} while ($choice -ne "q")
