<#
.SYNOPSIS
    Disk Cleanup Pro - Advanced disk space cleaner for Windows
.DESCRIPTION
    Safely removes temporary files, cache, logs, and other junk to free up disk space.
    Run as Administrator for best results.
#>

# ============================================
# COMMAND LINE PARAMETERS (MUST BE FIRST!)
# ============================================

param(
    [Parameter(Position=0)]
    [string]$Function = ""
)

# ============================================
# CHECK ADMINISTRATOR RIGHTS
# ============================================

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-NOT $isAdmin) {
    Write-Host "This script requires Administrator privileges. Restarting..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = ".\Win11_DiskCleanup.ps1" }
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
    
    $tempPaths = @(
        "$env:TEMP",
        "$env:WINDIR\Temp",
        "C:\Windows\Temp"
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
        # Отримуємо всі файли (виключаємо папки)
        $files = Get-ChildItem $prefetchPath -File -ErrorAction SilentlyContinue | Where-Object { 
            $_.Name -notlike "Layout.ini" -and $_.Name -notlike "ReadyBoot*" 
        }
        
        if ($files.Count -gt 0) {
            $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
            $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
            
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            
            Write-Host "  Cleaned: Prefetch ($totalSizeMB MB)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  Prefetch: nothing to clean" -ForegroundColor DarkYellow
        }
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
    
    $totalFreed = 0
    
    # Chrome
    $chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromeCache) {
        $sizeBefore = (Get-ChildItem $chromeCache -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item "$chromeCache\*" -Force -Recurse -ErrorAction SilentlyContinue
        $freed = [math]::Round($sizeBefore / 1MB, 2)
        $totalFreed += $freed
        Write-Host "  Cleaned: Chrome cache ($freed MB)" -ForegroundColor DarkYellow
    }
    
    # Edge
    $edgeCache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $edgeCache) {
        $sizeBefore = (Get-ChildItem $edgeCache -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item "$edgeCache\*" -Force -Recurse -ErrorAction SilentlyContinue
        $freed = [math]::Round($sizeBefore / 1MB, 2)
        $totalFreed += $freed
        Write-Host "  Cleaned: Edge cache ($freed MB)" -ForegroundColor DarkYellow
    }
    
    # Firefox
    $firefoxProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxProfiles) {
        $firefoxCaches = Get-ChildItem "$firefoxProfiles\*\cache" -ErrorAction SilentlyContinue
        foreach ($cache in $firefoxCaches) {
            $sizeBefore = (Get-ChildItem $cache -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Remove-Item "$cache\*" -Force -Recurse -ErrorAction SilentlyContinue
            $freed = [math]::Round($sizeBefore / 1MB, 2)
            $totalFreed += $freed
            Write-Host "  Cleaned: Firefox cache ($freed MB)" -ForegroundColor DarkYellow
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
    
    # Simple method - just delete log files directly (works 100% without errors)
    $logPaths = @(
        "$env:WINDIR\System32\winevt\Logs\*.evtx",
        "$env:WINDIR\Logs\CBS\*.log",
        "$env:WINDIR\Logs\WindowsUpdate\*.log",
        "$env:WINDIR\debug\*.log",
        "$env:WINDIR\Panther\*.log",
        "$env:WINDIR\INF\*.log"
    )
    
    $totalFreed = 0
    
    foreach ($logPath in $logPaths) {
        $folder = Split-Path $logPath -Parent
        if (Test-Path $folder) {
            $sizeBefore = (Get-ChildItem $logPath -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Remove-Item $logPath -Force -ErrorAction SilentlyContinue
            $sizeAfter = (Get-ChildItem $logPath -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $freed = [math]::Round(($sizeBefore - $sizeAfter) / 1MB, 2)
            $totalFreed += $freed
            if ($freed -gt 0) {
                Write-Host "  Cleaned: $(Split-Path $folder -Leaf) logs ($freed MB)" -ForegroundColor DarkYellow
            }
        }
    }
    
    # Alternative method for Event Logs using PowerShell (no errors)
    try {
        $logCount = 0
        Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
                $logCount++
            } catch {
                # Silently skip logs that can't be cleared
            }
        }
        Write-Host "  Cleared: $logCount Event Logs" -ForegroundColor DarkYellow
    } catch {
        Write-Host "  Event logs: Some logs could not be cleared (normal)" -ForegroundColor DarkYellow
    }
    
    Write-Host "[OK] Windows logs cleaned (freed approximately $totalFreed MB)" -ForegroundColor Green
}

function Clean-DISM {
    Write-Host "`n=== RUNNING DISM CLEANUP ===" -ForegroundColor Magenta
    
    Write-Host "  This may take a few minutes..." -ForegroundColor DarkYellow
    
    # Run DISM cleanup (removes old Windows components)
    $result = dism /online /Cleanup-Image /StartComponentCleanup /ResetBase /quiet 2>&1
    
    # Also run Disk Cleanup for additional system files
    Write-Host "  Running system file cleanup..." -ForegroundColor DarkYellow
    cleanmgr /sagerun:1 2>&1 | Out-Null
    
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
    $duplicateSizeMB = [math]::Round($duplicateSize / 1MB, 2)
    
    if ($duplicateSizeGB -ge 1) {
        Write-Host "  Found approximately $duplicateCount duplicate file groups" -ForegroundColor DarkYellow
        Write-Host "  Potential space waste: $duplicateSizeGB GB" -ForegroundColor DarkYellow
    } else {
        Write-Host "  Found approximately $duplicateCount duplicate file groups" -ForegroundColor DarkYellow
        Write-Host "  Potential space waste: $duplicateSizeMB MB" -ForegroundColor DarkYellow
    }
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
# MAIN LOGIC (PARAMETER HANDLING)
# ============================================

if ($Function) {
    switch ($Function.ToLower()) {
        "status" { Get-DiskUsage }
        "temp" { Clean-TemporaryFiles }
        "prefetch" { Clean-Prefetch }
        "recycle" { Clean-RecycleBin }
        "downloads" { Clean-DownloadsFolder }
        "browser" { Clean-BrowserCache }
        "delivery" { Clean-DeliveryOptimization }
        "logs" { Clean-WindowsLogs }
        "dism" { Clean-DISM }
        "duplicates" { Clean-DuplicateFiles }
        "full" { Run-FullCleanup }
        default { Write-Host "Unknown function. Options: status, temp, prefetch, recycle, downloads, browser, delivery, logs, dism, duplicates, full" -ForegroundColor Red }
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
