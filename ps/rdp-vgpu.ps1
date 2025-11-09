<#
.SYNOPSIS
One-click GPU optimization for Remote Desktop on Windows 10/11.
Checks and enables all key policies for hardware GPU rendering via RDP.

.DESCRIPTION
Activates:
 - UseHardwareGraphicsAdapter
 - fEnableHardwareRender
 - RemoteDesktopUseHardwareEncoder
 - EnableWddmDriver
 - Hardware-Accelerated GPU Scheduling (HwSchMode)
 - GPU priority for multimedia
#>

Write-Host "=== GPU RDP Optimization Script ===" -ForegroundColor Cyan

# --- 1. Enable GPU policies for Remote Desktop ---
$rdpKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
if (!(Test-Path $rdpKey)) { New-Item -Path $rdpKey -Force | Out-Null }

New-ItemProperty -Path $rdpKey -Name "UseHardwareDefaultGraphicsAdapter" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $rdpKey -Name "UseHardwareGraphicsAdapter" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $rdpKey -Name "fEnableHardwareRender" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $rdpKey -Name "RemoteDesktopUseHardwareEncoder" -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host "✅ RDP GPU policies enabled"

# --- 2. Enable WDDM driver for RDP sessions ---
$winstKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations"
if (!(Test-Path $winstKey)) { New-Item -Path $winstKey -Force | Out-Null }

New-ItemProperty -Path $winstKey -Name "EnableWddmDriver" -Value 1 -PropertyType DWord -Force | Out-Null
Write-Host "✅ WDDM driver enabled for RDP"

# --- 3. Enable Hardware-Accelerated GPU Scheduling (HAGS) ---
$gpuKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
if (!(Test-Path $gpuKey)) { New-Item -Path $gpuKey -Force | Out-Null }

New-ItemProperty -Path $gpuKey -Name "HwSchMode" -Value 2 -PropertyType DWord -Force | Out-Null
Write-Host "✅ Hardware-Accelerated GPU Scheduling enabled"

# --- 4. Set GPU priority for multimedia threads ---
$mediaKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
if (!(Test-Path $mediaKey)) { New-Item -Path $mediaKey -Force | Out-Null }

New-ItemProperty -Path $mediaKey -Name "GPUPriority" -Value 8 -PropertyType DWord -Force | Out-Null
Write-Host "✅ Multimedia GPU priority set to 8 (maximum)"

# --- 5. Summary ---
Write-Host "`nAll registry keys have been updated successfully." -ForegroundColor Green
Write-Host "A reboot is required for changes to take effect." -ForegroundColor Yellow
Write-Host "=== Done ===" -ForegroundColor Cyan
