<# 
.SYNOPSIS
    Quick inventory: OS Name + Version + Build + IP via DNS lookup
#>

Import-Module ActiveDirectory

Get-ADComputer -Filter 'Enabled -eq $True' -Properties OperatingSystem, OperatingSystemVersion, lastLogonTimestamp, dNSHostName |
    Select-Object `
        Name,
        OperatingSystem,
        OperatingSystemVersion,
        @{ n='LastLogon'; e={ [DateTime]::FromFileTime($_.lastLogonTimestamp) } },
        @{ n='IPAddress';  e={
                try {
                    # Very fast DNS lookup
                    ([System.Net.Dns]::GetHostAddresses($_.dNSHostName) | 
                     Where-Object { $_.AddressFamily -eq "InterNetwork" } |
                     Select-Object -First 1).IPAddressToString
                }
                catch {
                    "Unknown"
                }
            }
        } |
    Sort-Object Name |
    Export-Csv "C:\Reports\AD_OS_Inventory.csv" -NoTypeInformation

Write-Host "Report saved to C:\Reports\AD_OS_Inventory.csv"
