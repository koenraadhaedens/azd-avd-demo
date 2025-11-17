@description('Domain Controller VNet Resource ID')
param domainControllerVnetId string

@description('AVD VNet Resource ID') 
param avdVnetId string

@description('Name for the peering connection')
param peeringName string = 'peer-to-avd-vnet'

// Extract VNet information from the domain controller VNet ID
var dcVnetIdParts = split(domainControllerVnetId, '/')
var dcVnetName = dcVnetIdParts[8]

// Create reverse peering from Domain Controller VNet to AVD VNet
resource vnetPeeringFromDC 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  name: '${dcVnetName}/${peeringName}'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: avdVnetId
    }
  }
}

output peeringName string = vnetPeeringFromDC.name
output peeringState string = vnetPeeringFromDC.properties.peeringState
