@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Resource tags')
param tags object

// Generate unique storage account name (max 24 chars)
var storageAccountName = 'st${take(toLower(replace(environmentName, '-', '')), 8)}${take(uniqueString(resourceGroup().id), 10)}fs'

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

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output fileShareName string = fileShare.name
output fileShareUrl string = 'https://${storageAccount.name}.file.${environment().suffixes.storage}/${fileShare.name}'
