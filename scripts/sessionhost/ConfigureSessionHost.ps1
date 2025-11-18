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

# Verify domain join status
try {
    Write-Host "Verifying domain join status..." -ForegroundColor Yellow
    $computerInfo = Get-ComputerInfo
    $domainJoined = $computerInfo.PartOfDomain
    $currentDomain = $computerInfo.Domain
    
    if ($domainJoined -and ($currentDomain -eq $DomainName)) {
        Write-Host "✓ Computer is successfully joined to domain: $currentDomain" -ForegroundColor Green
    } elseif ($domainJoined) {
        Write-Warning "Computer is joined to domain '$currentDomain' but expected '$DomainName'"
    } else {
        Write-Warning "Computer is not domain joined. Some configurations may fail."
        Write-Host "Current workgroup: $($computerInfo.Workgroup)"
        
        # Wait a bit for domain join to complete if it's still in progress
        Write-Host "Waiting 60 seconds for domain join to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
        
        # Re-check domain status
        $computerInfo = Get-ComputerInfo
        $domainJoined = $computerInfo.PartOfDomain
        if ($domainJoined) {
            Write-Host "✓ Domain join completed: $($computerInfo.Domain)" -ForegroundColor Green
        } else {
            Write-Error "Domain join has not completed. Continuing with configuration..."
        }
    }
}
catch {
    Write-Error "Failed to verify domain join status: $($_.Exception.Message)"
}

# Download and install AVD Boot Loader
try {
    Write-Host "Downloading AVD Boot Loader..." -ForegroundColor Yellow
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
try {
    Write-Host "Downloading AVD Agent..." -ForegroundColor Yellow
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
try {
    Write-Host "Configuring FSLogix..." -ForegroundColor Yellow
    
    # Download FSLogix
    $fslogixUrl = "https://aka.ms/fslogix-latest"
    $fslogixZip = "$env:TEMP\FSLogix.zip"
    $fslogixPath = "$env:TEMP\FSLogix"
    
    Invoke-WebRequest -Uri $fslogixUrl -OutFile $fslogixZip -UseBasicParsing
    Expand-Archive -Path $fslogixZip -DestinationPath $fslogixPath -Force
    
    # Install FSLogix
    $fslogixInstaller = Get-ChildItem -Path $fslogixPath -Filter "FSLogixAppsSetup.exe" -Recurse
    if ($fslogixInstaller) {
        Write-Host "Installing FSLogix..." -ForegroundColor Yellow
        Start-Process -FilePath $fslogixInstaller.FullName -ArgumentList "/install /quiet /norestart" -Wait
    }
    
    # Configure FSLogix registry settings
    $fslogixRegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
    if (!(Test-Path $fslogixRegPath)) {
        New-Item -Path $fslogixRegPath -Force
    }
    
    $profilePath = "\\$StorageAccountName.file.core.windows.net\$FileShareName"
    
    Set-ItemProperty -Path $fslogixRegPath -Name "Enabled" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "VHDLocations" -Value $profilePath -Type String
    Set-ItemProperty -Path $fslogixRegPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "SizeInMBs" -Value 10240 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "IsDynamic" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "VolumeType" -Value "VHDX" -Type String
    Set-ItemProperty -Path $fslogixRegPath -Name "ConcurrentUserSessions" -Value 1 -Type DWORD
    
    # Additional FSLogix settings for better performance and reliability
    Set-ItemProperty -Path $fslogixRegPath -Name "ProfileType" -Value 0 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "RedirXMLSourceFolder" -Value $profilePath -Type String
    Set-ItemProperty -Path $fslogixRegPath -Name "AccessNetworkAsComputerObject" -Value 1 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "LockedRetryCount" -Value 3 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "LockedRetryInterval" -Value 15 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "ReAttachRetryCount" -Value 3 -Type DWORD
    Set-ItemProperty -Path $fslogixRegPath -Name "ReAttachIntervalSeconds" -Value 15 -Type DWORD
    
    Write-Host "FSLogix configured successfully" -ForegroundColor Green
    Write-Host "Profile path: $profilePath" -ForegroundColor White
    
    Write-Host "Note: NTFS permissions and RBAC roles are configured via post-deployment script" -ForegroundColor Yellow
}
catch {
    Write-Error "Failed to configure FSLogix: $($_.Exception.Message)"
}

# Configure timezone to UTC
try {
    Write-Host "Setting timezone to UTC..." -ForegroundColor Yellow
    Set-TimeZone -Id "UTC"
    Write-Host "Timezone set to UTC" -ForegroundColor Green
}
catch {
    Write-Error "Failed to set timezone: $($_.Exception.Message)"
}

# Enable RDP
try {
    Write-Host "Enabling Remote Desktop..." -ForegroundColor Yellow
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Write-Host "Remote Desktop enabled" -ForegroundColor Green
}
catch {
    Write-Error "Failed to enable RDP: $($_.Exception.Message)"
}

# Configure Windows Update settings
try {
    Write-Host "Configuring Windows Update..." -ForegroundColor Yellow
    $updatePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (!(Test-Path $updatePath)) {
        New-Item -Path $updatePath -Force
    }
    Set-ItemProperty -Path $updatePath -Name "NoAutoUpdate" -Value 0 -Type DWORD
    Set-ItemProperty -Path $updatePath -Name "AUOptions" -Value 4 -Type DWORD
    Set-ItemProperty -Path $updatePath -Name "ScheduledInstallDay" -Value 0 -Type DWORD
    Set-ItemProperty -Path $updatePath -Name "ScheduledInstallTime" -Value 3 -Type DWORD
    Write-Host "Windows Update configured" -ForegroundColor Green
}
catch {
    Write-Error "Failed to configure Windows Update: $($_.Exception.Message)"
}

# Create App Attach directory
try {
    Write-Host "Creating App Attach directory..." -ForegroundColor Yellow
    $appAttachPath = "C:\AppAttach"
    if (!(Test-Path $appAttachPath)) {
        New-Item -ItemType Directory -Path $appAttachPath -Force
    }
    Write-Host "App Attach directory created: $appAttachPath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create App Attach directory: $($_.Exception.Message)"
}

# Install additional tools
try {
    Write-Host "Installing additional tools..." -ForegroundColor Yellow
    
    # Install Microsoft Edge WebView2
    $webview2Url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
    $webview2Path = "$env:TEMP\MicrosoftEdgeWebview2Setup.exe"
    Invoke-WebRequest -Uri $webview2Url -OutFile $webview2Path -UseBasicParsing
    Start-Process -FilePath $webview2Path -ArgumentList "/silent /install" -Wait
    
    # Install Microsoft Visual C++ Redistributable
    $vcredistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $vcredistPath = "$env:TEMP\vc_redist.x64.exe"
    Invoke-WebRequest -Uri $vcredistUrl -OutFile $vcredistPath -UseBasicParsing
    Start-Process -FilePath $vcredistPath -ArgumentList "/install /quiet /norestart" -Wait
    
    Write-Host "Additional tools installed" -ForegroundColor Green
}
catch {
    Write-Error "Failed to install additional tools: $($_.Exception.Message)"
}

# Configure power settings
try {
    Write-Host "Configuring power settings..." -ForegroundColor Yellow
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  # High performance
    powercfg /change monitor-timeout-ac 0
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    Write-Host "Power settings configured" -ForegroundColor Green
}
catch {
    Write-Error "Failed to configure power settings: $($_.Exception.Message)"
}

Write-Host "Session host configuration completed!" -ForegroundColor Green
Write-Host "Configuration summary:" -ForegroundColor Cyan
Write-Host "  - AVD Agent installed and registered" -ForegroundColor White
Write-Host "  - FSLogix configured for profiles" -ForegroundColor White
Write-Host "  - Remote Desktop enabled" -ForegroundColor White
Write-Host "  - App Attach directory created" -ForegroundColor White
Write-Host "  - Additional tools installed" -ForegroundColor White
Write-Host "  - Power settings optimized" -ForegroundColor White

Stop-Transcript

# Restart required for some configurations to take effect
Write-Host "Restarting computer to complete configuration..." -ForegroundColor Yellow
Restart-Computer -Force