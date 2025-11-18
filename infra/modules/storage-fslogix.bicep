@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Resource tags')
param tags object

@description('Domain name for Azure AD DS')
param domainName string

@description('Storage Contributors group object ID')
param storageContributorsGroupId string

@description('Storage Users group object ID')
param storageUsersGroupId string

// Generate unique storage account name (max 24 chars)
var storageAccountName = 'st${take(toLower(replace(environmentName, 'fs-', '')), 8)}${take(uniqueString(resourceGroup().id), 10)}fs'

// Storage account for FSLogix profiles
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADDS'
      activeDirectoryProperties: {
        domainName: domainName
        netBiosDomainName: split(domainName, '.')[0]
        forestName: domainName
        domainGuid: ''
        domainSid: ''
        azureStorageSid: ''
      }
    }
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// File service for the storage account
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// File share for FSLogix profiles
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'profiles'
  properties: {
    shareQuota: 1024
    enabledProtocols: 'SMB'
    accessTier: 'Hot'
  }
}

// SMB role assignment for Storage File Data SMB Share Contributors (administrators)
resource smbContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageContributorsGroupId, 'Storage File Data SMB Share Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb') // Storage File Data SMB Share Contributor
    principalId: storageContributorsGroupId
    principalType: 'Group'
  }
}

// SMB role assignment for Storage File Data SMB Share Reader (users)
resource smbReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageUsersGroupId, 'Storage File Data SMB Share Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'aba4ae5f-2193-4029-9191-0cb91df5e314') // Storage File Data SMB Share Reader
    principalId: storageUsersGroupId
    principalType: 'Group'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output fileShareName string = fileShare.name
output storageAccountFqdn string = '${storageAccount.name}.file.${environment().suffixes.storage}'
output fileShareUrl string = 'https://${storageAccount.name}.file.${environment().suffixes.storage}/${fileShare.name}'
