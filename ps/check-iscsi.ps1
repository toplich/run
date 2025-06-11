# === iSCSI Monitor Script ===

# Налаштування параметрів
$TargetIP     = "192.168.1.2"
$TargetIQN    = "iqn.2000-01.com.synology:Target-veeam.KH86vrsf"
$ChapUser     = "veeam"
$ChapPassword = "StrongPass123"
$LogFile      = "C:\Scripts\iscsi-monitor.log"

function Write-Log {
    param ([string]$message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$timestamp`t$message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "=== Запуск моніторингу iSCSI ==="

# Перевірка активної сесії
$session = iscsicli SessionList | Select-String -Context 0,10 $TargetIQN

if ($session) {
    Write-Log "✅ Сесія з $TargetIQN активна."
    exit 0
} else {
    Write-Log "⚠️  Сесія з $TargetIQN відсутня. Спроба підключення..."
}

# Додаємо портал (може бути зайвим, якщо вже додано)
Write-Log "🌐 Додаємо Target Portal $TargetIP"
iscsicli QAddTargetPortal $TargetIP | Out-Null

# Отримуємо список таргетів
$targets = iscsicli ListTargets | Select-String $TargetIQN

if (!$targets) {
    Write-Log "❌ Таргет $TargetIQN не знайдено на порталі $TargetIP"
    exit 1
}

# Спроба підключення з CHAP
Write-Log "🔐 Спроба логіну до таргету через CHAP"
Start-Process -NoNewWindow -Wait -FilePath "iscsicli.exe" -ArgumentList @(
  "QLoginTarget", $TargetIQN, $ChapUser, $ChapPassword
)

Start-Sleep -Seconds 2

# Повторна перевірка сесії
$sessionNew = iscsicli SessionList | Select-String -Context 0,10 $TargetIQN

if ($sessionNew) {
    Write-Log "✅ Успішне підключення до $TargetIQN"
    exit 0
} else {
    Write-Log "❌ Не вдалося підключитися до $TargetIQN"
    exit 1
}
