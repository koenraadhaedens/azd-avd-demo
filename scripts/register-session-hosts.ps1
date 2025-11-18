#!/usr/bin/env pwsh

# Script to manually register VMs to AVD host pool
# Use this when VMs were created but not properly registered

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$HostPoolName,
    
    [Parameter(Mandatory=$false)]
    [string]$RegistrationToken
)

Write-Host "=== Manual AVD Session Host Registration ===" -ForegroundColor Cyan
Write-Host ""

# Check if Azure PowerShell module is available
try {
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Compute -ErrorAction Stop
    Import-Module Az.DesktopVirtualization -ErrorAction Stop
} catch {
    Write-Host "Azure PowerShell modules not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az.Compute, Az.DesktopVirtualization -Force -AllowClobber
}

# Check if logged in to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in to Azure. Please run: Connect-AzAccount" -ForegroundColor Red
    exit 1
}

# Get parameters if not provided
if (-not $ResourceGroupName) {
    if ($EnvironmentName) {
        $ResourceGroupName = "rg-$EnvironmentName"
    } else {
        Write-Host "Environment name or resource group name required" -ForegroundColor Red
        exit 1
    }
}

if (-not $HostPoolName) {
    if ($EnvironmentName) {
        $HostPoolName = "hp-$EnvironmentName"
    } else {
        Write-Host "Environment name or host pool name required" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Host Pool: $HostPoolName" -ForegroundColor Yellow
Write-Host ""

# Get or generate registration token
if (-not $RegistrationToken) {
    Write-Host "No registration token provided. Generating new token..." -ForegroundColor Yellow
    try {
        $expirationTime = (Get-Date).AddHours(24).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $tokenInfo = New-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -ExpirationTime $expirationTime
        $RegistrationToken = $tokenInfo.Token
        Write-Host "✓ Generated new registration token" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to generate registration token: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Find session host VMs
Write-Host "Finding session host VMs..." -ForegroundColor Yellow
try {
    $allVMs = Get-AzVM -ResourceGroupName $ResourceGroupName
    $sessionHostVMs = $allVMs | Where-Object { $_.Name -like "*$EnvironmentName*" -and $_.StorageProfile.ImageReference.Offer -like "*windows*" }
    
    if ($sessionHostVMs.Count -eq 0) {
        Write-Host "✗ No session host VMs found in resource group $ResourceGroupName" -ForegroundColor Red
        Write-Host "Looking for VMs with pattern: *$EnvironmentName*" -ForegroundColor Yellow
        
        # Show all VMs for debugging
        Write-Host "All VMs in resource group:" -ForegroundColor White
        foreach ($vm in $allVMs) {
            Write-Host "  - $($vm.Name)" -ForegroundColor White
        }
        exit 1
    }
    
    Write-Host "✓ Found $($sessionHostVMs.Count) session host VMs:" -ForegroundColor Green
    foreach ($vm in $sessionHostVMs) {
        Write-Host "  - $($vm.Name)" -ForegroundColor White
    }
    
} catch {
    Write-Host "✗ Error finding VMs: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check current session host registrations
Write-Host ""
Write-Host "Checking current host pool registrations..." -ForegroundColor Yellow
try {
    $currentHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -ErrorAction SilentlyContinue
    Write-Host "Currently registered hosts: $($currentHosts.Count)" -ForegroundColor White
    
    if ($currentHosts.Count -gt 0) {
        foreach ($host in $currentHosts) {
            Write-Host "  - $($host.Name): $($host.Status)" -ForegroundColor White
        }
    }
} catch {
    Write-Host "No hosts currently registered or error checking: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Create PowerShell script to run on each VM
$registrationScript = @"
# AVD Agent Registration Script
param([string]`$Token)

Write-Host "Starting AVD agent registration on `$env:COMPUTERNAME..." -ForegroundColor Green

# Stop any existing RD Agent services
try {
    Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Get-Service -Name "RdAgent" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Note: Some services were not running" -ForegroundColor Yellow
}

# Download and install/repair AVD Boot Loader
try {
    Write-Host "Downloading AVD Boot Loader..." -ForegroundColor Yellow
    `$bootLoaderUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    `$bootLoaderPath = "`$env:TEMP\Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi"
    
    Invoke-WebRequest -Uri `$bootLoaderUrl -OutFile `$bootLoaderPath -UseBasicParsing
    
    Write-Host "Installing/repairing AVD Boot Loader..." -ForegroundColor Yellow
    Start-Process msiexec.exe -ArgumentList "/i `$bootLoaderPath /quiet /norestart" -Wait
    Write-Host "✓ AVD Boot Loader installed" -ForegroundColor Green
} catch {
    Write-Error "Failed to install AVD Boot Loader: `$(`$_.Exception.Message)"
}

# Download and install/repair AVD Agent with new token
try {
    Write-Host "Downloading AVD Agent..." -ForegroundColor Yellow
    `$agentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    `$agentPath = "`$env:TEMP\Microsoft.RDInfra.RDAgent.Installer-x64.msi"
    
    Invoke-WebRequest -Uri `$agentUrl -OutFile `$agentPath -UseBasicParsing
    
    Write-Host "Installing AVD Agent with registration token..." -ForegroundColor Yellow
    Start-Process msiexec.exe -ArgumentList "/i `$agentPath /quiet /norestart REGISTRATIONTOKEN=`$Token" -Wait
    Write-Host "✓ AVD Agent registered successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to install AVD Agent: `$(`$_.Exception.Message)"
}

# Start services
try {
    Write-Host "Starting RD services..." -ForegroundColor Yellow
    Start-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    Start-Service -Name "RdAgent" -ErrorAction SilentlyContinue
    Write-Host "✓ RD services started" -ForegroundColor Green
} catch {
    Write-Warning "Some RD services may not have started properly"
}

Write-Host "Registration completed on `$env:COMPUTERNAME" -ForegroundColor Green
"@

# Execute registration script on each VM
Write-Host ""
Write-Host "Executing registration script on session host VMs..." -ForegroundColor Yellow

foreach ($vm in $sessionHostVMs) {
    Write-Host ""
    Write-Host "Processing VM: $($vm.Name)" -ForegroundColor Cyan
    
    try {
        # Check if VM is running
        $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status
        $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState*" } | Select-Object -ExpandProperty DisplayStatus
        
        if ($powerState -ne "VM running") {
            Write-Host "  ⚠ VM is not running (Status: $powerState). Starting VM..." -ForegroundColor Yellow
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait
            
            # Wait a bit for VM to start
            Write-Host "  Waiting for VM to start..." -ForegroundColor Yellow
            do {
                Start-Sleep -Seconds 30
                $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status
                $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState*" } | Select-Object -ExpandProperty DisplayStatus
                Write-Host "    VM Status: $powerState" -ForegroundColor White
            } while ($powerState -ne "VM running")
        }
        
        Write-Host "  ✓ VM is running" -ForegroundColor Green
        
        # Execute the registration script
        Write-Host "  Executing AVD agent registration..." -ForegroundColor Yellow
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm.Name -CommandId "RunPowerShellScript" -ScriptString $registrationScript -Parameter @{Token=$RegistrationToken}
        
        if ($result.Value[0].Message) {
            Write-Host "  Script Output:" -ForegroundColor White
            $result.Value[0].Message -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        }
        
        Write-Host "  ✓ Registration script completed on $($vm.Name)" -ForegroundColor Green
        
    } catch {
        Write-Host "  ✗ Error processing $($vm.Name): $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
}

# Wait a bit and then check registration status
Write-Host ""
Write-Host "Waiting 30 seconds for registrations to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Check final status
Write-Host ""
Write-Host "Checking final registration status..." -ForegroundColor Yellow
try {
    $finalHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -ErrorAction SilentlyContinue
    
    if ($finalHosts.Count -gt 0) {
        Write-Host "✓ Registered session hosts: $($finalHosts.Count)" -ForegroundColor Green
        foreach ($host in $finalHosts) {
            $statusColor = switch ($host.Status) {
                "Available" { "Green" }
                "Unavailable" { "Red" }
                "Disconnected" { "Yellow" }
                default { "White" }
            }
            Write-Host "  - $($host.Name): $($host.Status)" -ForegroundColor $statusColor
        }
    } else {
        Write-Host "⚠ No session hosts registered yet. This may take a few more minutes." -ForegroundColor Yellow
        Write-Host "Check the Azure portal in 5-10 minutes." -ForegroundColor White
    }
} catch {
    Write-Host "Error checking final status: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Registration Process Complete ===" -ForegroundColor Cyan
Write-Host "Check the AVD host pool in the Azure portal to verify session hosts are registered." -ForegroundColor White