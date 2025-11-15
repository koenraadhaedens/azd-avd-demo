@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Domain name for Azure AD Domain Services')
param domainName string = 'contoso.local'

@description('Resource tags')
param tags object

@description('Subnet ID for Azure AD DS')
param subnetId string

// Create Azure AD Domain Services
resource domainServices 'Microsoft.AAD/DomainServices@2022-12-01' = {
  name: domainName
  location: location
  tags: tags
  properties: {
    domainName: domainName
    replicaSets: [
      {
        subnetId: subnetId
        location: location
      }
    ]
    domainSecuritySettings: {
      ntlmV1: 'Disabled'
      tlsV1: 'Disabled'
      kerberosRc4Encryption: 'Disabled'
      kerberosArmoring: 'Disabled'
      syncNtlmPasswords: 'Enabled'
      syncKerberosPasswords: 'Enabled'
      syncOnPremPasswords: 'Enabled'
    }
    domainConfigurationType: 'FullySynced'
    filteredSync: 'Disabled'
    notificationSettings: {
      notifyGlobalAdmins: 'Enabled'
      notifyDcAdmins: 'Enabled'
      additionalRecipients: []
    }
    ldapsSettings: {
      ldaps: 'Disabled'
      pfxCertificate: ''
      pfxCertificatePassword: ''
    }
  }
}

// Create Network Security Group for Azure AD DS
resource aaddsNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-aadds-${environmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSyncWithAzureAD'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 101
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowPSRemoting'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 301
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5986'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 201
          protocol: 'Tcp'
          sourceAddressPrefix: 'CorpNetSaw'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowPasswordResetAccountUnlock'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 401
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '636'
        }
      }
    ]
  }
}

// Output the domain services information
output domainName string = domainServices.properties.domainName
output domainGuid string = domainServices.properties.tenantId
output deploymentId string = domainServices.properties.deploymentId
output domainServicesId string = domainServices.id
output nsgId string = aaddsNsg.id
