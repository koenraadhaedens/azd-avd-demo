@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Resource tags')
param tags object

@description('Host Pool token expiration time (default 2 hours from now)')
param tokenExpirationTime string = dateTimeAdd(utcNow(), 'PT2H')

// Create AVD Host Pool
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: 'hp-${environmentName}'
  location: location
  tags: tags
  properties: {
    friendlyName: 'AVD Host Pool - ${environmentName}'
    description: 'Demo AVD Host Pool for ${environmentName} environment'
    hostPoolType: 'Pooled'
    maxSessionLimit: 5
    loadBalancerType: 'DepthFirst'
    validationEnvironment: false
    preferredAppGroupType: 'Desktop'
    registrationInfo: {
      expirationTime: tokenExpirationTime
      registrationTokenOperation: 'Update'
    }
  }
}

// Create AVD Workspace
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: 'ws-${environmentName}'
  location: location
  tags: tags
  properties: {
    friendlyName: 'AVD Workspace - ${environmentName}'
    description: 'Demo AVD Workspace for ${environmentName} environment'
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
}

// Create Desktop Application Group
resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2023-09-05' = {
  name: 'ag-${environmentName}'
  location: location
  tags: tags
  properties: {
    friendlyName: 'Desktop Application Group - ${environmentName}'
    description: 'Desktop Application Group for ${environmentName} environment'
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
  }
}

output hostPoolId string = hostPool.id
output hostPoolName string = hostPool.name
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output applicationGroupId string = applicationGroup.id
output applicationGroupName string = applicationGroup.name
@secure()
output hostPoolToken string = hostPool.listRegistrationTokens().value[0].token
