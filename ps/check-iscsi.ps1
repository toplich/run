# iSCSI Monitor and Reconnect Script with CHAP
$target = "iqn.2000-01.com.synology:storage.target01"
$mountPath = "R:\"
$logPath = "C:\Logs\iscsi-monitor.log"

# CHAP credentials
$username = "chapuser"
$password = ConvertTo-SecureString "chapsecret" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($username, $password)

function Log {
    param ($msg)
    Add-Content -Path $logPath -Value "$(Get-Date -Format u) - $msg"
}

$sessions = Get-IscsiSession
$active = $sessions | Where-Object { $_.TargetNodeAddress -eq $target }

$fsAccessible = $false
try {
    $tmp = Join-Path $mountPath "test-iscsi.txt"
    New-Item -Path $tmp -ItemType File -Force | Out-Null
    Remove-Item -Path $tmp -Force
    $fsAccessible = $true
} catch {
    $fsAccessible = $false
}

if (-not $active -or -not $fsAccessible) {
    Log "iSCSI inactive or filesystem inaccessible. Reconnecting..."
    try {
        if ($active) {
            Disconnect-IscsiTarget -NodeAddress $target -Confirm:$false
            Start-Sleep -Seconds 3
        }
        Connect-IscsiTarget -NodeAddress $target -IsPersistent $true -AuthenticationType OneWayCHAP -Credential $cred | Out-Null
        Log "Reconnection successful."
    } catch {
        Log "Reconnection failed: $_"
    }
} else {
    Log "iSCSI session and filesystem are healthy."
}
