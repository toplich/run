<# 
.SYNOPSIS
    Quick inventory: OS Name + Version + Build from AD
#>

Import-Module ActiveDirectory

Get-ADComputer -Filter 'Enabled -eq $True' -Properties OperatingSystem, OperatingSystemVersion, lastLogonTimestamp |
    Select-Object `
        Name,
        OperatingSystem,
        OperatingSystemVersion,
        @{ n='LastLogon'; e={[DateTime]::FromFileTime($_.lastLogonTimestamp)} } |
    Sort-Object Name |
    Export-Csv "C:\inetpub\AD_OS_Inventory.csv" -NoTypeInformation

Write-Host "Report saved to C:\inetpub\AD_OS_Inventory.csv"
