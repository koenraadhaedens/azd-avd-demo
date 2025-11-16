@description('Environment name for resource naming')
param environmentName string

@description('Location for resources')
param location string

@description('Resource tags')
param tags object

@description('Domain admin username')
param domainAdminUsername string

@secure()
@description('Domain admin password')
param domainAdminPassword string

@description('Tenant domain for creating the UPN')
param tenantDomain string

@description('User Assigned Managed Identity ID for the deployment script')
param managedIdentityId string

// Create a deployment script to create the Azure AD user
resource createDomainAdminScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-domain-admin-${environmentName}'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'DOMAIN_ADMIN_PASSWORD'
        secureValue: domainAdminPassword
      }
    ]
    scriptContent: '''
      param(
        [string]$DomainAdminUsername,
        [string]$TenantDomain
      )

      Write-Output "Starting domain admin user creation process..."
      Write-Output "Domain Admin Username: $DomainAdminUsername"
      Write-Output "Tenant Domain: $TenantDomain"

      # Get the password from environment variable (more secure and avoids command-line parsing issues)
      $DomainAdminPassword = $env:DOMAIN_ADMIN_PASSWORD
      if (-not $DomainAdminPassword) {
        Write-Output "✗ Domain admin password not found in environment variables"
        $DeploymentScriptOutputs = @{
          userId = ""
          userPrincipalName = ""
          status = "failed"
          error = "Password not found in environment variables"
        }
        return
      }

      # Create the domain admin user using Azure PowerShell with User Assigned Managed Identity
      $userPrincipalName = "$DomainAdminUsername@$TenantDomain"
      
      try {
        Write-Output "Checking if user already exists: $userPrincipalName"
        $existingUser = Get-AzADUser -Filter "userPrincipalName eq '$userPrincipalName'" -ErrorAction SilentlyContinue
        
        if (-not $existingUser) {
          Write-Output "Creating Azure AD user: $userPrincipalName"
          
          # Create password profile
          $passwordProfile = @{
            Password = $DomainAdminPassword
            ForceChangePasswordNextSignIn = $true
          }
          
          # Create user parameters
          $userParams = @{
            UserPrincipalName = $userPrincipalName
            DisplayName = "AD Domain Admin"
            MailNickname = $DomainAdminUsername
            PasswordProfile = $passwordProfile
            UsageLocation = "US"
            AccountEnabled = $true
          }
          
          Write-Output "Creating user with parameters..."
          $user = New-AzADUser @userParams
          
          if ($user) {
            Write-Output "✓ User created successfully: $($user.UserPrincipalName)"
            Write-Output "User ID: $($user.Id)"
            
            # Wait for user propagation across Azure AD
            Write-Output "Waiting for user propagation (60 seconds)..."
            Start-Sleep -Seconds 60
            
            # Verify the user was created
            $verifyUser = Get-AzADUser -UserPrincipalName $userPrincipalName -ErrorAction SilentlyContinue
            if ($verifyUser) {
              Write-Output "✓ User verification successful"
            } else {
              Write-Output "⚠ User verification failed, but creation succeeded"
            }
            
            $DeploymentScriptOutputs = @{
              userId = $user.Id
              userPrincipalName = $user.UserPrincipalName
              status = "created"
            }
          }
          else {
            Write-Output "✗ User creation returned null"
            $DeploymentScriptOutputs = @{
              userId = ""
              userPrincipalName = ""
              status = "failed"
              error = "User creation returned null"
            }
          }
        }
        else {
          Write-Output "✓ User already exists: $userPrincipalName"
          Write-Output "User ID: $($existingUser.Id)"
          
          $DeploymentScriptOutputs = @{
            userId = $existingUser.Id
            userPrincipalName = $existingUser.UserPrincipalName
            status = "existing"
          }
        }
      }
      catch {
        Write-Output "✗ Error during user creation: $($_.Exception.Message)"
        Write-Output "Error Details: $($_.Exception.ToString())"
        Write-Output "PowerShell Version: $($PSVersionTable.PSVersion)"
        Write-Output "Available Modules:"
        Get-Module -ListAvailable | Where-Object { $_.Name -like "*Az*" } | ForEach-Object { Write-Output "  $($_.Name) $($_.Version)" }
        
        $DeploymentScriptOutputs = @{
          userId = ""
          userPrincipalName = ""
          status = "failed"
          error = $_.Exception.Message
        }
      }
      
      Write-Output "Domain admin user process completed with status: $($DeploymentScriptOutputs.status)"
    '''
    arguments: '-DomainAdminUsername ${domainAdminUsername} -TenantDomain ${tenantDomain}'
  }
}

// Output the user information
output userId string = createDomainAdminScript.properties.outputs.userId
output userPrincipalName string = createDomainAdminScript.properties.outputs.userPrincipalName
output status string = createDomainAdminScript.properties.outputs.status
output domainAdminUsername string = domainAdminUsername
output domainAdminUPN string = '${domainAdminUsername}@${tenantDomain}'
