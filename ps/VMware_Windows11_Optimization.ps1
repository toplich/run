# ============================================
# SAFE ENTERPRISE OPTIMIZATION FOR VMWARE VMs
# Version: 2.0 (with Delivery Optimization fix)
# Author: ChatGPT for Vitalii Stepchuk
# ============================================

Write-Host "Starting VMware Windows Optimization (Safe Enterprise Edition)..." -ForegroundColor Cyan

# -------------------------------------------------
# 1. Disable SysMain (Superfetch)
# -------------------------------------------------
Write-Host "Disabling SysMain..." -ForegroundColor Yellow
Stop-Service SysMain -ErrorAction SilentlyContinue
Set-Service SysMain -StartupType Disabled

# -------------------------------------------------
# 2. Disable Windows Search (recommended for VMs)
# -------------------------------------------------
Write-Host "Disabling Windows Search..." -ForegroundColor Yellow
Stop-Service WSearch -ErrorAction SilentlyContinue
Set-Service WSearch -StartupType Disabled

# -------------------------------------------------
# 3. Delivery Optimization FIX (Correct method)
# -------------------------------------------------
Write-Host "Applying Delivery Optimization Policy..." -ForegroundColor Yellow
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v "DODownloadMode" /t REG_DWORD /d 0 /f

# -------------------------------------------------
# 4. High Performance Power Plan
# -------------------------------------------------
Write-Host "Setting Power Plan to High Performance..." -ForegroundColor Yellow
powercfg -setactive SCHEME_MIN

# -------------------------------------------------
# 5. Disable Background Apps (UWP background agents)
# -------------------------------------------------
Write-Host "Disabling Background Apps..." -ForegroundColor Yellow
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v "GlobalUserDisabled" /t REG_DWORD /d 1 /f

# -------------------------------------------------
# 6. Disable GameDVR / GameBar
# -------------------------------------------------
Write-Host "Disabling GameDVR..." -ForegroundColor Yellow
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f
reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f

# -------------------------------------------------
# 7. Disable animations (better RDP performance)
# -------------------------------------------------
Write-Host "Optimizing Visual Effects..." -ForegroundColor Yellow
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v "VisualFXSetting" /t REG_DWORD /d 2 /f

# -------------------------------------------------
# 8. Disable Scheduled Disk Defrag (useless on VMs)
# -------------------------------------------------
Write-Host "Disabling Scheduled Defrag..." -ForegroundColor Yellow
Disable-ScheduledTask -TaskName "Microsoft\Windows\Defrag\ScheduledDefrag" -ErrorAction SilentlyContinue

# -------------------------------------------------
# 9. Disable Windows Tips & Suggestions
# -------------------------------------------------
Write-Host "Disabling Windows Tips..." -ForegroundColor Yellow
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SoftLandingEnabled" /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f

# -------------------------------------------------
# 10. Defender Optimization (safe — no disabling AV)
# -------------------------------------------------
#Write-Host "Optimizing Windows Defender scanning..." -ForegroundColor Yellow
#reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" /v "DisableScanningNetworkFiles" /t REG_DWORD /d 1 /f
#reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" /v "DisableArchiveScanning" /t REG_DWORD /d 1 /f

# -------------------------------------------------
# DONE
# -------------------------------------------------
Write-Host "Optimization Completed Successfully!" -ForegroundColor Green
