<# 
.SYNOPSIS
    Export all AD groups with their members.
#>

Import-Module ActiveDirectory

$groups = Get-ADGroup -Filter * 

$results = foreach ($g in $groups) {
    $members = Get-ADGroupMember $g -ErrorAction SilentlyContinue |
        Select -ExpandProperty SamAccountName

    [PSCustomObject]@{
        GroupName = $g.Name
        Members   = $members -join ";"
    }
}

$results | Export-Csv "C:\Reports\AD_Groups_Members.csv" -NoTypeInformation

Write-Host "Saved: AD_Groups_Members.csv"
