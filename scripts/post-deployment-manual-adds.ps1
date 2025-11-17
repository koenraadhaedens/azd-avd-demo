# Post-Deployment Setup Script
# This script automates the post-deployment tasks for manual ADDS integration

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipReversePeering
)

Write-Host "=== AVD Manual ADDS Post-Deployment Setup ===" -ForegroundColor Cyan
Write-Host ""

# Get current azd environment if not specified
if (-not $EnvironmentName) {
    try {
        $azdEnv = azd env list --output json | ConvertFrom-Json
        if ($azdEnv -and $azdEnv.Count -eq 1) {
            $EnvironmentName = $azdEnv[0].Name
            Write-Host "Using azd environment: $EnvironmentName" -ForegroundColor Green
        } elseif ($azdEnv -and $azdEnv.Count -gt 1) {
            Write-Host "Multiple azd environments found:" -ForegroundColor Yellow
            $azdEnv | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }
            $EnvironmentName = Read-Host "Enter environment name"
        } else {
            Write-Host "No azd environments found. Please run 'azd init' first." -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "Could not detect azd environment. Please specify -EnvironmentName parameter." -ForegroundColor Red
        exit 1
    }
}

# Get deployment outputs
Write-Host "Retrieving deployment information..." -ForegroundColor Yellow
try {
    $outputs = azd env get-values --environment $EnvironmentName --output json | ConvertFrom-Json -ErrorAction Stop
    
    # Convert PSCustomObject to hashtable for easier access
    $outputsHash = @{}
    $outputs.PSObject.Properties | ForEach-Object { $outputsHash[$_.Name] = $_.Value }
    
} catch {
    Write-Host "Could not retrieve deployment outputs. Make sure 'azd up' completed successfully." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Display deployment summary
Write-Host ""
Write-Host "=== Deployment Summary ===" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentName" -ForegroundColor White
Write-Host "Domain: $($outputsHash.domainName)" -ForegroundColor White
Write-Host "DNS Server IP: $($outputsHash.dnsServerIp)" -ForegroundColor White
Write-Host "Domain Controller VNet: $($outputsHash.domainControllerVnetId)" -ForegroundColor White
Write-Host "AVD VNet ID: $($outputsHash.avdVnetId)" -ForegroundColor White
Write-Host ""

# Check required outputs
$requiredOutputs = @('domainControllerVnetId', 'avdVnetId', 'dnsServerIp')
$missingOutputs = @()

foreach ($output in $requiredOutputs) {
    if (-not $outputsHash.ContainsKey($output) -or [string]::IsNullOrEmpty($outputsHash[$output])) {
        $missingOutputs += $output
    }
}

if ($missingOutputs.Count -gt 0) {
    Write-Host "Missing required deployment outputs:" -ForegroundColor Red
    $missingOutputs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Please ensure the deployment completed successfully." -ForegroundColor Red
    exit 1
}

# Setup reverse VNet peering
if (-not $SkipReversePeering) {
    Write-Host "=== Setting up Reverse VNet Peering ===" -ForegroundColor Cyan
    Write-Host ""
    
    $dcVnetId = $outputsHash.domainControllerVnetId
    $avdVnetId = $outputsHash.avdVnetId
    
    Write-Host "Setting up peering: Domain Controller VNet -> AVD VNet" -ForegroundColor Yellow
    
    try {
        & "$PSScriptRoot\setup-reverse-peering.ps1" -DomainControllerVnetId $dcVnetId -AvdVnetId $avdVnetId
        Write-Host ""
        Write-Host "✓ Reverse VNet peering setup completed" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "⚠ Reverse VNet peering setup failed or was skipped" -ForegroundColor Yellow
        Write-Host "You can run it manually later:" -ForegroundColor White
        Write-Host "  .\scripts\setup-reverse-peering.ps1 -DomainControllerVnetId `"$dcVnetId`" -AvdVnetId `"$avdVnetId`"" -ForegroundColor Gray
    }
} else {
    Write-Host "Skipping reverse VNet peering setup (use -SkipReversePeering `$false to enable)" -ForegroundColor Yellow
}

# Next steps
Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Verify domain connectivity:" -ForegroundColor Yellow
Write-Host "   - Check that session hosts successfully joined the domain" -ForegroundColor White
Write-Host "   - Verify VNet peering is in 'Connected' state on both sides" -ForegroundColor White
Write-Host ""
Write-Host "2. Configure user access:" -ForegroundColor Yellow
Write-Host "   - Add users to the AVD application group" -ForegroundColor White
Write-Host "   - Assign appropriate permissions on FSLogix file share" -ForegroundColor White
Write-Host ""
Write-Host "3. Test AVD functionality:" -ForegroundColor Yellow
Write-Host "   - Connect to AVD workspace using Remote Desktop client" -ForegroundColor White
Write-Host "   - Verify user profiles are created in FSLogix storage" -ForegroundColor White
Write-Host ""

# Display resource information
if ($outputsHash.ContainsKey('resourceGroupName')) {
    Write-Host "Resource Group: $($outputsHash.resourceGroupName)" -ForegroundColor Cyan
}
if ($outputsHash.ContainsKey('hostPoolName')) {
    Write-Host "Host Pool: $($outputsHash.hostPoolName)" -ForegroundColor Cyan
}
if ($outputsHash.ContainsKey('workspaceName')) {
    Write-Host "Workspace: $($outputsHash.workspaceName)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "✓ Post-deployment setup completed!" -ForegroundColor Green