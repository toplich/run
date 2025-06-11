# Параметри завдання
$TaskName = "Rotate-iSCSI-Log"
$ScriptPath = "C:\Scripts\rotate-log.ps1"

# Створити тригер (щодня о 02:00)
$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

# Дія – запуск PowerShell з потрібним скриптом
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""

# Опціонально: вказати користувача (поточний)
$User = "$env:UserDomain\$env:UserName"

# Реєстрація завдання
Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -User $User -RunLevel Highest -Force

Write-Host "✅ Завдання '$TaskName' створено для щоденного очищення логів."
