@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Admin username for session hosts')
param adminUsername string

@secure()
@description('Admin password for session hosts')
param adminPassword string

@description('Domain name for Azure AD DS')
param domainName string

@description('Subnet ID for session hosts')
param subnetId string

@secure()
@description('Host pool registration token')
param hostPoolToken string

@description('Number of session hosts to deploy')
param sessionHostCount int = 2

@description('FSLogix storage account name')
param fslogixStorageAccountName string

@description('FSLogix file share name')
param fslogixFileShareName string

@description('Azure AD DS domain admin username (e.g., addomainadmin)')
param domainAdminUsername string

@secure()
@description('Azure AD DS domain admin password')
param domainAdminPassword string

@description('Resource tags')
param tags object

// Deploy session hosts
resource sessionHosts 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, sessionHostCount): {
  name: 'vm-${environmentName}-${padLeft(i + 1, 2, '0')}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4s_v3'
    }
    osProfile: {
      computerName: 'vm-${environmentName}-${padLeft(i + 1, 2, '0')}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-22h2-avd'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaces[i].id
        }
      ]
    }
  }
  dependsOn: [
    networkInterfaces
  ]
}]

// Network interfaces for session hosts
resource networkInterfaces 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, sessionHostCount): {
  name: 'nic-${environmentName}-${padLeft(i + 1, 2, '0')}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}]

// Domain join extension with retry logic
resource domainJoin 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, sessionHostCount): {
  name: 'DomainJoin'
  parent: sessionHosts[i]
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      Name: domainName
      OUPath: ''
      User: '${domainAdminUsername}@${domainName}'
      Restart: 'true'
      Options: '3'
      NumberOfRetries: '4'
      RetryIntervalInMinutes: '5'
    }
    protectedSettings: {
      Password: domainAdminPassword
    }
  }
}]

// Install AVD agents and configure FSLogix
resource avdAgentInstall 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, sessionHostCount): {
  name: 'AVDAgentInstall'
  parent: sessionHosts[i]
  location: location
  dependsOn: [
    domainJoin[i]
  ]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/koenraadhaedens/azd-avd-demo/main/scripts/sessionhost/ConfigureSessionHost.ps1'
      ]
    }
    protectedSettings: {
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File ConfigureSessionHost.ps1 -HostPoolRegistrationToken "${hostPoolToken}" -StorageAccountName "${fslogixStorageAccountName}" -FileShareName "${fslogixFileShareName}" -DomainName "${domainName}"'
    }
  }
}]

output sessionHostNames array = [for i in range(0, sessionHostCount): sessionHosts[i].name]
output sessionHostIds array = [for i in range(0, sessionHostCount): sessionHosts[i].id]
