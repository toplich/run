# Task Scheduler Library taskschd.msc
$TaskName = "iSCSI Monitor"
$ScriptPath = "C:\Scripts\check-iscsi.ps1"

# Дія: запуск PowerShell із потрібним скриптом
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""

# Тригер: запуск один раз сьогодні і повторення кожні 5 хвилин протягом 24 годин
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 1)

# Права адміністратора
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

# Реєстрація завдання
Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Principal $Principal -Force
