# Get VNet Information Script
# This script helps find VNet resource IDs and information

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$VNetName,
    
    [Parameter(Mandatory=$false)]
    [string]$DnsServerIp
)

Write-Host "=== VNet Information Retrieval Tool ===" -ForegroundColor Cyan
Write-Host ""

# Check if Azure PowerShell module is available
try {
    Import-Module Az.Network -ErrorAction Stop
    Import-Module Az.Accounts -ErrorAction Stop
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

Write-Host "Current Azure context: $($context.Account.Id) - $($context.Subscription.Name)" -ForegroundColor Green
Write-Host ""

if ($DnsServerIp) {
    Write-Host "Searching for VNets containing DNS server IP: $DnsServerIp" -ForegroundColor Yellow
    Write-Host ""
    
    # Get all VNets and check their subnets for the DNS server IP
    $allVNets = Get-AzVirtualNetwork
    $foundVNets = @()
    
    foreach ($vnet in $allVNets) {
        foreach ($subnet in $vnet.Subnets) {
            # Check if the DNS server IP is within this subnet's address range
            $subnetPrefix = $subnet.AddressPrefix
            
            # Simple check - you might want to use proper IP address range checking
            $subnetNetwork = $subnetPrefix.Split('/')[0]
            $subnetBase = $subnetNetwork.Split('.')[0..2] -join '.'
            $dnsBase = $DnsServerIp.Split('.')[0..2] -join '.'
            
            if ($dnsBase -eq $subnetBase) {
                $foundVNets += [PSCustomObject]@{
                    VNetName = $vnet.Name
                    ResourceGroup = $vnet.ResourceGroupName
                    Subscription = $context.Subscription.Id
                    AddressSpace = $vnet.AddressSpace.AddressPrefixes -join ', '
                    Location = $vnet.Location
                    ResourceId = $vnet.Id
                    MatchingSubnet = $subnet.Name
                    SubnetPrefix = $subnetPrefix
                }
                break
            }
        }
    }
    
    if ($foundVNets) {
        Write-Host "Found VNets that might contain the DNS server:" -ForegroundColor Green
        foreach ($foundVNet in $foundVNets) {
            Write-Host ""
            Write-Host "  VNet Name: $($foundVNet.VNetName)" -ForegroundColor Cyan
            Write-Host "  Resource Group: $($foundVNet.ResourceGroup)" -ForegroundColor White
            Write-Host "  Subscription: $($foundVNet.Subscription)" -ForegroundColor White
            Write-Host "  Address Space: $($foundVNet.AddressSpace)" -ForegroundColor White
            Write-Host "  Matching Subnet: $($foundVNet.MatchingSubnet) ($($foundVNet.SubnetPrefix))" -ForegroundColor Yellow
            Write-Host "  Resource ID: $($foundVNet.ResourceId)" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Environment Variable:" -ForegroundColor Cyan
            Write-Host "    azd env set DOMAIN_CONTROLLER_VNET_ID `"$($foundVNet.ResourceId)`"" -ForegroundColor White
            Write-Host "  " + "="*80
        }
    } else {
        Write-Host "No VNets found that might contain DNS server $DnsServerIp" -ForegroundColor Yellow
        Write-Host "Note: This search uses a simple subnet matching algorithm." -ForegroundColor Gray
    }
}

if ($SubscriptionId -or $ResourceGroupName -or $VNetName) {
    Write-Host "Searching with specific criteria..." -ForegroundColor Yellow
    Write-Host ""
    
    $searchVNets = @()
    
    if ($VNetName -and $ResourceGroupName) {
        # Specific VNet
        try {
            $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            $searchVNets += $vnet
        } catch {
            Write-Host "VNet '$VNetName' not found in resource group '$ResourceGroupName'" -ForegroundColor Red
        }
    } elseif ($ResourceGroupName) {
        # All VNets in resource group
        try {
            $searchVNets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        } catch {
            Write-Host "Resource group '$ResourceGroupName' not found or no VNets in it" -ForegroundColor Red
        }
    } elseif ($SubscriptionId) {
        # All VNets in subscription
        try {
            Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
            $searchVNets = Get-AzVirtualNetwork -ErrorAction Stop
        } catch {
            Write-Host "Could not access subscription '$SubscriptionId'" -ForegroundColor Red
        }
    }
    
    if ($searchVNets) {
        Write-Host "Found VNets:" -ForegroundColor Green
        foreach ($vnet in $searchVNets) {
            Write-Host ""
            Write-Host "  VNet Name: $($vnet.Name)" -ForegroundColor Cyan
            Write-Host "  Resource Group: $($vnet.ResourceGroupName)" -ForegroundColor White
            Write-Host "  Address Space: $($vnet.AddressSpace.AddressPrefixes -join ', ')" -ForegroundColor White
            Write-Host "  Location: $($vnet.Location)" -ForegroundColor White
            Write-Host "  Subnets:" -ForegroundColor Yellow
            foreach ($subnet in $vnet.Subnets) {
                Write-Host "    - $($subnet.Name): $($subnet.AddressPrefix)" -ForegroundColor Gray
            }
            Write-Host "  Resource ID: $($vnet.Id)" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Environment Variable:" -ForegroundColor Cyan
            Write-Host "    azd env set DOMAIN_CONTROLLER_VNET_ID `"$($vnet.Id)`"" -ForegroundColor White
            Write-Host "  " + "="*80
        }
    }
}

if (-not $DnsServerIp -and -not $SubscriptionId -and -not $ResourceGroupName -and -not $VNetName) {
    Write-Host "No search criteria provided. Here are the available options:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Search by DNS Server IP:" -ForegroundColor Cyan
    Write-Host "  .\scripts\get-vnet-info.ps1 -DnsServerIp `"192.168.1.10`"" -ForegroundColor White
    Write-Host ""
    Write-Host "Search by Resource Group:" -ForegroundColor Cyan
    Write-Host "  .\scripts\get-vnet-info.ps1 -ResourceGroupName `"rg-domain-controllers`"" -ForegroundColor White
    Write-Host ""
    Write-Host "Search by specific VNet:" -ForegroundColor Cyan
    Write-Host "  .\scripts\get-vnet-info.ps1 -ResourceGroupName `"rg-domain-controllers`" -VNetName `"vnet-dc`"" -ForegroundColor White
    Write-Host ""
    Write-Host "Search by Subscription:" -ForegroundColor Cyan
    Write-Host "  .\scripts\get-vnet-info.ps1 -SubscriptionId `"12345678-1234-1234-1234-123456789012`"" -ForegroundColor White
}

Write-Host ""
Write-Host "Note: Copy the Resource ID from above to use as DOMAIN_CONTROLLER_VNET_ID" -ForegroundColor Green