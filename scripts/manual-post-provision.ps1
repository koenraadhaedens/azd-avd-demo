#!/usr/bin/env pwsh

# Manual Post-provision script for AVD environment
# Run this script manually with appropriate permissions if the automatic post-provision fails
# This script configures RBAC assignments and Azure AD groups

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZURE_RESOURCE_GROUP_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$FSLogixStorageAccountName = $env:AZURE_FSLOGIX_STORAGE_ACCOUNT_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$AppAttachStorageAccountName = $env:AZURE_APP_ATTACH_STORAGE_ACCOUNT_NAME
)

Write-Host "=== Manual Post-provision Configuration for AVD ===" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentName" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Green
Write-Host "FSLogix Storage Account: $FSLogixStorageAccountName" -ForegroundColor Green
Write-Host "App Attach Storage Account: $AppAttachStorageAccountName" -ForegroundColor Green

# Check if we're logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Please run 'Connect-AzAccount' first" -ForegroundColor Red
        exit 1
    }
    Write-Host "Using Azure context: $($context.Account.Id)" -ForegroundColor Yellow
}
catch {
    Write-Host "Azure PowerShell module not found. Please install it first:" -ForegroundColor Red
    Write-Host "Install-Module -Name Az -Scope CurrentUser -Force" -ForegroundColor Yellow
    exit 1
}

# Set subscription context
if ($SubscriptionId) {
    try {
        $currentContext = Get-AzContext
        if ($currentContext.Subscription.Id -ne $SubscriptionId) {
            Write-Host "Setting subscription context to: $SubscriptionId" -ForegroundColor Yellow
            Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        }
        Write-Host "Using subscription: $((Get-AzContext).Subscription.Id)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to set subscription context: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Verify storage accounts exist
Write-Host "`nVerifying storage accounts..." -ForegroundColor Yellow

try {
    $fslogixStorage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $FSLogixStorageAccountName -ErrorAction Stop
    Write-Host "✓ FSLogix storage account found: $($fslogixStorage.StorageAccountName)" -ForegroundColor Green
}
catch {
    Write-Host "✗ FSLogix storage account not found: $FSLogixStorageAccountName" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $appAttachStorage = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $AppAttachStorageAccountName -ErrorAction Stop
    Write-Host "✓ App Attach storage account found: $($appAttachStorage.StorageAccountName)" -ForegroundColor Green
}
catch {
    Write-Host "✗ App Attach storage account not found: $AppAttachStorageAccountName" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Function to create Azure AD group if it doesn't exist
function New-AzureADGroupIfNotExists {
    param(
        [string]$GroupName,
        [string]$Description
    )
    
    try {
        $group = Get-AzADGroup -DisplayName $GroupName -ErrorAction SilentlyContinue
        if (-not $group) {
            Write-Host "Creating Azure AD group: $GroupName" -ForegroundColor Yellow
            $group = New-AzADGroup -DisplayName $GroupName -MailNickname $GroupName.Replace(" ", "").Replace("-", "") -Description $Description
            Write-Host "✓ Created Azure AD group: $GroupName" -ForegroundColor Green
            Start-Sleep 5  # Wait for group creation
        }
        else {
            Write-Host "✓ Azure AD group already exists: $GroupName" -ForegroundColor Green
        }
        return $group.Id
    }
    catch {
        Write-Host "✗ Error working with Azure AD group $GroupName : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

Write-Host "`nCreating Azure AD groups..." -ForegroundColor Yellow

# Create AVD user groups
$avdAdminsGroupId = New-AzureADGroupIfNotExists -GroupName "AVD-Admins-$EnvironmentName" -Description "Azure Virtual Desktop Administrators for $EnvironmentName"
$avdUsersGroupId = New-AzureADGroupIfNotExists -GroupName "AVD-Users-$EnvironmentName" -Description "Azure Virtual Desktop Users for $EnvironmentName"

# Function to assign RBAC role
function Set-StorageRoleAssignment {
    param(
        [string]$StorageAccountId,
        [string]$PrincipalId,
        [string]$RoleDefinitionName,
        [string]$GroupName
    )
    
    try {
        $existingAssignment = Get-AzRoleAssignment -ObjectId $PrincipalId -RoleDefinitionName $RoleDefinitionName -Scope $StorageAccountId -ErrorAction SilentlyContinue
        if (-not $existingAssignment) {
            Write-Host "Assigning role '$RoleDefinitionName' to group '$GroupName'" -ForegroundColor Yellow
            New-AzRoleAssignment -ObjectId $PrincipalId -RoleDefinitionName $RoleDefinitionName -Scope $StorageAccountId -ErrorAction Stop
            Write-Host "✓ Role assignment completed" -ForegroundColor Green
        }
        else {
            Write-Host "✓ Role '$RoleDefinitionName' already assigned to group '$GroupName'" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "✗ Error assigning role '$RoleDefinitionName' to group '$GroupName': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    return $true
}

Write-Host "`nConfiguring RBAC roles..." -ForegroundColor Yellow

$success = $true

# Configure FSLogix storage permissions if group was created
if ($avdUsersGroupId) {
    $success = $success -and (Set-StorageRoleAssignment -StorageAccountId $fslogixStorage.Id -PrincipalId $avdUsersGroupId -RoleDefinitionName "Storage File Data SMB Share Contributor" -GroupName "AVD Users")
    $success = $success -and (Set-StorageRoleAssignment -StorageAccountId $fslogixStorage.Id -PrincipalId $avdUsersGroupId -RoleDefinitionName "Reader and Data Access" -GroupName "AVD Users")
}

# Configure App Attach storage permissions if group was created
if ($avdAdminsGroupId) {
    $success = $success -and (Set-StorageRoleAssignment -StorageAccountId $appAttachStorage.Id -PrincipalId $avdAdminsGroupId -RoleDefinitionName "Storage File Data SMB Share Contributor" -GroupName "AVD Admins")
    $success = $success -and (Set-StorageRoleAssignment -StorageAccountId $appAttachStorage.Id -PrincipalId $avdAdminsGroupId -RoleDefinitionName "Reader and Data Access" -GroupName "AVD Admins")
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($success) {
    Write-Host "✓ Manual post-provision configuration completed successfully!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Add users to the appropriate Azure AD groups:" -ForegroundColor White
    Write-Host "   - AVD-Admins-$EnvironmentName (for administrators)" -ForegroundColor White
    Write-Host "   - AVD-Users-$EnvironmentName (for regular users)" -ForegroundColor White
    Write-Host "2. Configure session host domain join if needed" -ForegroundColor White
    Write-Host "3. Assign users to the AVD application group in the Azure Portal" -ForegroundColor White
}
else {
    Write-Host "✗ Some configuration steps failed. Please check the errors above." -ForegroundColor Red
    Write-Host "You may need to assign roles manually in the Azure Portal." -ForegroundColor Yellow
}

Write-Host "`nEnvironment Details:" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "FSLogix Storage: $FSLogixStorageAccountName" -ForegroundColor White
Write-Host "App Attach Storage: $AppAttachStorageAccountName" -ForegroundColor White