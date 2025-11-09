<#
.SYNOPSIS
Automatic NVIDIA vGPU license update via FastAPI-DLS
– Uses standard ssh and scp
– Stores files in /home/<user>/<hostname>/
– Password is passed via here-string (expect)
#>

# ========== Configuration ==========
$LinuxHost = "192.168.11.23"
$LinuxUser = "administrator"
$HomeDIR = "/home/$LinuxUser"
$Patcher = "$HomeDIR/gridd-unlock-patcher"
$RootCA = "$HomeDIR/rootCA.pem"

# ----------------------- SYSTEM INFORMATION -----------------------
$HostName = $env:COMPUTERNAME
$RemoteHostDir = "$HomeDIR/$HostName"
$RemoteDllPath = "$RemoteHostDir/nvxdapix.dll"
$LocalOutPath = "$HOME\Desktop\"
$TokenDir = "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken"
$Timestamp = Get-Date -Format "dd-MM-yy-HH-mm-ss"
$TokenPath = "$TokenDir\client_configuration_token_$Timestamp.tok"
$searchRoot = "C:\Windows\System32\DriverStore\FileRepository"
$dllName = "nvxdapix.dll"
$replacementDll = "$HOME\Desktop\nvxdapix.dll"
$logFile = "$HOME\dll_replacement_log.txt"
# ===================================

Write-Host "`n Windows host: $HostName" -ForegroundColor Cyan
Write-Host " FastAPI-DLS server: $LinuxHost" -ForegroundColor Cyan
Write-Host " Remote directory: $RemoteHostDir`n" -ForegroundColor Cyan

# ----------------------- 1 Check Linux server availability -----------------------
Write-Host " Checking Linux server availability..." -ForegroundColor Cyan
if (-not (Test-Connection -ComputerName $LinuxHost -Count 1 -Quiet)) {
    Write-Host " Server $LinuxHost is unreachable." -ForegroundColor Red
    exit
}

# ----------------------- 2 Search for $dllName -----------------------
Write-Host "`n Searching for $dllName in DriverStore..." -ForegroundColor Cyan
$dll = Get-ChildItem -Path $searchRoot -Recurse -Filter $dllName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dll) {
    Write-Host " $dllName not found." -ForegroundColor Red
    exit
}
Write-Host "Found: $($dll.FullName)"

# ----------------------- 3 Create directory -----------------------
Write-Host "Creating directory $RemoteHostDir" -ForegroundColor Cyan
$cmd = "mkdir -p '$RemoteHostDir'"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${LinuxUser}@${LinuxHost} "bash -c '$cmd'"

# ----------------------- 4 Check Root-CA -----------------------
Write-Host "`nChecking for Root-CA..." -ForegroundColor Cyan

# формуємо чистий bash-рядок у змінній
$checkCmd = "if [ -f '$RootCA' ]; then echo 1; else echo 0; fi"

# передаємо як аргумент до bash -c, без подвійного цитування
$exists = ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null `
    -o PreferredAuthentications=password -o PubkeyAuthentication=no `
    ${LinuxUser}@${LinuxHost} "bash -c '$checkCmd'"

if ($exists -and $exists.Trim() -eq "1") {
    Write-Host "Root-CA already exists" -ForegroundColor Green
}
else {
    Write-Host "Creating new Root-CA from FastAPI-DLS..." -ForegroundColor Yellow
    $createCmd = "curl -k -o '$RootCA' https://$LinuxHost/-/config/root-certificate"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null `
        -o PreferredAuthentications=password -o PubkeyAuthentication=no `
        ${LinuxUser}@${LinuxHost} "bash -c '$createCmd'"
}

# ----------------------- 5 Copy $dllName to Linux -----------------------
Write-Host "`n Copying $dllName to $RemoteHostDir..." -ForegroundColor Cyan
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $dll.FullName "${LinuxUser}@${LinuxHost}:${RemoteDllPath}"

# ----------------------- 6 Run patch -----------------------
Write-Host "`n Running patch on Linux..." -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${LinuxUser}@${LinuxHost} "$Patcher -g $RemoteDllPath -c $RootCA"

# ----------------------- 7 Copy back -----------------------
Write-Host "`n Downloading patched file to $LocalOutPath..." -ForegroundColor Cyan
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${LinuxUser}@${LinuxHost}:${RemoteDllPath} "$LocalOutPath"

# ----------------------- 8 Replace the DLL -----------------------
# Search for the DLL
Write-Host "Searching for $dllName in $searchRoot..." -ForegroundColor Cyan
$dllPath = Get-ChildItem -Path $searchRoot -Recurse -Filter $dllName -ErrorAction SilentlyContinue | Select-Object -First 1

# Stop NV service before replacing the DLL
Stop-Service NVDisplay.ContainerLocalSystem

if ($dllPath) {
    $fullPath = $dllPath.FullName
    Write-Host "Found DLL: $fullPath"
    Add-Content -Path $logFile -Value "Found $dllName at: $fullPath"

    # Take ownership
    takeown /F $fullPath | Out-Null

    # Find "Admin Group" to support all locales e.g. "EN: administrators", "DE: Administratoren", ...
    $adminGroup = ([System.Security.Principal.SecurityIdentifier] "S-1-5-32-544").Translate([System.Security.Principal.NTAccount]).Value
    $adminGroupName = $adminGroup.Split('\')[1]

    # Grant full control to administrators
    $permission = "$adminGroupName`:F"
    icacls $fullPath /grant  $permission | Out-Null

    # Attempt to stop processes using the DLL (optional: may not apply to DriverStore)
    Get-Process | Where-Object {
        $_.Modules | Where-Object { $_.FileName -eq $fullPath }
    } | ForEach-Object {
        Write-Host "Stopping process: $($_.Name) (PID: $($_.Id))"
        Stop-Process -Id $_.Id -Force
    }

    # Replace the DLL
    Copy-Item -Path $replacementDll -Destination $fullPath -Force
    Write-Host "Replaced $dllName successfully."
    Add-Content -Path $logFile -Value "Replaced $dllName at $fullPath on $(Get-Date)"
} else {
    Write-Host "DLL not found."
    Add-Content -Path $logFile -Value "Failed to find $dllName in $searchRoot on $(Get-Date)"
}

# Start the service after the replacement
Start-Service NVDisplay.ContainerLocalSystem

# ----------------------- 9 Getting Client Token -----------------------
Write-Host "`n Get Client Token from FastAPI-DLS..." -ForegroundColor Cyan
curl.exe --insecure -L -X GET "https://$LinuxHost/-/client-token" -o $TokenPath
Write-Host " Token saved in: $TokenPath"

# ----------------------- 10 Restart Nvidia -----------------------
Write-Host "`n restart NVIDIA..." -ForegroundColor Cyan
Restart-Service NVDisplay.ContainerLocalSystem

# ----------------------- Check License -----------------------
Write-Host "`n Check License NVIDIA..." -ForegroundColor Yellow
sleep 60
& nvidia-smi -q | Select-String "License"

# ----------------------- Completion -----------------------
Write-Host "`n Operation completed successfully!" -ForegroundColor Green
Write-Host "Patch saved in: $LocalOutPath"
