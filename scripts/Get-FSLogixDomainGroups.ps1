#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Gets the object IDs for AAD DC domain groups needed for FSLogix storage authentication.

.DESCRIPTION
    This script retrieves the object IDs for the default AAD DS groups that need access to the FSLogix storage account.
    These IDs are required for setting up SMB role assignments.

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
        "AAD DC Administrators" = @{
            Description = "Administrators group for Azure AD Domain Services"
            Role = "Storage File Data SMB Share Contributor"
        }
        "AAD DC Users" = @{
            Description = "Users group for Azure AD Domain Services"  
            Role = "Storage File Data SMB Share Reader"
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
        Write-Host "No Azure AD DS groups found. Please ensure:" -ForegroundColor Red
        Write-Host "1. Azure AD Domain Services is properly configured" -ForegroundColor Yellow
        Write-Host "2. The default groups have been created" -ForegroundColor Yellow
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
    
    # Generate environment variables for azd
    Write-Host "Environment variables for azd:" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    
    if ($results.ContainsKey("AAD DC Administrators")) {
        Write-Host "STORAGE_CONTRIBUTORS_GROUP_ID=$($results['AAD DC Administrators'].ObjectId)" -ForegroundColor Yellow
    }
    
    if ($results.ContainsKey("AAD DC Users")) {
        Write-Host "STORAGE_USERS_GROUP_ID=$($results['AAD DC Users'].ObjectId)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Add these to your .env file or set them as azd environment variables:" -ForegroundColor Green
    Write-Host "azd env set STORAGE_CONTRIBUTORS_GROUP_ID `"$($results['AAD DC Administrators'].ObjectId)`"" -ForegroundColor Cyan
    Write-Host "azd env set STORAGE_USERS_GROUP_ID `"$($results['AAD DC Users'].ObjectId)`"" -ForegroundColor Cyan
    
}
catch {
    Write-Error "Failed to get domain groups: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}