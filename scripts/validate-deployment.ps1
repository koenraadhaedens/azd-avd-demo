# Post-Deployment Validation Script
# This script validates that the manual ADDS integration is working correctly

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName
)

Write-Host "=== AVD Manual ADDS Deployment Validation ===" -ForegroundColor Cyan
Write-Host ""

# Check if Azure PowerShell module is available
try {
    Import-Module Az.Network -ErrorAction Stop
    Import-Module Az.Compute -ErrorAction Stop
} catch {
    Write-Host "Azure PowerShell modules not found. Please install:" -ForegroundColor Red
    Write-Host "  Install-Module -Name Az -Force" -ForegroundColor White
    exit 1
}

# Check if logged in to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host "Not logged in to Azure. Please run: Connect-AzAccount" -ForegroundColor Red
    exit 1
}

# Get deployment outputs if using azd
if ($EnvironmentName -and !$ResourceGroupName) {
    try {
        $outputs = azd env get-values --environment $EnvironmentName --output json | ConvertFrom-Json -ErrorAction Stop
        $outputsHash = @{}
        $outputs.PSObject.Properties | ForEach-Object { $outputsHash[$_.Name] = $_.Value }
        
        if ($outputsHash.ContainsKey('resourceGroupName')) {
            $ResourceGroupName = $outputsHash['resourceGroupName']
        }
    } catch {
        Write-Host "Could not retrieve azd environment outputs" -ForegroundColor Yellow
    }
}

if (-not $ResourceGroupName) {
    $ResourceGroupName = Read-Host "Enter the AVD resource group name"
}

Write-Host "Validating deployment in resource group: $ResourceGroupName" -ForegroundColor Green
Write-Host ""

# Test 1: Check VNet and DNS configuration
Write-Host "1. Checking VNet DNS Configuration..." -ForegroundColor Yellow
try {
    $vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    $avdVnet = $vnets | Where-Object {$_.Name -like "*avd*" -or $_.Name -like "*$EnvironmentName*"} | Select-Object -First 1
    
    if ($avdVnet) {
        Write-Host "   ✓ Found AVD VNet: $($avdVnet.Name)" -ForegroundColor Green
        
        if ($avdVnet.DhcpOptions -and $avdVnet.DhcpOptions.DnsServers) {
            Write-Host "   ✓ Custom DNS servers configured: $($avdVnet.DhcpOptions.DnsServers -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "   ⚠ No custom DNS servers found - using Azure default" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ✗ AVD VNet not found" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Error checking VNet configuration: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Check VNet peering
Write-Host ""
Write-Host "2. Checking VNet Peering..." -ForegroundColor Yellow
if ($avdVnet) {
    try {
        $peerings = Get-AzVirtualNetworkPeering -VirtualNetworkName $avdVnet.Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        if ($peerings.Count -gt 0) {
            foreach ($peering in $peerings) {
                if ($peering.PeeringState -eq 'Connected') {
                    Write-Host "   ✓ Peering '$($peering.Name)' is Connected to $($peering.RemoteVirtualNetwork.Id.Split('/')[-1])" -ForegroundColor Green
                } else {
                    Write-Host "   ⚠ Peering '$($peering.Name)' state: $($peering.PeeringState)" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "   ⚠ No VNet peerings found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ✗ Error checking VNet peering: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 3: Check session host VMs
Write-Host ""
Write-Host "3. Checking Session Host VMs..." -ForegroundColor Yellow
try {
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop | Where-Object {$_.Name -like "*vm-*"}
    
    if ($vms.Count -gt 0) {
        Write-Host "   ✓ Found $($vms.Count) session host VM(s)" -ForegroundColor Green
        
        foreach ($vm in $vms) {
            $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Status -ErrorAction SilentlyContinue
            if ($vmStatus) {
                $powerState = ($vmStatus.Statuses | Where-Object {$_.Code -like "PowerState/*"}).DisplayStatus
                if ($powerState -eq "VM running") {
                    Write-Host "   ✓ VM '$($vm.Name)' is running" -ForegroundColor Green
                } else {
                    Write-Host "   ⚠ VM '$($vm.Name)' state: $powerState" -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "   ⚠ No session host VMs found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ✗ Error checking session host VMs: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Check domain join extensions
Write-Host ""
Write-Host "4. Checking Domain Join Extensions..." -ForegroundColor Yellow
foreach ($vm in $vms) {
    try {
        $extensions = Get-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $vm.Name -ErrorAction Stop
        $domainJoinExt = $extensions | Where-Object {$_.ExtensionType -eq 'JsonADDomainExtension'}
        
        if ($domainJoinExt) {
            if ($domainJoinExt.ProvisioningState -eq 'Succeeded') {
                Write-Host "   ✓ VM '$($vm.Name)' domain join extension succeeded" -ForegroundColor Green
            } else {
                Write-Host "   ⚠ VM '$($vm.Name)' domain join state: $($domainJoinExt.ProvisioningState)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   ⚠ VM '$($vm.Name)' has no domain join extension" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ✗ Error checking extensions for VM '$($vm.Name)': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 5: Check storage accounts
Write-Host ""
Write-Host "5. Checking Storage Accounts..." -ForegroundColor Yellow
try {
    $storageAccounts = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    
    $fslogixStorage = $storageAccounts | Where-Object {$_.StorageAccountName -like "*fslogix*"}
    $appAttachStorage = $storageAccounts | Where-Object {$_.StorageAccountName -like "*appattach*"}
    
    if ($fslogixStorage) {
        Write-Host "   ✓ FSLogix storage account found: $($fslogixStorage.StorageAccountName)" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ FSLogix storage account not found" -ForegroundColor Yellow
    }
    
    if ($appAttachStorage) {
        Write-Host "   ✓ App Attach storage account found: $($appAttachStorage.StorageAccountName)" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ App Attach storage account not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ✗ Error checking storage accounts: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan
Write-Host ""

if ($avdVnet -and $avdVnet.DhcpOptions -and $peerings -and $vms.Count -gt 0) {
    Write-Host "✓ Core infrastructure validation passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "• Add users to the AVD application group" -ForegroundColor White
    Write-Host "• Configure FSLogix permissions for domain users" -ForegroundColor White
    Write-Host "• Test AVD connectivity from client devices" -ForegroundColor White
} else {
    Write-Host "⚠ Some validation checks did not pass completely" -ForegroundColor Yellow
    Write-Host "Please review the output above and address any issues" -ForegroundColor White
}

Write-Host ""
Write-Host "For detailed troubleshooting, see the MANUAL_DEPLOYMENT_GUIDE.md" -ForegroundColor Cyan