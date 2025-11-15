#!/usr/bin/env pwsh

# Azure AD DS Diagnostic Script
# This script checks the current state of Azure AD DS deployment and provides specific guidance

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZURE_RESOURCE_GROUP_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME
)

Write-Host "=== Azure AD DS Diagnostic Script ===" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentName" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Yellow
Write-Host ""

# Check if logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "❌ Not logged in to Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
}
catch {
    Write-Host "❌ Azure PowerShell module not available. Install with: Install-Module -Name Az" -ForegroundColor Red
    exit 1
}

# Check subscription
if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
    try {
        Set-AzContext -SubscriptionId $SubscriptionId
        Write-Host "✅ Switched to subscription: $SubscriptionId" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to switch to subscription: $SubscriptionId" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n=== Checking Azure AD Permissions ===" -ForegroundColor Cyan

# Check Global Admin role
try {
    $currentUser = Get-AzADUser -UserPrincipalName $context.Account.Id -ErrorAction SilentlyContinue
    if ($currentUser) {
        $globalAdminRole = Get-AzADDirectoryRole | Where-Object { $_.DisplayName -eq "Global Administrator" }
        if ($globalAdminRole) {
            $isGlobalAdmin = Get-AzADDirectoryRoleMember -ObjectId $globalAdminRole.Id | Where-Object { $_.Id -eq $currentUser.Id }
            if ($isGlobalAdmin) {
                Write-Host "✅ User has Global Administrator role" -ForegroundColor Green
            } else {
                Write-Host "❌ User does NOT have Global Administrator role" -ForegroundColor Red
                Write-Host "   This is required for Azure AD DS deployment!" -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠️  Could not verify Global Administrator role" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  Could not find current user in Azure AD" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠️  Could not check Azure AD permissions: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n=== Checking Resource Group ===" -ForegroundColor Cyan

if (-not $ResourceGroupName) {
    Write-Host "❌ Resource Group name not provided or found in environment" -ForegroundColor Red
    Write-Host "   Set AZURE_RESOURCE_GROUP_NAME or provide -ResourceGroupName parameter" -ForegroundColor Yellow
    return
}

try {
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($resourceGroup) {
        Write-Host "✅ Resource Group found: $($resourceGroup.ResourceGroupName)" -ForegroundColor Green
        Write-Host "   Location: $($resourceGroup.Location)" -ForegroundColor Gray
    } else {
        Write-Host "❌ Resource Group not found: $ResourceGroupName" -ForegroundColor Red
        return
    }
}
catch {
    Write-Host "❌ Error checking Resource Group: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "`n=== Checking Azure AD Domain Services ===" -ForegroundColor Cyan

# Find Azure AD DS resource
$aaddsResources = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.AAD/DomainServices"

if ($aaddsResources.Count -eq 0) {
    Write-Host "❌ No Azure AD Domain Services found in resource group" -ForegroundColor Red
    Write-Host "   The deployment may not have started or failed early" -ForegroundColor Yellow
    
    # Check deployment history
    Write-Host "`n=== Checking Deployment History ===" -ForegroundColor Cyan
    $deployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Sort-Object Timestamp -Descending | Select-Object -First 5
    
    foreach ($deployment in $deployments) {
        $status = if ($deployment.ProvisioningState -eq "Succeeded") { "✅" } 
                 elseif ($deployment.ProvisioningState -eq "Failed") { "❌" }
                 else { "⚠️" }
        
        Write-Host "$status $($deployment.DeploymentName): $($deployment.ProvisioningState) at $($deployment.Timestamp)" -ForegroundColor $(if ($deployment.ProvisioningState -eq "Succeeded") { "Green" } elseif ($deployment.ProvisioningState -eq "Failed") { "Red" } else { "Yellow" })
    }
    
    return
}

foreach ($aadds in $aaddsResources) {
    Write-Host "📋 Azure AD DS Found: $($aadds.Name)" -ForegroundColor Blue
    
    # Get detailed properties
    try {
        $aaddsDetails = Get-AzResource -ResourceId $aadds.ResourceId -ExpandProperties
        $status = $aaddsDetails.Properties.domainServiceStatus
        
        Write-Host "   Status: $status" -ForegroundColor $(
            if ($status -eq "Running") { "Green" }
            elseif ($status -eq "Failed") { "Red" }
            elseif ($status -in @("Deploying", "Updating")) { "Yellow" }
            else { "Gray" }
        )
        
        if ($aaddsDetails.Properties.healthMonitors) {
            $healthyCount = ($aaddsDetails.Properties.healthMonitors | Where-Object { $_.health -eq "Healthy" }).Count
            $totalCount = $aaddsDetails.Properties.healthMonitors.Count
            Write-Host "   Health Monitors: $healthyCount/$totalCount healthy" -ForegroundColor $(if ($healthyCount -eq $totalCount) { "Green" } else { "Yellow" })
            
            # Show unhealthy monitors
            $unhealthyMonitors = $aaddsDetails.Properties.healthMonitors | Where-Object { $_.health -ne "Healthy" }
            foreach ($monitor in $unhealthyMonitors) {
                Write-Host "     ❌ $($monitor.name): $($monitor.health)" -ForegroundColor Red
                if ($monitor.details) {
                    Write-Host "        Details: $($monitor.details)" -ForegroundColor Gray
                }
            }
        }
        
        if ($status -eq "Failed") {
            Write-Host "   ❌ AZURE AD DS IS IN FAILED STATE" -ForegroundColor Red
            Write-Host "   📞 Contact Microsoft Support with:" -ForegroundColor Yellow
            Write-Host "      - Tenant ID: $($context.Tenant.Id)" -ForegroundColor White
            Write-Host "      - Domain Name: $($aadds.Name)" -ForegroundColor White
            Write-Host "      - Subscription ID: $($context.Subscription.Id)" -ForegroundColor White
            Write-Host "      - Resource Group: $ResourceGroupName" -ForegroundColor White
            
            Write-Host "`n   💡 Potential Solutions:" -ForegroundColor Cyan
            Write-Host "      1. Delete the failed Azure AD DS and redeploy" -ForegroundColor White
            Write-Host "      2. Try a different domain name" -ForegroundColor White
            Write-Host "      3. Check networking configuration" -ForegroundColor White
            Write-Host "      4. Verify tenant supports Azure AD DS" -ForegroundColor White
        }
        elseif ($status -eq "Deploying") {
            Write-Host "   ⏳ Azure AD DS is still deploying (normal: 60-90 minutes)" -ForegroundColor Yellow
            
            # Check how long it's been deploying
            $deployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Where-Object { $_.DeploymentName -like "*aad*" -or $_.DeploymentName -like "*domain*" } | Sort-Object Timestamp -Descending
            if ($deployments) {
                $latestDeployment = $deployments[0]
                $deployTime = (Get-Date) - $latestDeployment.Timestamp
                Write-Host "   ⏱️  Deploy time: $([math]::Round($deployTime.TotalMinutes, 1)) minutes" -ForegroundColor Gray
                
                if ($deployTime.TotalMinutes -gt 120) {
                    Write-Host "   ⚠️  Deployment time is longer than expected" -ForegroundColor Yellow
                    Write-Host "      Consider checking Azure portal for more details" -ForegroundColor Gray
                }
            }
        }
        elseif ($status -eq "Running") {
            Write-Host "   ✅ Azure AD DS is running normally" -ForegroundColor Green
            
            # Check for domain admin user
            Write-Host "`n=== Checking Domain Admin User ===" -ForegroundColor Cyan
            
            # Try to find tenant default domain
            try {
                $tenantInfo = Get-AzTenant -TenantId $context.Tenant.Id
                $defaultDomain = "Unknown"
                
                # Try to get default domain (this might not work in all scenarios)
                try {
                    $domains = Get-AzADDomain
                    $defaultDomainObj = $domains | Where-Object { $_.IsDefault -eq $true }
                    if ($defaultDomainObj) {
                        $defaultDomain = $defaultDomainObj.Id
                    }
                } catch {
                    $defaultDomain = "$($context.Tenant.Id).onmicrosoft.com"
                }
                
                $domainAdminUPN = "addomainadmin@$defaultDomain"
                
                Write-Host "   Looking for domain admin: $domainAdminUPN" -ForegroundColor Gray
                
                $domainAdminUser = Get-AzADUser -UserPrincipalName $domainAdminUPN -ErrorAction SilentlyContinue
                if ($domainAdminUser) {
                    Write-Host "   ✅ Domain admin user found" -ForegroundColor Green
                    Write-Host "      User ID: $($domainAdminUser.Id)" -ForegroundColor Gray
                } else {
                    Write-Host "   ❌ Domain admin user not found" -ForegroundColor Red
                    Write-Host "      Run post-provision script to create user" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "   ⚠️  Could not check domain admin user: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
    }
    catch {
        Write-Host "   ❌ Error getting Azure AD DS details: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Network Configuration Check ===" -ForegroundColor Cyan

# Check VNet and subnets
try {
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName
    foreach ($vnet in $vnets) {
        Write-Host "📡 Virtual Network: $($vnet.Name)" -ForegroundColor Blue
        Write-Host "   Address Space: $($vnet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor Gray
        
        $aaddsSubnet = $vnet.Subnets | Where-Object { $_.Name -like "*aadds*" }
        if ($aaddsSubnet) {
            Write-Host "   ✅ Azure AD DS subnet found: $($aaddsSubnet.Name)" -ForegroundColor Green
            Write-Host "      Address Prefix: $($aaddsSubnet.AddressPrefix)" -ForegroundColor Gray
            
            if ($aaddsSubnet.Delegations -and $aaddsSubnet.Delegations.Count -gt 0) {
                Write-Host "      Delegations: $($aaddsSubnet.Delegations.ServiceName -join ', ')" -ForegroundColor Gray
            } else {
                Write-Host "      ⚠️  No subnet delegations found" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   ❌ Azure AD DS subnet not found" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "❌ Error checking network configuration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Summary and Recommendations ===" -ForegroundColor Cyan

if ($aaddsResources.Count -eq 0) {
    Write-Host "🔄 Recommendation: Re-run 'azd up' to deploy Azure AD DS" -ForegroundColor Yellow
}
elseif ($aaddsResources[0] -and (Get-AzResource -ResourceId $aaddsResources[0].ResourceId -ExpandProperties).Properties.domainServiceStatus -eq "Failed") {
    Write-Host "🚨 Action Required: Azure AD DS failed - contact Microsoft Support or try clean redeployment" -ForegroundColor Red
    Write-Host "   See: AZURE_AD_DS_TROUBLESHOOTING.md for detailed steps" -ForegroundColor Gray
}
elseif ($aaddsResources[0] -and (Get-AzResource -ResourceId $aaddsResources[0].ResourceId -ExpandProperties).Properties.domainServiceStatus -eq "Deploying") {
    Write-Host "⏳ Wait for Azure AD DS deployment to complete (can take 60-90 minutes)" -ForegroundColor Yellow
    Write-Host "   Monitor progress in Azure portal" -ForegroundColor Gray
}
else {
    Write-Host "✅ Azure AD DS appears to be working - continue with AVD deployment" -ForegroundColor Green
}

Write-Host "`n=== Useful Commands ===" -ForegroundColor Cyan
Write-Host "# Check deployment status:" -ForegroundColor Gray
Write-Host "azd show" -ForegroundColor White
Write-Host ""
Write-Host "# Redeploy if needed:" -ForegroundColor Gray
Write-Host "azd up" -ForegroundColor White
Write-Host ""
Write-Host "# Clean up and restart:" -ForegroundColor Gray
Write-Host "azd down --force --purge" -ForegroundColor White
Write-Host "azd up" -ForegroundColor White