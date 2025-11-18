#!/usr/bin/env pwsh

# Script to regenerate AVD host pool registration token
# Use this when the original token has expired (default is 2 hours)

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$HostPoolName,
    
    [Parameter(Mandatory=$false)]
    [int]$ExpirationHours = 24
)

Write-Host "=== AVD Host Pool Token Regeneration ===" -ForegroundColor Cyan
Write-Host ""

# Check if Azure PowerShell module is available
try {
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.DesktopVirtualization -ErrorAction Stop
} catch {
    Write-Host "Azure PowerShell modules not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az.DesktopVirtualization -Force -AllowClobber
    Import-Module Az.DesktopVirtualization
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

# Get current host pool information
try {
    Write-Host "Checking host pool status..." -ForegroundColor Yellow
    $hostPool = Get-AzWvdHostPool -ResourceGroupName $ResourceGroupName -Name $HostPoolName -ErrorAction Stop
    
    Write-Host "✓ Found host pool: $($hostPool.Name)" -ForegroundColor Green
    Write-Host "  Type: $($hostPool.HostPoolType)" -ForegroundColor White
    Write-Host "  Load Balancer: $($hostPool.LoadBalancerType)" -ForegroundColor White
    Write-Host "  Max Sessions: $($hostPool.MaxSessionLimit)" -ForegroundColor White
    
    # Get current session hosts
    $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName
    Write-Host "  Current Session Hosts: $($sessionHosts.Count)" -ForegroundColor White
    
    if ($sessionHosts.Count -eq 0) {
        Write-Host "  ⚠ No session hosts found in host pool" -ForegroundColor Yellow
    } else {
        Write-Host "  Session Hosts:" -ForegroundColor White
        foreach ($host in $sessionHosts) {
            $status = $host.Status
            $statusColor = switch ($status) {
                "Available" { "Green" }
                "Unavailable" { "Red" }
                "Disconnected" { "Yellow" }
                default { "White" }
            }
            Write-Host "    - $($host.Name): $status" -ForegroundColor $statusColor
        }
    }
    
} catch {
    Write-Host "✗ Error getting host pool information: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Generate new registration token
try {
    Write-Host ""
    Write-Host "Generating new registration token (expires in $ExpirationHours hours)..." -ForegroundColor Yellow
    
    $expirationTime = (Get-Date).AddHours($ExpirationHours).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    
    $newToken = New-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -ExpirationTime $expirationTime
    
    Write-Host "✓ New registration token generated successfully" -ForegroundColor Green
    Write-Host "  Expiration: $expirationTime" -ForegroundColor White
    Write-Host ""
    
    # Output the token (be careful with this in production)
    Write-Host "New Registration Token:" -ForegroundColor Cyan
    Write-Host $newToken.Token -ForegroundColor White
    Write-Host ""
    
    # Save token to file for automation
    $tokenFile = ".\hostpool-token-$EnvironmentName.txt"
    $newToken.Token | Out-File -FilePath $tokenFile -Force
    Write-Host "Token saved to: $tokenFile" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Error generating registration token: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Show next steps
Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Use this token to register existing VMs to the host pool" -ForegroundColor White
Write-Host "2. Or redeploy session hosts with the new token" -ForegroundColor White
Write-Host ""
Write-Host "To manually register a VM, run this on each session host:" -ForegroundColor Yellow
Write-Host 'msiexec /i "Microsoft.RDInfra.RDAgent.Installer-x64.msi" /quiet REGISTRATIONTOKEN="<TOKEN>"' -ForegroundColor White
Write-Host ""
Write-Host "Or run the session host configuration script with the new token." -ForegroundColor Yellow