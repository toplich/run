# Конфігурація
$target = "iqn.2000-01.com.synology:storage.target01"
$mountPath = "R:\"
$logPath = "C:\Logs\iscsi-monitor.log"

function Log {
    param ($msg)
    Add-Content -Path $logPath -Value "$(Get-Date -Format u) - $msg"
}

# 1️⃣ Перевірка активної iSCSI-сесії
$sessions = Get-IscsiSession
$active = $sessions | Where-Object { $_.TargetNodeAddress -eq $target }

# 2️⃣ Перевірка доступності файлової системи
$fsAccessible = $false
try {
    $tmp = Join-Path $mountPath "test-iscsi.txt"
    New-Item -Path $tmp -ItemType File -Force | Out-Null
    Remove-Item -Path $tmp -Force
    $fsAccessible = $true
} catch {
    $fsAccessible = $false
}

# 3️⃣ Логіка перезапуску
if (-not $active -or -not $fsAccessible) {
    Log "iSCSI inactive or filesystem inaccessible. Reconnecting..."
    try {
        # Якщо є активне підключення — від'єднати
        if ($active) {
            Disconnect-IscsiTarget -NodeAddress $target -Confirm:$false
            Start-Sleep -Seconds 3
        }

        # Повторне підключення
        Connect-IscsiTarget -NodeAddress $target -IsPersistent $true | Out-Null
        Log "Reconnection successful."
    } catch {
        Log "Reconnection failed: $_"
    }
} else {
    Log "iSCSI session and filesystem are healthy."
}
