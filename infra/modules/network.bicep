@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Virtual network address prefix')
param vnetAddressPrefix string

@description('Subnet address prefix for session hosts')
param subnetAddressPrefix string

@description('Subnet address prefix for Azure AD DS')
param aaddsSubnetAddressPrefix string = '10.0.2.0/24'

@description('Resource tags')
param tags object

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-${environmentName}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-avd-sessionhosts'
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'snet-aadds'
        properties: {
          addressPrefix: aaddsSubnetAddressPrefix
        }
      }
    ]
  }
}

// Network Security Group for session hosts
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${environmentName}-avd'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          description: 'Allow RDP traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAVDTraffic'
        properties: {
          description: 'Allow AVD service traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '443'
            '80'
          ]
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'WindowsVirtualDesktop'
          access: 'Allow'
          priority: 1001
          direction: 'Outbound'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output subnetId string = vnet.properties.subnets[0].id
output aaddsSubnetId string = vnet.properties.subnets[1].id
output vnetName string = vnet.name
output subnetName string = vnet.properties.subnets[0].name
output aaddsSubnetName string = vnet.properties.subnets[1].name
