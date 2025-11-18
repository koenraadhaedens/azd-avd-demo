#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory=$true)]
    [string]$HostPoolRegistrationToken,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$FileShareName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName
)

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force

# Create log directory
$LogPath = "C:\AVDDeployment"
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force
}

# Start logging
Start-Transcript -Path "$LogPath\SessionHostConfig.log" -Force

Write-Host "Starting AVD session host configuration..." -ForegroundColor Green
Write-Host "Computer Name: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "Storage Account: $StorageAccountName"

# Download and install AVD Boot Loader
Write-Host "Downloading AVD Boot Loader..." -ForegroundColor Yellow
try {
    $bootLoaderUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $bootLoaderPath = "$env:TEMP\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi"
    
    Invoke-WebRequest -Uri $bootLoaderUrl -OutFile $bootLoaderPath -UseBasicParsing
    
    Write-Host "Installing AVD Boot Loader..." -ForegroundColor Yellow
    Start-Process msiexec.exe -ArgumentList "/i $bootLoaderPath /quiet /norestart" -Wait
    Write-Host "AVD Boot Loader installed successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to install AVD Boot Loader: $($_.Exception.Message)"
}

# Download and install AVD Agent
Write-Host "Downloading AVD Agent..." -ForegroundColor Yellow
try {
    $agentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    $agentPath = "$env:TEMP\Microsoft.RDInfra.RDAgent.Installer-x64.msi"
    
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    
    Write-Host "Installing AVD Agent..." -ForegroundColor Yellow
    Start-Process msiexec.exe -ArgumentList "/i $agentPath /quiet /norestart REGISTRATIONTOKEN=$HostPoolRegistrationToken" -Wait
    Write-Host "AVD Agent installed successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to install AVD Agent: $($_.Exception.Message)"
}

# Configure FSLogix
Write-Host "Configuring FSLogix..." -ForegroundColor Yellow
try {
    # Configure FSLogix registry settings
    $fslogixRegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
    if (!(Test-Path $fslogixRegPath)) {
        New-Item -Path $fslogixRegPath -Force
    }
    
    $profilePath = "\\$StorageAccountName.file.core.windows.net\$FileShareName"
    
    Set-ItemProperty -Path $fslogixRegPath -Name "Enabled" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "VHDLocations" -Value $profilePath -Type String
    Set-ItemProperty -Path $fslogixRegPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "SizeInMBs" -Value 10240 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "IsDynamic" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "VolumeType" -Value "VHDX" -Type String
    
    Write-Host "FSLogix configured successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to configure FSLogix: $($_.Exception.Message)"
}

# Configure timezone to UTC
Write-Host "Setting timezone to UTC..." -ForegroundColor Yellow
try {
    Set-TimeZone -Id "UTC"
    Write-Host "Timezone set to UTC" -ForegroundColor Green
}
catch {
    Write-Error "Failed to set timezone: $($_.Exception.Message)"
}

# Enable RDP
Write-Host "Enabling Remote Desktop..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Write-Host "Remote Desktop enabled" -ForegroundColor Green
}
catch {
    Write-Error "Failed to enable RDP: $($_.Exception.Message)"
}

Write-Host "Session host configuration completed!" -ForegroundColor Green
Stop-Transcript