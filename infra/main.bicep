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

@description('Domain admin username (will be created in Azure AD and synced to Azure AD DS)')
param domainAdminUsername string = 'addomainadmin'

@description('Admin username for session hosts')
param adminUsername string = 'addomainadmin'

@description('Tenant domain for creating user UPN (e.g., contoso.onmicrosoft.com)')
param tenantDomain string

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

// Create User Assigned Managed Identity for deployment scripts
module managedIdentity './modules/managed-identity.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// Create domain admin user in Azure AD before deploying Azure AD DS
module createDomainAdmin './modules/create-domain-admin.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    domainAdminUsername: domainAdminUsername
    domainAdminPassword: domainAdminPassword
    tenantDomain: tenantDomain
    managedIdentityId: managedIdentity.outputs.identityId
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
  dependsOn: [
    createDomainAdmin
  ]
}

// Wait for Azure AD DS to be fully operational and user sync to complete before proceeding
module waitForUserSync './modules/wait-for-user-sync.bicep' = {
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    domainName: domainName
    domainAdminUPN: createDomainAdmin.outputs.domainAdminUPN
    aaddsResourceId: aadds.outputs.domainServicesId
    managedIdentityId: managedIdentity.outputs.identityId
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
    domainAdminUsername: createDomainAdmin.outputs.domainAdminUPN
    domainAdminPassword: domainAdminPassword
    subnetId: network.outputs.subnetId
    hostPoolToken: avdCore.outputs.hostPoolToken
    sessionHostCount: sessionHostCount
    fslogixStorageAccountName: fslogixStorage.outputs.storageAccountName
    fslogixFileShareName: fslogixStorage.outputs.fileShareName
    tags: tags
  }
  dependsOn: [
    waitForUserSync
  ]
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
output aaddsReadyStatus string = waitForUserSync.outputs.status
output aaddsReadyTime string = waitForUserSync.outputs.readyTime
output userSyncComplete string = waitForUserSync.outputs.userSyncComplete
output domainAdminUserUPN string = createDomainAdmin.outputs.domainAdminUPN
output domainAdminUserId string = createDomainAdmin.outputs.userId
output domainAdminCreationStatus string = createDomainAdmin.outputs.status
output managedIdentityId string = managedIdentity.outputs.identityId
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

// Additional outputs for azd environment variables
output AZURE_FSLOGIX_STORAGE_ACCOUNT_NAME string = fslogixStorage.outputs.storageAccountName
output AZURE_APP_ATTACH_STORAGE_ACCOUNT_NAME string = appAttachStorage.outputs.storageAccountName
output AZURE_DOMAIN_NAME string = aadds.outputs.domainName

