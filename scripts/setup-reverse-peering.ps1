# Create Reverse VNet Peering Script
# This script creates the reverse peering from the domain controller VNet to the AVD VNet

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainControllerVnetId,
    
    [Parameter(Mandatory=$true)]
    [string]$AvdVnetId,
    
    [Parameter(Mandatory=$false)]
    [string]$PeeringName = "peer-to-avd-vnet"
)

Write-Host "=== VNet Reverse Peering Setup ===" -ForegroundColor Cyan
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

Write-Host "Current Azure context: $($context.Account.Id)" -ForegroundColor Green
Write-Host ""

# Parse VNet IDs
Write-Host "Parsing VNet information..." -ForegroundColor Yellow

$dcVnetIdParts = $DomainControllerVnetId.Split('/')
$avdVnetIdParts = $AvdVnetId.Split('/')

if ($dcVnetIdParts.Length -ne 9 -or $avdVnetIdParts.Length -ne 9) {
    Write-Host "Invalid VNet resource ID format. Expected format:" -ForegroundColor Red
    Write-Host "/subscriptions/{subscription}/resourceGroups/{resourceGroup}/providers/Microsoft.Network/virtualNetworks/{vnetName}" -ForegroundColor White
    exit 1
}

$dcSubscriptionId = $dcVnetIdParts[2]
$dcResourceGroupName = $dcVnetIdParts[4]
$dcVnetName = $dcVnetIdParts[8]

$avdSubscriptionId = $avdVnetIdParts[2]
$avdResourceGroupName = $avdVnetIdParts[4]
$avdVnetName = $avdVnetIdParts[8]

Write-Host "Domain Controller VNet:" -ForegroundColor Cyan
Write-Host "  Subscription: $dcSubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $dcResourceGroupName" -ForegroundColor White
Write-Host "  VNet Name: $dcVnetName" -ForegroundColor White

Write-Host ""
Write-Host "AVD VNet:" -ForegroundColor Cyan
Write-Host "  Subscription: $avdSubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $avdResourceGroupName" -ForegroundColor White
Write-Host "  VNet Name: $avdVnetName" -ForegroundColor White

Write-Host ""

# Check if we need to switch subscriptions
if ($dcSubscriptionId -ne $context.Subscription.Id) {
    Write-Host "Switching to domain controller subscription: $dcSubscriptionId" -ForegroundColor Yellow
    try {
        Set-AzContext -SubscriptionId $dcSubscriptionId -ErrorAction Stop
        Write-Host "✓ Switched to subscription $dcSubscriptionId" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to switch to subscription $dcSubscriptionId" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Check if peering already exists
Write-Host "Checking for existing peering..." -ForegroundColor Yellow
try {
    $existingPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $dcVnetName -ResourceGroupName $dcResourceGroupName -Name $PeeringName -ErrorAction SilentlyContinue
    if ($existingPeering) {
        Write-Host "⚠ Peering '$PeeringName' already exists in $dcVnetName" -ForegroundColor Yellow
        Write-Host "Current state: $($existingPeering.PeeringState)" -ForegroundColor White
        
        $continue = Read-Host "Do you want to continue and update it? (y/N)"
        if ($continue.ToLower() -ne 'y') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
} catch {
    # Peering doesn't exist, continue
}

# Create the reverse peering
Write-Host "Creating reverse peering: $dcVnetName -> $avdVnetName" -ForegroundColor Yellow
try {
    $peering = Add-AzVirtualNetworkPeering -VirtualNetworkName $dcVnetName -ResourceGroupName $dcResourceGroupName -Name $PeeringName -RemoteVirtualNetworkId $AvdVnetId -AllowVirtualNetworkAccess -AllowForwardedTraffic -ErrorAction Stop
    
    Write-Host "✓ Reverse peering created successfully!" -ForegroundColor Green
    Write-Host "  Peering Name: $($peering.Name)" -ForegroundColor White
    Write-Host "  Peering State: $($peering.PeeringState)" -ForegroundColor White
    Write-Host "  Allow Virtual Network Access: $($peering.AllowVirtualNetworkAccess)" -ForegroundColor White
    Write-Host "  Allow Forwarded Traffic: $($peering.AllowForwardedTraffic)" -ForegroundColor White
    
} catch {
    Write-Host "✗ Failed to create reverse peering" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "• Insufficient permissions on the domain controller VNet" -ForegroundColor White
    Write-Host "• VNet address spaces overlap" -ForegroundColor White
    Write-Host "• Network policies blocking the peering" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "=== Peering Status ===" -ForegroundColor Cyan
Write-Host ""

# Check both peerings
Write-Host "Checking peering status from both sides..." -ForegroundColor Yellow

# Check DC to AVD peering
try {
    $dcToAvdPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $dcVnetName -ResourceGroupName $dcResourceGroupName -Name $PeeringName -ErrorAction Stop
    Write-Host "DC -> AVD Peering:" -ForegroundColor Green
    Write-Host "  State: $($dcToAvdPeering.PeeringState)" -ForegroundColor White
} catch {
    Write-Host "DC -> AVD Peering: Not found or error" -ForegroundColor Red
}

# Check AVD to DC peering (switch to AVD subscription if needed)
if ($avdSubscriptionId -ne $dcSubscriptionId) {
    Set-AzContext -SubscriptionId $avdSubscriptionId | Out-Null
}

try {
    $avdToDcPeering = Get-AzVirtualNetworkPeering -VirtualNetworkName $avdVnetName -ResourceGroupName $avdResourceGroupName -ErrorAction Stop | Where-Object {$_.RemoteVirtualNetwork.Id -eq $DomainControllerVnetId}
    if ($avdToDcPeering) {
        Write-Host "AVD -> DC Peering:" -ForegroundColor Green
        Write-Host "  State: $($avdToDcPeering.PeeringState)" -ForegroundColor White
    } else {
        Write-Host "AVD -> DC Peering: Not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "AVD -> DC Peering: Could not check (may not be deployed yet)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✓ Reverse peering setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Note: Both peerings should show 'Connected' state once the AVD VNet is deployed." -ForegroundColor Cyan