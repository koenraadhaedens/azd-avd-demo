#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Gets the object IDs for AVD groups created during deployment (for reference).

.DESCRIPTION
    This script retrieves the object IDs for the "AVD Admins" and "AVD Users" groups that are 
    automatically created during the deployment. This is primarily for reference and troubleshooting,
    as the deployment handles all the necessary group creation and role assignments automatically.

.PARAMETER DomainName
    The domain name for Azure AD DS (e.g., contoso.com)

.PARAMETER TenantId
    Azure AD tenant ID (optional, will use current context if not provided)

.EXAMPLE
    .\Get-FSLogixDomainGroups.ps1 -DomainName "contoso.com"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId
)

# Import required modules
Import-Module Az.Accounts -Force
Import-Module Az.Resources -Force

try {
    Write-Host "Getting AAD DC group object IDs for FSLogix configuration..." -ForegroundColor Green
    
    # Check if we're logged in to Azure
    $context = Get-AzContext
    if (!$context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Current Azure context:" -ForegroundColor Yellow
    Write-Host "  Tenant: $($context.Tenant.Id)" -ForegroundColor White
    Write-Host "  Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor White
    Write-Host "  Account: $($context.Account.Id)" -ForegroundColor White
    
    # Switch to specific tenant if provided
    if ($TenantId -and $context.Tenant.Id -ne $TenantId) {
        Write-Host "Switching to tenant: $TenantId" -ForegroundColor Yellow
        $context = Set-AzContext -TenantId $TenantId
    }
    
    # Get Microsoft Graph access token
    Write-Host "Getting Microsoft Graph access token..." -ForegroundColor Yellow
    $graphToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "https://graph.microsoft.com/").AccessToken
    
    if (!$graphToken) {
        Write-Error "Failed to get Microsoft Graph access token"
        exit 1
    }
    
    # Define the groups we need
    $requiredGroups = @{
        "AVD Admins" = @{
            Description = "Azure Virtual Desktop Administrators (created by deployment)"
            Role = "Storage File Data SMB Share Elevated Contributor"
        }
        "AVD Users" = @{
            Description = "Azure Virtual Desktop Users (created by deployment)"  
            Role = "Storage File Data SMB Share Contributor"
        }
    }
    
    Write-Host "Searching for Azure AD groups..." -ForegroundColor Yellow
    
    $headers = @{
        'Authorization' = "Bearer $graphToken"
        'Content-Type' = 'application/json'
    }
    
    $results = @{}
    
    foreach ($groupName in $requiredGroups.Keys) {
        Write-Host "Looking for group: $groupName" -ForegroundColor Cyan
        
        try {
            # Search for the group by display name
            $searchUrl = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$groupName'"
            $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method Get
            
            if ($response.value -and $response.value.Count -gt 0) {
                $group = $response.value[0]
                $results[$groupName] = @{
                    ObjectId = $group.id
                    DisplayName = $group.displayName
                    Description = $requiredGroups[$groupName].Description
                    Role = $requiredGroups[$groupName].Role
                }
                
                Write-Host "✓ Found: $($group.displayName)" -ForegroundColor Green
                Write-Host "  Object ID: $($group.id)" -ForegroundColor White
            }
            else {
                Write-Warning "Group '$groupName' not found. This group should be created automatically when Azure AD DS is enabled."
                
                # Try alternative search
                $altSearchUrl = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$groupName')"
                $altResponse = Invoke-RestMethod -Uri $altSearchUrl -Headers $headers -Method Get
                
                if ($altResponse.value -and $altResponse.value.Count -gt 0) {
                    Write-Host "Found similar groups:" -ForegroundColor Yellow
                    foreach ($altGroup in $altResponse.value) {
                        Write-Host "  - $($altGroup.displayName) ($($altGroup.id))" -ForegroundColor White
                    }
                }
            }
        }
        catch {
            Write-Error "Failed to search for group '$groupName': $($_.Exception.Message)"
        }
    }
    
    # Display summary
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "========" -ForegroundColor Cyan
    
    if ($results.Count -eq 0) {
        Write-Host "No AVD groups found. Please ensure:" -ForegroundColor Red
        Write-Host "1. The deployment has completed successfully" -ForegroundColor Yellow
        Write-Host "2. The post-provision script has run and created the AVD groups" -ForegroundColor Yellow
        Write-Host "3. You have permissions to read Azure AD groups" -ForegroundColor Yellow
        exit 1
    }
    
    foreach ($groupName in $results.Keys) {
        $group = $results[$groupName]
        Write-Host "$groupName:" -ForegroundColor Green
        Write-Host "  Object ID: $($group.ObjectId)" -ForegroundColor White
        Write-Host "  Role: $($group.Role)" -ForegroundColor White
        Write-Host ""
    }
    
    # Generate group information for reference
    Write-Host "Group information for reference:" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    
    if ($results.ContainsKey("AVD Admins")) {
        Write-Host "AVD_ADMINS_GROUP_ID=$($results['AVD Admins'].ObjectId)" -ForegroundColor Yellow
    }
    
    if ($results.ContainsKey("AVD Users")) {
        Write-Host "AVD_USERS_GROUP_ID=$($results['AVD Users'].ObjectId)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Note: These groups are automatically used by the deployment." -ForegroundColor Green
    Write-Host "No manual configuration is required for FSLogix to work." -ForegroundColor Green
    
}
catch {
    Write-Error "Failed to get domain groups: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}