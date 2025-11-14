@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Domain name for Azure AD DS')
param domainName string

@description('Resource tags')
param tags object

// Generate unique storage account name
var storageAccountName = 'st${toLower(replace(environmentName, '-', ''))}fslogix'

// Storage account for FSLogix profiles
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'FileStorage'
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADDS'
      activeDirectoryProperties: {
        domainName: domainName
        domainSid: ''
        forestName: domainName
        netBiosDomainName: split(domainName, '.')[0]
        domainGuid: ''
        azureStorageSid: ''
        samAccountName: ''
        accountType: ''
      }
    }
  }
}

// File service for the storage account
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        multichannel: {
          enabled: true
        }
        authenticationMethods: 'Kerberos'
        channelEncryption: 'AES-256-GCM'
        kerberosTicketEncryption: 'AES-256'
      }
    }
  }
}

// File share for FSLogix profiles
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: 'profiles'
  properties: {
    shareQuota: 1024
    enabledProtocols: 'SMB'
    accessTier: 'Premium'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output fileShareName string = fileShare.name
output fileShareUrl string = 'https://${storageAccount.name}.file.${environment().suffixes.storage}/${fileShare.name}'
