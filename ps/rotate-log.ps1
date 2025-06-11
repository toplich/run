# Шлях до основного лог-файлу
$LogPath = "C:\Scripts\check-iscsi.log"

# Папка для архівів
$ArchiveFolder = "C:\Scripts\Logs"

# Параметри очищення
$MaxSizeBytes = 1MB
$MaxAgeDays = 7

# Створити папку архіву, якщо не існує
if (-not (Test-Path $ArchiveFolder)) {
    New-Item -ItemType Directory -Path $ArchiveFolder | Out-Null
}

# Перевірка існування логу
if (Test-Path $LogPath) {
    $logItem = Get-Item $LogPath
    $tooOld = $logItem.LastWriteTime -lt (Get-Date).AddDays(-$MaxAgeDays)
    $tooLarge = $logItem.Length -gt $MaxSizeBytes

    if ($tooOld -or $tooLarge) {
        # Створити архівну копію
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $ArchivePath = Join-Path $ArchiveFolder "check-iscsi_$timestamp.log"
        Copy-Item $LogPath $ArchivePath

        # Очистити основний лог
        Clear-Content $LogPath
        Add-Content $LogPath "[$(Get-Date -Format u)] Лог очищено. Архів: $ArchivePath"
    }
}
