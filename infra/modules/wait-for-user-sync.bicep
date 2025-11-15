@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Resource tags')
param tags object

@description('Domain name to test')
param domainName string

@description('Domain admin user UPN to verify')
param domainAdminUPN string

@description('Azure AD DS resource ID to check status')
param aaddsResourceId string

// Wait for Azure AD DS to be ready and user to be synchronized
resource waitForUserSync 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'wait-for-user-sync-${environmentName}'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azPowerShellVersion: '11.0'
    timeout: 'PT45M'
    retentionInterval: 'PT2H'
    scriptContent: '''
      param(
        [string]$DomainName,
        [string]$DomainAdminUPN,
        [string]$AADDSResourceId
      )

      Write-Output "Waiting for Azure AD DS to be fully operational and user sync to complete..."
      Write-Output "Domain: $DomainName"
      Write-Output "Domain Admin UPN: $DomainAdminUPN"
      Write-Output "Azure AD DS Resource ID: $AADDSResourceId"

      $maxAttempts = 30
      $waitInterval = 60 # seconds
      $attempt = 0
      $isReady = $false

      while ($attempt -lt $maxAttempts -and -not $isReady) {
        $attempt++
        Write-Output "Attempt $attempt of $maxAttempts - Checking Azure AD DS status..."

        try {
          # Check Azure AD DS status
          $aaddsStatus = Get-AzResource -ResourceId $AADDSResourceId | Get-AzResource -ExpandProperties
          
          if ($aaddsStatus.Properties.domainServiceStatus -eq "Running") {
            Write-Output "✓ Azure AD DS is running"
            
            # Additional checks for readiness
            if ($aaddsStatus.Properties.healthMonitors -and $aaddsStatus.Properties.healthMonitors.Count -gt 0) {
              $healthyMonitors = $aaddsStatus.Properties.healthMonitors | Where-Object { $_.health -eq "Healthy" }
              $healthPercentage = ($healthyMonitors.Count / $aaddsStatus.Properties.healthMonitors.Count) * 100
              
              Write-Output "Health monitors: $($healthyMonitors.Count)/$($aaddsStatus.Properties.healthMonitors.Count) healthy ($healthPercentage%)"
              
              if ($healthPercentage -ge 80) {
                Write-Output "✓ Azure AD DS health checks are passing"
                $isReady = $true
              }
              else {
                Write-Output "⚠ Azure AD DS health checks still pending..."
              }
            }
            else {
              Write-Output "⚠ No health monitors available yet, assuming ready after running status"
              $isReady = $true
            }
          }
          else {
            Write-Output "⚠ Azure AD DS status: $($aaddsStatus.Properties.domainServiceStatus)"
          }
        }
        catch {
          Write-Output "⚠ Error checking Azure AD DS status: $($_.Exception.Message)"
        }

        if (-not $isReady) {
          Write-Output "Waiting $waitInterval seconds before next attempt..."
          Start-Sleep -Seconds $waitInterval
        }
      }

      if ($isReady) {
        Write-Output "✓ Azure AD DS is ready for domain operations"
        
        # Additional wait for user synchronization
        Write-Output "Allowing additional time for user synchronization..."
        Start-Sleep -Seconds 120
        
        $DeploymentScriptOutputs = @{
          status = "ready"
          readyTime = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
          domainName = $DomainName
          userSyncComplete = "true"
        }
      }
      else {
        Write-Output "✗ Azure AD DS did not become ready within the timeout period"
        $DeploymentScriptOutputs = @{
          status = "timeout"
          readyTime = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
          domainName = $DomainName
          userSyncComplete = "false"
        }
      }
    '''
    arguments: '-DomainName ${domainName} -DomainAdminUPN ${domainAdminUPN} -AADDSResourceId ${aaddsResourceId}'
  }
}

output status string = waitForUserSync.properties.outputs.status
output readyTime string = waitForUserSync.properties.outputs.readyTime
output userSyncComplete string = waitForUserSync.properties.outputs.userSyncComplete
