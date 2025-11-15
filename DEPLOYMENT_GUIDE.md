# Azure Virtual Desktop (AVD) Demo - Deployment Guide

## 🎉 Success! Your AVD Infrastructure with Azure AD DS is Deployed

Your Azure Virtual Desktop infrastructure has been successfully deployed to Azure, including automatic deployment and configuration of Azure AD Domain Services. The deployment now includes a complete domain-joined environment.

## 📋 Deployed Resources

Your AVD environment includes:
- **Azure AD Domain Services**: Automatically configured domain (e.g., `contoso.local`)
- **Resource Group**: Based on your environment name
- **Host Pool**: Domain-joined session hosts
- **Application Group**: Desktop application group
- **Workspace**: AVD workspace for user access
- **FSLogix Storage Account**: For user profile storage with domain authentication
- **App Attach Storage Account**: For application virtualization
- **Session Hosts**: Domain-joined Windows VMs ready for AVD
- **Virtual Network**: With dedicated subnets for session hosts and Azure AD DS

## 🔑 Important Notes

### Azure AD Domain Services
- **Deployment Time**: Azure AD DS typically takes 30-60 minutes to fully deploy
- **Domain Controllers**: Two domain controllers are automatically created
- **DNS**: The virtual network is automatically configured to use Azure AD DS DNS
- **Synchronization**: User accounts from your Azure AD tenant are automatically synchronized

### Domain Join Status
- Session hosts are automatically joined to the Azure AD DS domain
- Domain join occurs after Azure AD DS is fully operational
- This process may take additional time after the initial deployment

## 🛠️ Required Manual Configuration Steps

### 1. Verify Azure AD DS Deployment

Before proceeding, ensure Azure AD DS is fully deployed:

```powershell
# Check Azure AD DS status
Get-AzADDomainService -ResourceGroupName "rg-your-env-name" -Name "your-domain-name"
```

The status should show "Running" before proceeding with user configuration.

### 2. Connect with Proper Permissions

You'll need to sign in to Azure with an account that has:
- **Contributor** or **Owner** role on the subscription
- **User Administrator** role in Azure AD (for managing groups)

```powershell
# Sign in to Azure with your admin account
Connect-AzAccount

# Set the correct subscription context
Set-AzContext -SubscriptionId "your-subscription-id"
```

### 3. Run the Manual Post-Provision Script

The manual script will configure RBAC and security groups:

```powershell
.\scripts\manual-post-provision.ps1 -EnvironmentName "your-env-name" -ResourceGroupName "rg-your-env-name" -SubscriptionId "your-subscription-id" -FSLogixStorageAccountName "your-fslogix-storage" -AppAttachStorageAccountName "your-appattach-storage"
```

### 4. Create Domain Users

Since Azure AD DS synchronizes from Azure AD, you can create users either in:

#### Option A: Azure AD Portal
1. Go to [Azure Portal](https://portal.azure.com) → Azure Active Directory → Users
2. Create new users - they'll automatically sync to Azure AD DS

#### Option B: PowerShell
```powershell
# Create a new Azure AD user (will sync to Azure AD DS)
$passwordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$passwordProfile.Password = "TempPassword123!"
$passwordProfile.ForceChangePasswordNextLogin = $true

New-AzureADUser -DisplayName "Test User" -UserPrincipalName "testuser@yourdomain.onmicrosoft.com" -AccountEnabled $true -PasswordProfile $passwordProfile -MailNickName "testuser"
```

### 5. Add Users to AVD Groups

After creating users and running the post-provision script:

```powershell
# Add users to AVD Users group
$userGroup = Get-AzADGroup -DisplayName "AVD-Users-your-env-name"
$user = Get-AzADUser -UserPrincipalName "testuser@yourdomain.onmicrosoft.com"
Add-AzADGroupMember -TargetGroupObjectId $userGroup.Id -MemberObjectId $user.Id
```

### 6. Assign Users to Application Group

```powershell
# Assign the AVD Users group to the application group
$appGroup = Get-AzWvdApplicationGroup -ResourceGroupName "rg-your-env-name" -Name "ag-your-env-name"
$userGroup = Get-AzADGroup -DisplayName "AVD-Users-your-env-name"

New-AzRoleAssignment -ObjectId $userGroup.Id -RoleDefinitionName "Desktop Virtualization User" -Scope $appGroup.Id
```

## 🕒 Timing Considerations

### Deployment Timeline:
1. **Infrastructure (15-20 minutes)**: Virtual network, storage, compute resources
2. **Azure AD DS (30-60 minutes)**: Domain services deployment and configuration
3. **Domain Join (5-10 minutes)**: Session hosts joining the domain
4. **Manual Configuration (5-15 minutes)**: RBAC and user assignments

### What to Expect:
- Initial `azd up` completes when infrastructure is deployed
- Azure AD DS continues deploying in the background
- Session hosts may show "domain join pending" initially
- Allow 60-90 minutes total for complete deployment

## 🔧 Troubleshooting

### Azure AD DS Issues

Check deployment status:
```powershell
$aadds = Get-AzADDomainService -ResourceGroupName "rg-your-env-name"
Write-Output "Status: $($aadds.DomainServiceStatus)"
```

### Domain Join Issues

If session hosts fail to join domain:
1. Verify Azure AD DS is "Running"
2. Check DNS settings on virtual network
3. Verify domain admin credentials
4. Check session host logs in Azure portal

### Storage Access Issues

Test domain authentication:
```powershell
# From a domain-joined machine
Test-NetConnection your-storage-account.file.core.windows.net -Port 445
```

## 🎯 User Access Guide

### For End Users:
1. Navigate to [AVD Web Client](https://rdweb.wvd.microsoft.com/)
2. Sign in with Azure AD credentials (same account that syncs to Azure AD DS)
3. Access will work once the user is:
   - Added to AVD Users group
   - Assigned to the application group
   - Azure AD DS synchronization is complete

### For Administrators:
1. Domain admin account: `aaddsadmin@your-domain.local`
2. Use Azure portal for AVD management
3. Use traditional AD tools for domain management (via Azure Bastion or VPN)

## 🔐 Security Best Practices

### Azure AD DS Security:
- Enable Azure AD DS secure LDAP if external access is needed
- Configure conditional access policies
- Regular monitoring of domain admin accounts

### AVD Security:
- Implement conditional access for AVD access
- Configure MFA for all users
- Regular review of group memberships

## 📚 Key Differences from Manual Azure AD DS

This automated deployment:
- ✅ Creates Azure AD DS automatically
- ✅ Configures network DNS settings
- ✅ Joins session hosts to domain automatically
- ✅ Sets up proper subnet architecture
- ✅ Configures security groups for Azure AD DS

Manual setup would require:
- ❌ Manual Azure AD DS configuration
- ❌ DNS configuration
- ❌ Manual domain join process
- ❌ Security group configuration

## 🔄 Future Deployments

For future deployments with the updated template:
1. `azd up` includes Azure AD DS deployment
2. Provide both VM admin and domain admin passwords when prompted
3. Wait for complete deployment (60-90 minutes)
4. Run manual post-provision script for RBAC configuration

The solution now provides a complete, automated Azure AD DS + AVD environment!