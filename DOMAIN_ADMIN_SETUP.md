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
2. **Domain Admin**: The `addomainadmin` user is created in Azure AD with domain admin privileges
3. **Group Membership**: The user is automatically added to the AVD Admins group for proper permissions

### Deployment Process

1. **Infrastructure Deployment**: Bicep templates deploy Azure AD DS and AVD infrastructure
2. **User Creation**: Post-provision script creates `addomainadmin` in Azure AD
3. **Group Assignment**: User is added to AVD Admins group
4. **Domain Join**: Session hosts use `addomainadmin@{domainName}` for domain join operations

### Security Considerations

- **Password**: A secure random password is generated during deployment
- **Force Change**: User must change password on first login
- **Group Membership**: User is automatically added to AVD Admins for proper permissions
- **Credentials Display**: Credentials are displayed securely during deployment

## Usage

### During Deployment

The domain admin user is automatically created when you run the post-provision script. The credentials will be displayed in the console output:

```
DOMAIN ADMIN CREDENTIALS:
Username: addomainadmin@{tenant-domain}
Password: {generated-password}
IMPORTANT: Save these credentials securely!
```

### Manual Creation

If automatic creation fails, you can run the manual post-provision script:

```powershell
.\scripts\manual-post-provision.ps1
```

### Environment Variables

You can override the default domain admin username using environment variables:

```bash
export DOMAIN_ADMIN_USERNAME=mycustomadmin
```

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

## Best Practices

1. **Password Management**: Store the generated password in a secure password manager
2. **Group Management**: Use Azure AD groups for access control rather than direct user assignments
3. **Monitoring**: Monitor domain admin account usage through Azure AD audit logs
4. **Rotation**: Regularly rotate the domain admin password following security policies
5. **Least Privilege**: Only grant domain admin privileges when necessary for specific operations