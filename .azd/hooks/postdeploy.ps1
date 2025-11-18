#!/usr/bin/env pwsh

# Post-deploy hook for azd
# This script runs automatically after the infrastructure deployment completes

Write-Host "=== Running Post-Deployment Configuration ===" -ForegroundColor Green

# Get deployment outputs from azd
$outputs = azd env get-values --output json | ConvertFrom-Json

# Extract required values
$environmentName = $outputs.AZURE_ENV_NAME
$resourceGroupName = $outputs.AZURE_RESOURCE_GROUP_NAME
$subscriptionId = $outputs.AZURE_SUBSCRIPTION_ID
$fslogixStorageAccountName = $outputs.AZURE_FSLOGIX_STORAGE_ACCOUNT_NAME
$appAttachStorageAccountName = $outputs.AZURE_APP_ATTACH_STORAGE_ACCOUNT_NAME

Write-Host "Environment: $environmentName" -ForegroundColor Yellow
Write-Host "Resource Group: $resourceGroupName" -ForegroundColor Yellow
Write-Host "FSLogix Storage: $fslogixStorageAccountName" -ForegroundColor Yellow
Write-Host "App Attach Storage: $appAttachStorageAccountName" -ForegroundColor Yellow

# Run the post-provision script with the required parameters
Write-Host "Executing post-provision configuration script..." -ForegroundColor Yellow

try {
    $scriptPath = Join-Path $PSScriptRoot "..\..\scripts\post-provision.ps1"
    
    & $scriptPath `
        -SubscriptionId $subscriptionId `
        -ResourceGroupName $resourceGroupName `
        -EnvironmentName $environmentName `
        -FSLogixStorageAccountName $fslogixStorageAccountName `
        -AppAttachStorageAccountName $appAttachStorageAccountName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Post-provision configuration completed successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Post-provision script completed with exit code: $LASTEXITCODE"
    }
}
catch {
    Write-Error "Failed to run post-provision script: $($_.Exception.Message)"
    Write-Host "You can run the script manually:" -ForegroundColor Yellow
    Write-Host ".\scripts\post-provision.ps1 -EnvironmentName '$environmentName' -ResourceGroupName '$resourceGroupName' -SubscriptionId '$subscriptionId' -FSLogixStorageAccountName '$fslogixStorageAccountName' -AppAttachStorageAccountName '$appAttachStorageAccountName'" -ForegroundColor Cyan
    
    # Don't fail the deployment for post-provision errors
    exit 0
}

Write-Host "=== Post-Deployment Configuration Complete ===" -ForegroundColor Green