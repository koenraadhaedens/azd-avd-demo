# Azure AD Domain Services Troubleshooting Guide

## Overview

This guide provides troubleshooting steps for Azure AD Domain Services (Azure AD DS) deployment failures and common issues encountered during the AVD demo environment deployment.

## Common Azure AD DS Failure Scenarios

### 1. "Managed domain is in a failed state" Error

This error typically occurs due to one of the following reasons:

#### **Cause: Insufficient Permissions**
- **Issue**: The deployment identity lacks sufficient Azure AD permissions
- **Solution**: Ensure the deployment user has **Global Administrator** role in Azure AD
- **Check**: Azure portal → Azure Active Directory → Roles and administrators → Global Administrator

#### **Cause: Networking Configuration Issues**
- **Issue**: Subnet configuration or NSG rules prevent Azure AD DS communication
- **Solution**: Verify subnet delegation and NSG rules are correctly configured

#### **Cause: Tenant Limitations**
- **Issue**: Azure AD tenant doesn't support Azure AD DS or has conflicting configurations
- **Solution**: Check tenant requirements and existing domain services

#### **Cause: Resource Quotas**
- **Issue**: Insufficient compute or network quotas in the target region
- **Solution**: Check and request quota increases if needed

### 2. Domain Creation Timeout

If Azure AD DS deployment takes longer than expected (>90 minutes), it may indicate:

#### **Symptom**: Deployment hangs during Azure AD DS creation
- **Check**: Azure portal → Resource groups → Your RG → Azure AD Domain Services status
- **Normal**: "Deploying" status for 60-90 minutes
- **Issue**: "Failed" or "Needs attention" status

## Diagnostic Steps

### Step 1: Check Azure AD DS Status

```powershell
# Get Azure AD DS resource
$resourceGroupName = "rg-your-environment-name"
$domainServiceName = "contoso.local"

$aadds = Get-AzResource -ResourceGroupName $resourceGroupName -Name $domainServiceName -ResourceType "Microsoft.AAD/DomainServices"
$aadds.Properties
```

### Step 2: Check Azure AD Tenant Requirements

```powershell
# Check current user permissions
$context = Get-AzContext
Write-Output "Current user: $($context.Account.Id)"

# Check if user is Global Admin
$user = Get-AzADUser -UserPrincipalName $context.Account.Id
$globalAdminRole = Get-AzADDirectoryRole | Where-Object { $_.DisplayName -eq "Global Administrator" }
$isGlobalAdmin = Get-AzADDirectoryRoleMember -ObjectId $globalAdminRole.Id | Where-Object { $_.Id -eq $user.Id }

if ($isGlobalAdmin) {
    Write-Output "✓ User has Global Administrator role"
} else {
    Write-Output "✗ User does NOT have Global Administrator role - this is required for Azure AD DS"
}
```

### Step 3: Verify Network Configuration

```powershell
# Check subnet delegation
$vnetName = "vnet-your-environment-name"
$subnetName = "subnet-aadds"

$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork (Get-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name $vnetName) -Name $subnetName

Write-Output "Subnet Address Prefix: $($subnet.AddressPrefix)"
Write-Output "Delegations: $($subnet.Delegations | ForEach-Object { $_.ServiceName })"
```

## Resolution Strategies

### Strategy 1: Clean Deployment

If Azure AD DS is in a failed state, you may need to clean up and redeploy:

```powershell
# Remove failed Azure AD DS instance
Remove-AzResource -ResourceGroupName $resourceGroupName -Name $domainServiceName -ResourceType "Microsoft.AAD/DomainServices" -Force

# Wait for cleanup to complete (5-10 minutes)
Start-Sleep 600

# Redeploy using azd
azd up
```

### Strategy 2: Manual Azure AD DS Configuration

If automated deployment continues to fail, create Azure AD DS manually:

1. **Azure Portal Method**:
   - Go to Azure portal → Create a resource → Azure AD Domain Services
   - Use the same configuration as in the Bicep template
   - Wait for deployment to complete
   - Resume with `azd up` (it will detect existing resources)

2. **Required Configuration**:
   - Domain name: `contoso.local` (or your configured domain)
   - Virtual network: Use the vnet created by the deployment
   - Subnet: Use the dedicated Azure AD DS subnet
   - Administration: Add your user account to the "AAD DC Administrators" group

### Strategy 3: Alternative Domain Name

Sometimes the domain name conflicts with existing configurations:

```bash
# Try a different domain name
azd env set AADDS_DOMAIN_NAME "avddemo.local"
azd up
```

## Prevention Best Practices

### 1. Pre-Deployment Checks

Before running `azd up`, verify:

```powershell
# Check Azure AD permissions
$context = Get-AzContext
$user = Get-AzADUser -UserPrincipalName $context.Account.Id
$roles = Get-AzADDirectoryRoleMember | Where-Object { $_.Id -eq $user.Id }
Write-Output "User roles: $($roles | ForEach-Object { (Get-AzADDirectoryRole -ObjectId $_.DirectoryRoleId).DisplayName })"

# Check subscription quotas
Get-AzVMUsage -Location "East US 2" | Where-Object { $_.Name.Value -in @("Standard_D2s_v3", "cores") }

# Check existing Azure AD DS instances in tenant
Get-AzResource -ResourceType "Microsoft.AAD/DomainServices"
```

### 2. Staged Deployment

For production environments, consider deploying in stages:

1. Deploy networking infrastructure first
2. Create Azure AD DS manually and verify it's working
3. Deploy the remaining AVD infrastructure

### 3. Monitoring and Alerts

Set up monitoring for Azure AD DS:

```powershell
# Create alert rule for Azure AD DS health
$resourceId = "/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.AAD/DomainServices/{domain-name}"

# Monitor for "DomainServicesStatus" metric
# Alert when status is not "Running"
```

## Support and Escalation

### When to Contact Microsoft Support

Contact Microsoft Support if:
- Azure AD DS deployment fails repeatedly with different domain names
- The tenant appears to have Azure AD DS restrictions
- Network configuration is correct but deployment still fails
- You receive specific error codes that aren't covered in this guide

### Information to Provide to Support

When contacting support, provide:

1. **Microsoft Entra Tenant ID**: 
   ```powershell
   (Get-AzContext).Tenant.Id
   ```

2. **Domain Name**: The domain name that failed (e.g., "contoso.local")

3. **Error Messages**: Exact error text from Azure portal or deployment logs

4. **Deployment Logs**: 
   ```bash
   azd show --output table
   ```

5. **Resource Group Name**: Where the deployment was attempted

6. **Subscription ID**: 
   ```powershell
   (Get-AzContext).Subscription.Id
   ```

### Alternative Approaches

If Azure AD DS continues to fail, consider these alternatives:

1. **Use existing on-premises AD with Azure AD Connect**
2. **Deploy a Windows Server Domain Controller in Azure** (requires more management)
3. **Use Azure AD join instead of domain join** (limited functionality for AVD)

## Recovery Steps

### Complete Environment Reset

If you need to start completely over:

```bash
# Clean up the environment
azd down --force --purge

# Remove any orphaned Azure AD DS resources
# (Check Azure portal manually)

# Reinitialize
azd init
azd up
```

### Partial Recovery

If only Azure AD DS failed but other resources are working:

```bash
# Target specific resources for redeployment
azd deploy --template-file ./infra/modules/aad-domain-services.bicep
```

Remember: Azure AD DS deployment is the most time-sensitive part of the process, often taking 60-90 minutes even when successful.