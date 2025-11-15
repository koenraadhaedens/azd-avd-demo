targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@secure()
@description('Password for the Windows VM')
param winVMPassword string

@secure()
@description('Password for the Azure AD DS domain admin account')
param domainAdminPassword string

@description('Domain name for Azure AD Domain Services')
param domainName string = 'contoso.local'

@description('Admin username for session hosts')
param adminUsername string = 'avdadmin'

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix for session hosts')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('Number of session hosts to deploy')
param sessionHostCount int = 2

var tags = {
  'azd-env-name': environmentName
  CostControl: 'Ignore'
  SecurityControl: 'Ignore'
  WorkloadType: 'AVD-Demo'
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// Deploy networking infrastructure
module network './modules/network.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    subnetAddressPrefix: subnetAddressPrefix
    tags: tags
  }
}

// Deploy Azure AD Domain Services
module aadds './modules/aad-domain-services.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    domainName: domainName
    subnetId: network.outputs.aaddsSubnetId
    tags: tags
  }
}

// Deploy FSLogix storage account
module fslogixStorage './modules/storage-fslogix.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// Deploy App Attach storage account
module appAttachStorage './modules/storage-appattach.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// Deploy AVD Host Pool, Workspace, and Application Group
module avdCore './modules/avd-core.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// Deploy session hosts
module sessionHosts './modules/session-hosts.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    adminUsername: adminUsername
    adminPassword: winVMPassword
    domainName: domainName
    domainAdminPassword: domainAdminPassword
    subnetId: network.outputs.subnetId
    hostPoolToken: avdCore.outputs.hostPoolToken
    sessionHostCount: sessionHostCount
    fslogixStorageAccountName: fslogixStorage.outputs.storageAccountName
    fslogixFileShareName: fslogixStorage.outputs.fileShareName
    tags: tags
  }
}

// Output important information for post-deployment configuration
output resourceGroupName string = rg.name
output hostPoolName string = avdCore.outputs.hostPoolName
output workspaceName string = avdCore.outputs.workspaceName
output applicationGroupName string = avdCore.outputs.applicationGroupName
output fslogixStorageAccountName string = fslogixStorage.outputs.storageAccountName
output fslogixFileShareName string = fslogixStorage.outputs.fileShareName
output appAttachStorageAccountName string = appAttachStorage.outputs.storageAccountName
output appAttachFileShareName string = appAttachStorage.outputs.fileShareName
output sessionHostNames array = sessionHosts.outputs.sessionHostNames
output domainName string = aadds.outputs.domainName
output aaddsDomainGuid string = aadds.outputs.domainGuid

// Additional outputs for azd environment variables
output AZURE_FSLOGIX_STORAGE_ACCOUNT_NAME string = fslogixStorage.outputs.storageAccountName
output AZURE_APP_ATTACH_STORAGE_ACCOUNT_NAME string = appAttachStorage.outputs.storageAccountName
output AZURE_DOMAIN_NAME string = aadds.outputs.domainName

