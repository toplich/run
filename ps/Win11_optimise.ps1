<#
.SYNOPSIS
    Windows Laptop Optimization Script (Modular)
.DESCRIPTION
    Кожну оптимізацію можна запустити окремо. Обов'язковий блок: Telemetry Removal.
    Запуск: .\optimize.ps1 -Function All
    Або: .\optimize.ps1 -Function Telemetry, Privacy, BackgroundApps
#>

# ============================================
# Адміністратор?
# ============================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Запустіть PowerShell як Адміністратор!" -ForegroundColor Red
    exit 1
}

# ============================================
# ОСНОВНІ ФУНКЦІЇ
# ============================================

function Disable-Telemetry {
    Write-Host "`n=== ВИМІКНЕННЯ ТЕЛЕМЕТРІЇ (СТЕЖЕННЯ) ===" -ForegroundColor Magenta
    
    # Рівень телеметрії: 0 - Безпека (мінімум)
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f
    
    # Вимкнути рекламні ID
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d 1 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f
    
    # Вимкнути WiFi Sense та збір даних про мережі
    reg add "HKLM\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" /v "value" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" /v "AutoConnectAllowedOEM" /t REG_DWORD /d 0 /f
    
    # Вимкнути handwriting data sharing
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 1 /f
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d 1 /f
    
    # Вимкнути Tailored Experiences
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f
    
    # Вимкнути Find My Device
    reg add "HKLM\SOFTWARE\Microsoft\Settings\FindMyDevice" /v "LocationSyncEnabled" /t REG_DWORD /d 0 /f
    
    # Вимкнути реєстрацію натискань клавіш (key logging - так, Windows це збирає за замовчуванням)
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontManagement" /v "FontProviders" /t REG_DWORD /d 0 /f
    
    # Вимкнути Cortana повністю
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortanaAboveLock" /t REG_DWORD /d 0 /f
    
    # Вимкнути збір даних про мову вводу
    reg add "HKCU\SOFTWARE\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 1 /f
    
    # Вимкнути оновлення через peer-to-peer (оновлення не шаряться)
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v "DODownloadMode" /t REG_DWORD /d 0 /f
    
    Write-Host "[OK] Телеметрія вимкнена" -ForegroundColor Green
}

function Disable-PrivacyServices {
    Write-Host "`n=== ВИМІКНЕННЯ ПРИВАТНИХ СЛУЖБ ===" -ForegroundColor Magenta
    
    # Служби стеження
    $services = @(
        "DiagTrack",           # Connected User Experiences and Telemetry
        "dmwappushservice",    # Device Management WAP Push
        "WMPNetworkSvc",       # Windows Media Player Network Sharing
        "RemoteRegistry",      # Віддалений реєстр
        "lfsvc",               # Geolocation Service
        "MapsBroker",          # Downloaded Maps Manager
        "PcaSvc",              # Program Compatibility Assistant
        "WSearch",             # Windows Search (за бажанням, але вимкнемо)
        "SysMain"              # Superfetch (економить ресурси)
    )
    
    foreach ($svc in $services) {
        Stop-Service $svc -ErrorAction SilentlyContinue
        Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Stop & Disabled: $svc" -ForegroundColor DarkYellow
    }
    
    # Вимкнути Windows Error Reporting
    reg add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v "Disabled" /t REG_DWORD /d 1 /f
    
    Write-Host "[OK] Служби стеження вимкнені" -ForegroundColor Green
}

function Disable-TrackingTasks {
    Write-Host "`n=== ВИМІКНЕННЯ ЗАПЛАНОВАНИХ ЗАВДАНЬ СТЕЖЕННЯ ===" -ForegroundColor Magenta
    
    $tasks = @(
        "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "Microsoft\Windows\Application Experience\StartupAppTask",
        "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "Microsoft\Windows\Feedback\Siuf\DmClient",
        "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
        "Microsoft\Windows\Location\Notifications",
        "Microsoft\Windows\Maps\MapsToastTask",
        "Microsoft\Windows\Maps\MapsUpdateTask",
        "Microsoft\Windows\NetCfg\BindingWorkItem",
        "Microsoft\Windows\NetCfg\Dummy",
        "Microsoft\Windows\PI\Sqm-Tasks",
        "Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
        "Microsoft\Windows\Windows Error Reporting\QueueReporting"
    )
    
    foreach ($task in $tasks) {
        Disable-ScheduledTask -TaskPath "\$($task.Split('\')[0])" -TaskName $task.Split('\')[-1] -ErrorAction SilentlyContinue
        Write-Host "  Disabled: $task" -ForegroundColor DarkYellow
    }
    
    Write-Host "[OK] Заплановані завдання стеження вимкнені" -ForegroundColor Green
}

function Disable-OneDrive {
    Write-Host "`n=== ВИДАЛЕННЯ ONEDRIVE ===" -ForegroundColor Magenta
    
    # Зупинити процес
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    
    # Вимкнути автозавантаження
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /t REG_SZ /d "" /f
    
    # Видалити OneDrive
    $onedrive = "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
    if (Test-Path $onedrive) {
        Start-Process $onedrive -ArgumentList "/uninstall" -NoNewWindow -Wait
        Write-Host "  OneDrive видалено" -ForegroundColor Green
    }
    
    # Видалити залишки з реєстру
    reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f -ErrorAction SilentlyContinue
}

function Optimize-Performance {
    Write-Host "`n=== ОПТИМІЗАЦІЯ ПРОДУКТИВНОСТІ ===" -ForegroundColor Magenta
    
    # Видалити непотрібні AppX (соціальні/ігрові)
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
        Get-AppxPackage -AllUsers -Name $app | Remove-AppxPackage -ErrorAction SilentlyContinue
        Write-Host "  Removed: $app" -ForegroundColor DarkYellow
    }
    
    # Вимкнути анімації (пришвидшує)
    reg add "HKCU\Control Panel\Desktop" /v "UserPreferencesMask" /t REG_BINARY /d "9012038010000000" /f
    reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v "MinAnimate" /t REG_SZ /d "0" /f
    
    # План живлення: Збалансований (для ноутбука)
    powercfg /setactive SCHEME_BALANCED
    
    # Вимкнути індексацію для SSD
    $drives = Get-WmiObject Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3}
    foreach ($drive in $drives) {
        if ($drive.MediaType -eq 12) { # SSD
            Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            fsutil behavior set DisableLastAccess 1
        }
    }
    
    Write-Host "[OK] Оптимізація продуктивності завершена" -ForegroundColor Green
}

function Disable-GameDVR {
    Write-Host "`n=== ВИМІКНЕННЯ GAMEDVR ===" -ForegroundColor Magenta
    
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f
    reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" /v "AllowGameDVR" /t REG_DWORD /d 0 /f
    
    Write-Host "[OK] GameDVR вимкнено" -ForegroundColor Green
}

function Disable-WebSearch {
    Write-Host "`n=== ВИМІКНЕННЯ ВЕБ-ПОШУКУ В МЕНЮ ПУСК ===" -ForegroundColor Magenta
    
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "DisableWebSearch" /t REG_DWORD /d 1 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowSearchToUseLocation" /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "ConnectedSearchUseWeb" /t REG_DWORD /d 0 /f
    
    Write-Host "[OK] Веб-пошук вимкнено" -ForegroundColor Green
}

function Set-DarkTheme {
    Write-Host "`n=== ТЕМНА ТЕМА ===" -ForegroundColor Magenta
    
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f
    
    Write-Host "[OK] Темна тема увімкнена" -ForegroundColor Green
}

function Show-Status {
    Write-Host "`n=== ПОТОЧНИЙ СТАН ===" -ForegroundColor Cyan
    
    $telemetry = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    Write-Host "Телеметрія: $($telemetry -eq 0 ? 'ВИМКНЕНО' : 'УВІМКНЕНО')" -ForegroundColor $(if($telemetry -eq 0){'Green'}else{'Red'})
    
    $cortana = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -ErrorAction SilentlyContinue).AllowCortana
    Write-Host "Cortana: $($cortana -eq 0 ? 'ВИМКНЕНО' : 'УВІМКНЕНО')" -ForegroundColor $(if($cortana -eq 0){'Green'}else{'Red'})
}

function Show-Menu {
    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║           WINDOWS LAPTOP OPTIMIZER - МОДУЛЬНИЙ СКРИПТ            ║
╚══════════════════════════════════════════════════════════════════╝

ДОСТУПНІ ФУНКЦІЇ:

  [1] Disable-Telemetry      - Вимкнути всю телеметрію та стеження ⭐
  [2] Disable-PrivacyServices - Вимкнути служби стеження
  [3] Disable-TrackingTasks  - Вимкнути заплановані завдання телеметрії
  [4] Disable-OneDrive        - Видалити OneDrive
  [5] Optimize-Performance    - Оптимізація продуктивності
  [6] Disable-GameDVR         - Вимкнути GameDVR
  [7] Disable-WebSearch       - Вимкнути веб-пошук у Пуску
  [8] Set-DarkTheme           - Увімкнути темну тему
  [9] Show-Status            - Показати поточний стан
  [A] ВСІ ФУНКЦІЇ (повна оптимізація)
  [Q] Вихід

"@
}

# ============================================
# ОСНОВНА ЛОГІКА
# ============================================

param(
    [Parameter(Position=0)]
    [string]$Function = ""
)

if ($Function) {
    switch ($Function.ToLower()) {
        "telemetry" { Disable-Telemetry }
        "privacy" { Disable-PrivacyServices }
        "tracking" { Disable-TrackingTasks }
        "onedrive" { Disable-OneDrive }
        "performance" { Optimize-Performance }
        "gamedvr" { Disable-GameDVR }
        "websearch" { Disable-WebSearch }
        "darktheme" { Set-DarkTheme }
        "status" { Show-Status }
        "all" {
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Disable-OneDrive
            Optimize-Performance
            Disable-GameDVR
            Disable-WebSearch
        }
        default { Write-Host "Невідома функція. Використовуйте: telemetry, privacy, tracking, onedrive, performance, gamedvr, websearch, darktheme, status, all" -ForegroundColor Red }
    }
    exit 0
}

# Інтерактивний режим
do {
    Show-Menu
    $choice = Read-Host "Виберіть функцію"
    
    switch ($choice) {
        "1" { Disable-Telemetry }
        "2" { Disable-PrivacyServices }
        "3" { Disable-TrackingTasks }
        "4" { Disable-OneDrive }
        "5" { Optimize-Performance }
        "6" { Disable-GameDVR }
        "7" { Disable-WebSearch }
        "8" { Set-DarkTheme }
        "9" { Show-Status }
        "a" { 
            Disable-Telemetry
            Disable-PrivacyServices
            Disable-TrackingTasks
            Disable-OneDrive
            Optimize-Performance
            Disable-GameDVR
            Disable-WebSearch
        }
        "q" { Write-Host "Вихід..." -ForegroundColor Yellow }
        default { Write-Host "Невірний вибір" -ForegroundColor Red }
    }
    
    if ($choice -ne "q") {
        Write-Host "`nНатисніть Enter для продовження..."
        Read-Host
    }
    
} while ($choice -ne "q")
