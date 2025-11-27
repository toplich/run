<# 
.SYNOPSIS
    Export domain users with their security groups.
#>

Import-Module ActiveDirectory

Get-ADUser -Filter * -Properties DisplayName, mail, memberOf, Enabled |
    Select-Object `
        SamAccountName,
        DisplayName,
        mail,
        Enabled,
        @{n="Groups";e={ ($_.memberOf | Get-ADGroup | Select -ExpandProperty Name) -join ";" }} |
    Export-Csv "C:\Reports\AD_Users_Groups.csv" -NoTypeInformation

Write-Host "Report saved to C:\Reports\AD_Users_Groups.csv"
