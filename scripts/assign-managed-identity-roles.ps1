#!/usr/bin/env pwsh

# Script to assign Azure AD roles to the User Assigned Managed Identity
# This script should be run after the infrastructure deployment completes

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZURE_RESOURCE_GROUP_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$ManagedIdentityPrincipalId
)

Write-Host "=== Azure AD Role Assignment for Managed Identity ===" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentName" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Green

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
        Set-AzContext -SubscriptionId $SubscriptionId
        Write-Host "Set subscription context to: $SubscriptionId" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Failed to set subscription context: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Get the managed identity principal ID if not provided
if (-not $ManagedIdentityPrincipalId) {
    try {
        Write-Host "Looking for managed identity in resource group..." -ForegroundColor Yellow
        $identityName = "id-deployment-$EnvironmentName"
        $managedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $identityName -ErrorAction SilentlyContinue
        
        if ($managedIdentity) {
            $ManagedIdentityPrincipalId = $managedIdentity.PrincipalId
            Write-Host "Found managed identity: $identityName" -ForegroundColor Green
            Write-Host "Principal ID: $ManagedIdentityPrincipalId" -ForegroundColor Gray
        }
        else {
            Write-Host "Could not find managed identity: $identityName" -ForegroundColor Red
            Write-Host "Please provide the PrincipalId parameter or ensure the managed identity exists" -ForegroundColor Yellow
            exit 1
        }
    }
    catch {
        Write-Host "Error finding managed identity: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Check for Microsoft Graph PowerShell module
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.DirectoryObjects -ErrorAction Stop
    Write-Host "Microsoft Graph PowerShell modules loaded" -ForegroundColor Green
}
catch {
    Write-Host "Microsoft Graph PowerShell modules not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
        Install-Module Microsoft.Graph.DirectoryObjects -Scope CurrentUser -Force
        Import-Module Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.DirectoryObjects
        Write-Host "Microsoft Graph PowerShell modules installed and loaded" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install Microsoft Graph modules: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please install manually: Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
}

# Connect to Microsoft Graph
try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory" -NoWelcome
    Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Ensure you have Global Administrator permissions" -ForegroundColor Yellow
    exit 1
}

# Function to assign Azure AD role
function Grant-AzureADRole {
    param(
        [string]$RoleName,
        [string]$PrincipalId
    )
    
    try {
        Write-Host "Granting role: $RoleName" -ForegroundColor Yellow
        
        # Get or create the directory role
        $role = Get-MgDirectoryRole -Filter "displayName eq '$RoleName'" -ErrorAction SilentlyContinue
        
        if (-not $role) {
            Write-Host "Role template not activated, activating: $RoleName" -ForegroundColor Yellow
            $roleTemplate = Get-MgDirectoryRoleTemplate -Filter "displayName eq '$RoleName'"
            if ($roleTemplate) {
                $role = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
                Write-Host "Role activated: $RoleName" -ForegroundColor Green
            }
            else {
                Write-Host "Could not find role template: $RoleName" -ForegroundColor Red
                return $false
            }
        }
        
        # Check if already assigned
        $existingMember = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id | Where-Object { $_.Id -eq $PrincipalId }
        
        if ($existingMember) {
            Write-Host "✓ Role already assigned: $RoleName" -ForegroundColor Green
            return $true
        }
        
        # Assign the role
        $bodyParameter = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$PrincipalId"
        }
        
        New-MgDirectoryRoleMember -DirectoryRoleId $role.Id -BodyParameter $bodyParameter
        Write-Host "✓ Role assigned successfully: $RoleName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Failed to assign role $RoleName : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Assign required roles
Write-Host "`nGranting Azure AD roles to managed identity..." -ForegroundColor Cyan

$success = $true

# User Administrator role (to create and manage users)
$success = $success -and (Grant-AzureADRole -RoleName "User Administrator" -PrincipalId $ManagedIdentityPrincipalId)

# Groups Administrator role (to create and manage groups)
$success = $success -and (Grant-AzureADRole -RoleName "Groups Administrator" -PrincipalId $ManagedIdentityPrincipalId)

if ($success) {
    Write-Host "`n✅ All role assignments completed successfully!" -ForegroundColor Green
    Write-Host "`nThe managed identity now has permissions to:" -ForegroundColor Cyan
    Write-Host "  • Create and manage Azure AD users" -ForegroundColor White
    Write-Host "  • Create and manage Azure AD groups" -ForegroundColor White
    Write-Host "`nYou can now run deployment scripts that use this managed identity." -ForegroundColor Green
}
else {
    Write-Host "`n⚠️  Some role assignments failed." -ForegroundColor Yellow
    Write-Host "Please check the errors above and ensure you have Global Administrator permissions." -ForegroundColor Yellow
}

# Disconnect from Microsoft Graph
try {
    Disconnect-MgGraph
    Write-Host "`nDisconnected from Microsoft Graph" -ForegroundColor Gray
}
catch {
    # Silent disconnect failure
}

Write-Host "`nRole assignment process completed." -ForegroundColor Cyan