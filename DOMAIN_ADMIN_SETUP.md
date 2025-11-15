# Domain Admin User Configuration

## Overview

The AVD demo environment has been updated to use a dedicated domain admin user called `addomainadmin` instead of the default Azure AD DS admin account. This user is automatically created during the post-provision process and added to the AVD Admins group.

## Changes Made

### 1. Bicep Template Updates

#### `infra/main.bicep`:
- Added `domainAdminUsername` parameter with default value `'addomainadmin'`
- Updated `adminUsername` default value to `'addomainadmin'`
- Modified session hosts module call to pass the `domainAdminUsername` parameter

#### `infra/modules/session-hosts.bicep`:
- Updated `domainAdminUsername` parameter to accept explicit username instead of constructing it
- Modified domain join extension to use proper UPN format: `${domainAdminUsername}@${domainName}`

#### `infra/main.parameters.json`:
- Added `domainAdminUsername` parameter with default value `addomainadmin`
- Updated `adminUsername` default value to `addomainadmin`

### 2. PowerShell Script Updates

#### `scripts/post-provision.ps1`:
- Added `New-AzureADUserIfNotExists` function to create Azure AD users
- Added `Add-UserToAzureADGroup` function to add users to groups
- Implemented automatic creation of `addomainadmin` user in Azure AD
- Added the domain admin user to the AVD Admins group
- Updated output to display domain admin credentials securely

#### `scripts/manual-post-provision.ps1`:
- Added the same user creation functionality for manual execution
- Enhanced with better error handling and visual feedback

## How It Works

### Azure AD Domain Services User Management

Azure AD Domain Services (Azure AD DS) is different from traditional on-premises Active Directory:

1. **User Creation**: Users must be created in Azure AD first, then synchronized to Azure AD DS
2. **Domain Admin**: The `addomainadmin` user is created in Azure AD during infrastructure deployment
3. **Synchronization**: The user is synchronized to Azure AD DS before session hosts attempt domain join
4. **Group Membership**: The user is added to the AVD Admins group during post-provision

### Deployment Process

1. **Network Infrastructure**: Virtual networks and subnets are deployed first
2. **Domain Admin Creation**: `addomainadmin` user is created in Azure AD via deployment script
3. **Azure AD DS Deployment**: Azure AD Domain Services is deployed with proper dependencies
4. **User Synchronization Wait**: Deployment waits for the domain admin user to sync to Azure AD DS
5. **AVD Infrastructure**: Host pools, workspaces, and storage accounts are deployed
6. **Session Host Deployment**: VMs are deployed and joined to the domain using the pre-created domain admin
7. **Post-Provision**: Groups are configured and the domain admin is added to AVD Admins group

### Security Considerations

- **Password**: A secure random password is generated during infrastructure deployment
- **Force Change**: User must change password on first login
- **Pre-Creation**: User is available before domain join operations begin
- **Synchronization**: Deployment waits for proper user sync before proceeding
- **Group Membership**: User is automatically added to AVD Admins for proper permissions

## Usage

### During Deployment

The domain admin user is automatically created during the infrastructure deployment phase using a deployment script. The password is securely generated and the user is ready for domain join operations.

**Important**: The deployment script creates the user, but the password is generated securely within the deployment. You'll need to reset the password after deployment if you need to use this account interactively.

### Post-Deployment Configuration

The post-provision script will:

1. Verify the domain admin user exists
2. Add the user to the AVD Admins group
3. Configure proper permissions and group memberships

### Manual Creation

If automatic creation fails during deployment, the post-provision script will attempt to create the user manually and display the credentials.

### Environment Variables

You can customize the deployment using these environment variables:

```bash
export DOMAIN_ADMIN_USERNAME=mycustomadmin
export TENANT_DOMAIN=contoso.onmicrosoft.com
export DOMAIN_ADMIN_PASSWORD=SecurePassword123!
```

**Required**: `TENANT_DOMAIN` must be set to your Azure AD tenant's default domain (e.g., contoso.onmicrosoft.com)

## Verification

After deployment, verify the configuration:

1. **Azure AD**: Check that `addomainadmin` user exists in Azure AD
2. **Group Membership**: Verify user is member of AVD Admins group
3. **Domain Join**: Confirm session hosts successfully joined the domain
4. **AVD Access**: Test that domain admin can access AVD resources

## Troubleshooting

### User Creation Fails
- Ensure you have sufficient Azure AD permissions
- Check that the tenant supports user creation
- Verify the default domain is configured correctly

### Domain Join Fails
- Confirm Azure AD DS is fully deployed and operational
- Check that the domain admin user has been synchronized to Azure AD DS
- Verify network connectivity between session hosts and Azure AD DS

### Permission Issues
- Ensure the domain admin user is in the AVD Admins group
- Check RBAC assignments on storage accounts
- Verify the user has necessary permissions in Azure AD DS

## Troubleshooting

### Azure AD DS Deployment Failures

If you encounter "The managed domain is in a failed state" error, see the comprehensive troubleshooting guide: [AZURE_AD_DS_TROUBLESHOOTING.md](./AZURE_AD_DS_TROUBLESHOOTING.md)

Common issues and quick fixes:

#### Domain Admin User Creation Fails
- **Issue**: Deployment script fails to create the domain admin user
- **Cause**: Insufficient Azure AD permissions
- **Solution**: Ensure you have Global Administrator role in Azure AD
- **Verification**: 
  ```powershell
  $user = Get-AzADUser -UserPrincipalName (Get-AzContext).Account.Id
  $globalAdminRole = Get-AzADDirectoryRole | Where-Object { $_.DisplayName -eq "Global Administrator" }
  Get-AzADDirectoryRoleMember -ObjectId $globalAdminRole.Id | Where-Object { $_.Id -eq $user.Id }
  ```

#### Domain Join Fails
- **Issue**: Session hosts fail to join the domain even with domain admin user created
- **Cause**: User not synchronized to Azure AD DS or Azure AD DS not ready
- **Solution**: Check the wait-for-user-sync deployment script logs
- **Manual Check**:
  ```powershell
  # Check if Azure AD DS is running
  $aadds = Get-AzResource -ResourceType "Microsoft.AAD/DomainServices"
  $aadds.Properties.domainServiceStatus
  ```

#### User Creation Timeout
- **Issue**: Domain admin user creation script times out
- **Cause**: Network connectivity or Azure AD service issues
- **Solution**: Run the post-provision script manually to create the user

### User Synchronization Issues

#### User Not Appearing in Azure AD DS
- **Wait Time**: Azure AD to Azure AD DS sync can take 20-30 minutes
- **Force Sync**: There's no way to force sync, you must wait
- **Verification**: Check Azure portal → Azure AD Domain Services → Users

#### Password Issues
- **Issue**: Domain admin password doesn't work for domain operations
- **Cause**: Password complexity requirements or sync issues
- **Solution**: Reset the password in Azure AD and wait for sync:
  ```powershell
  $userPrincipalName = "addomainadmin@yourdomain.onmicrosoft.com"
  $newPassword = ConvertTo-SecureString "NewSecurePassword123!" -AsPlainText -Force
  Set-AzADUser -UserPrincipalName $userPrincipalName -Password $newPassword
  ```

### Deployment Script Issues

#### Managed Identity Permissions
- **Issue**: Deployment script fails with permission errors
- **Cause**: Managed identity lacks Azure AD permissions
- **Solution**: The script should automatically get necessary permissions, but may need manual role assignment

#### Script Timeout
- **Issue**: User creation script times out after 30 minutes
- **Solution**: Increase timeout or run creation manually:
  ```powershell
  # Manual user creation
  $userParams = @{
    UserPrincipalName = "addomainadmin@yourdomain.onmicrosoft.com"
    DisplayName = "AD Domain Admin"
    MailNickname = "addomainadmin"
    PasswordProfile = @{
      Password = "SecurePassword123!"
      ForceChangePasswordNextSignIn = $true
    }
    UsageLocation = "US"
    AccountEnabled = $true
  }
  
  New-AzADUser @userParams
  ```

## Best Practices

1. **Password Management**: Store the generated password in a secure password manager
2. **Group Management**: Use Azure AD groups for access control rather than direct user assignments
3. **Monitoring**: Monitor domain admin account usage through Azure AD audit logs
4. **Rotation**: Regularly rotate the domain admin password following security policies
5. **Least Privilege**: Only grant domain admin privileges when necessary for specific operations
6. **Pre-Deployment Validation**: Always verify Global Administrator permissions before starting deployment
7. **Staged Deployment**: For production environments, consider deploying Azure AD DS manually first, then the rest of the infrastructure