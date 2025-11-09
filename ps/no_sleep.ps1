# Disable Sleep and Hibernation
powercfg /hibernate off
powercfg -change standby-timeout-ac 0
powercfg -change standby-timeout-dc 0
powercfg -change monitor-timeout-ac 0
powercfg -change monitor-timeout-dc 0
powercfg -change hibernate-timeout-ac 0
powercfg -change hibernate-timeout-dc 0

# Optional: High performance plan
powercfg -setactive SCHEME_MIN

Write-Host "✅ Sleep, monitor off and hibernate disabled. Power plan set to High Performance." -ForegroundColor Green
