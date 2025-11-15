@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Domain name for Azure AD Domain Services')
param domainName string

@description('Azure AD DS resource ID')
param aaddsResourceId string

@description('Resource tags')
param tags object

// Create managed identity for the deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-aadds-wait-${environmentName}'
  location: location
  tags: tags
}

// Role assignment for the managed identity to read Azure AD DS status
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to wait for Azure AD DS to be ready
resource waitForAzureADDS 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'wait-for-aadds-${environmentName}'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    retentionInterval: 'PT1H'
    timeout: 'PT3H' // 3 hour timeout
    cleanupPreference: 'OnSuccess'
    scriptContent: '''
      param(
        [string]$DomainName,
        [string]$AaddsResourceId,
        [string]$SubscriptionId,
        [string]$ResourceGroupName
      )

      Write-Output "Starting Azure AD DS readiness check for domain: $DomainName"
      Write-Output "Azure AD DS Resource ID: $AaddsResourceId"

      # Set context to the subscription
      Set-AzContext -SubscriptionId $SubscriptionId -Force

      # Parse resource group and resource name from resource ID
      $resourceParts = $AaddsResourceId -split '/'
      $resourceGroup = $resourceParts[4]
      $resourceName = $resourceParts[-1]

      Write-Output "Resource Group: $resourceGroup"
      Write-Output "Resource Name: $resourceName"

      $maxWaitTime = 180 # 3 hours in minutes
      $waitInterval = 5 # Check every 5 minutes
      $elapsedTime = 0
      $isReady = $false

      while ($elapsedTime -lt $maxWaitTime -and -not $isReady) {
        try {
          Write-Output "Checking Azure AD DS status... (Elapsed: $elapsedTime minutes)"
          
          # Get the Azure AD DS resource
          $aaddsResource = Get-AzResource -ResourceId $AaddsResourceId -ErrorAction SilentlyContinue
          
          if ($aaddsResource) {
            Write-Output "Azure AD DS resource found. Current provisioning state: $($aaddsResource.Properties.provisioningState)"
            
            # Check if the resource is in Running state
            if ($aaddsResource.Properties.provisioningState -eq "Succeeded") {
              Write-Output "Azure AD DS provisioning completed successfully!"
              
              # Additional check - verify domain controllers are accessible
              try {
                $domainControllers = $aaddsResource.Properties.replicaSets[0].domainControllerIpAddress
                if ($domainControllers -and $domainControllers.Count -gt 0) {
                  Write-Output "Domain controllers are available: $($domainControllers -join ', ')"
                  
                  # Test DNS resolution for the domain
                  try {
                    $dnsResult = Resolve-DnsName -Name $DomainName -Type A -ErrorAction SilentlyContinue
                    if ($dnsResult) {
                      Write-Output "DNS resolution successful for domain: $DomainName"
                      $isReady = $true
                      break
                    } else {
                      Write-Output "DNS resolution not yet available for domain: $DomainName"
                    }
                  } catch {
                    Write-Output "DNS resolution check failed: $($_.Exception.Message)"
                  }
                } else {
                  Write-Output "Domain controllers not yet available"
                }
              } catch {
                Write-Output "Error checking domain controllers: $($_.Exception.Message)"
              }
            } elseif ($aaddsResource.Properties.provisioningState -eq "Failed") {
              Write-Error "Azure AD DS deployment failed!"
              throw "Azure AD DS deployment failed with state: Failed"
            } else {
              Write-Output "Azure AD DS is still provisioning. Current state: $($aaddsResource.Properties.provisioningState)"
            }
          } else {
            Write-Output "Azure AD DS resource not found or not accessible"
          }
        } catch {
          Write-Output "Error checking Azure AD DS status: $($_.Exception.Message)"
        }

        if (-not $isReady) {
          Write-Output "Waiting $waitInterval minutes before next check..."
          Start-Sleep -Seconds ($waitInterval * 60)
          $elapsedTime += $waitInterval
        }
      }

      if ($isReady) {
        Write-Output "Azure AD DS is ready for domain join operations!"
        $DeploymentScriptOutputs = @{
          'status' = 'ready'
          'message' = 'Azure AD DS is operational and ready for domain joins'
          'domainName' = $DomainName
          'readyTime' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss UTC')
        }
      } else {
        Write-Error "Timeout waiting for Azure AD DS to become ready after $maxWaitTime minutes"
        throw "Azure AD DS did not become ready within the timeout period"
      }
    '''
    arguments: '-DomainName "${domainName}" -AaddsResourceId "${aaddsResourceId}" -SubscriptionId "${subscription().subscriptionId}" -ResourceGroupName "${resourceGroup().name}"'
  }
  dependsOn: [
    roleAssignment
  ]
}

output deploymentScriptId string = waitForAzureADDS.id
output status string = waitForAzureADDS.properties.outputs.status
output message string = waitForAzureADDS.properties.outputs.message
output readyTime string = waitForAzureADDS.properties.outputs.readyTime