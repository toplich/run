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
$LinuxPass = "88.Sieb-25!!AHDLS"
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

Write-Host "`n💻 Windows host: $HostName" -ForegroundColor Cyan
Write-Host "📡 FastAPI-DLS server: $LinuxHost" -ForegroundColor Cyan
Write-Host "📁 Remote directory: $RemoteHostDir`n" -ForegroundColor Cyan

# ----------------------- 1️⃣ Check Linux server availability -----------------------
Write-Host "🔍 Checking Linux server availability..." -ForegroundColor Cyan
if (-not (Test-Connection -ComputerName $LinuxHost -Count 1 -Quiet)) {
    Write-Host "❌ Server $LinuxHost is unreachable." -ForegroundColor Red
    exit
}

# ----------------------- 2️⃣ Search for $dllName -----------------------
Write-Host "`n🔍 Searching for $dllName in DriverStore..." -ForegroundColor Cyan
$dll = Get-ChildItem -Path $searchRoot -Recurse -Filter $dllName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $dll) {
    Write-Host "❌ $dllName not found." -ForegroundColor Red
    exit
}
Write-Host "✅ Found: $($dll.FullName)"

# ----------------------- 3️⃣ Create directory -----------------------
Write-Host "`n📂 Creating directory $RemoteHostDir..." -ForegroundColor Cyan
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $LinuxUser@$LinuxHost "bash -c 'mkdir -p $RemoteHostDir && chmod 700 $RemoteHostDir'"

# ----------------------- 4️⃣ Check Root-CA -----------------------
Write-Host "`n🔑 Checking for Root-CA..." -ForegroundColor Cyan
$exists = ssh $LinuxUser@$LinuxHost "if [ -f $RootCA ]; then echo 1; else echo 0; fi"
if ($exists.Trim() -eq "1") {
    Write-Host "✅ Root-CA already exists"
} else {
    Write-Host "⚙️ Creating new Root-CA from FastAPI-DLS..." -ForegroundColor Yellow
    ssh $LinuxUser@$LinuxHost "curl -k -o $RootCA https://$LinuxHost/-/config/root-certificate"
}

# ----------------------- 5️⃣ Copy $dllName to Linux -----------------------
Write-Host "`n📤 Copying $dllName to $RemoteHostDir..." -ForegroundColor Cyan
scp $dll.FullName $LinuxUser"@"$LinuxHost":"$RemoteDllPath

# ----------------------- 6️⃣ Run patch -----------------------
Write-Host "`n⚙️ Running patch on Linux..." -ForegroundColor Cyan
ssh $LinuxUser@$LinuxHost "$Patcher -g $RemoteDllPath -c $RootCA"

# ----------------------- 7️⃣ Copy back -----------------------
Write-Host "`n📥 Downloading patched file to $LocalOutPath..." -ForegroundColor Cyan
scp $LinuxUser@$LinuxHost":"$RemoteDllPath "$LocalOutPath"

# Search for the DLL
Write-Host "Searching for $dllName in $searchRoot..."
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

# ----------------------- 8️⃣ Getting Client Token -----------------------
Write-Host "`n🔑 Get Client Token from FastAPI-DLS..." -ForegroundColor Cyan
curl.exe --insecure -L -X GET "https://$LinuxHost/-/client-token" -o $TokenPath
Write-Host "✅ Token saved in: $TokenPath"

# ----------------------- 9️⃣ Restart Nvidia -----------------------
Write-Host "`n🔄 restart NVIDIA..." -ForegroundColor Cyan
Restart-Service NVDisplay.ContainerLocalSystem

# ----------------------- 🔍 Check License -----------------------
Write-Host "`n🔍 Check License NVIDIA..." -ForegroundColor Yellow
sleep 120
& 'nvidia-smi' -q | Select-String "License"

# ----------------------- ✅ Completion -----------------------
Write-Host "`n✅ Operation completed successfully!" -ForegroundColor Green
Write-Host "📁 Patch saved in: $LocalOutPath"
