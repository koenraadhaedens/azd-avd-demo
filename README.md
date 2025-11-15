# Azure Virtual Desktop Demo Environment

> **🚀 Quick Start**: If you're having deployment issues, check the [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for troubleshooting and manual configuration steps.

## Overview
This repository contains a complete Azure Virtual Desktop (AVD) demo environment deployed using Azure Developer CLI (azd) and Bicep templates. The solution provides a production-ready AVD infrastructure with FSLogix profiles, App Attach capabilities, and proper security configuration.

## Architecture Components

### Core AVD Resources
- **Host Pool**: Manages the collection of session hosts with pooled configuration
- **Workspace**: Provides user interface for accessing published resources
- **Application Group**: Desktop application group for full desktop access
- **Session Hosts**: Two Windows 11 virtual machines with AVD agents

### Storage Infrastructure
- **FSLogix Profile Storage**: Premium Azure Files storage for user profiles
- **App Attach Storage**: Standard storage for MSIX application packages
- **Azure AD DS**: Automatically deployed and configured for domain authentication

### Network Infrastructure
- **Virtual Network**: Isolated network for AVD resources with dedicated subnets for session hosts and Azure AD DS
- **Network Security Group**: Security rules for RDP and AVD traffic
- **Dedicated Subnets**: Separate subnets for session hosts and Azure AD Domain Services

### Security Configuration
- **RBAC Roles**: 
  - AVD Admins → Storage File Data SMB Share Elevated Contributor
  - AVD Users → Storage File Data SMB Share Contributor
- **Azure AD Groups**: Automated creation of AVD user and admin groups
- **FSLogix Configuration**: Registry settings applied via Custom Script Extension

## Prerequisites

### Azure Requirements
- Azure subscription with Owner or Contributor permissions
- Azure AD tenant with Global Administrator permissions
- Sufficient quota for compute and storage resources
- **Note**: Azure AD Domain Services will be automatically deployed as part of this solution

### Local Requirements
- **Azure CLI**: Latest version installed
- **Azure Developer CLI (azd)**: v1.5.0 or later
- **PowerShell** (for post-deployment configuration): v7.0 or later
- **Git**: For repository cloning

### Azure AD Domain Services
Azure AD Domain Services will be automatically deployed and configured as part of this solution. The deployment will:
1. Create and configure Azure AD DS in your tenant
2. Set up DNS settings for the virtual network
3. Use a default domain name (configurable via parameters)
4. **Wait for Azure AD DS to be fully operational** before deploying session hosts (prevents domain join failures)

> **Note**: Azure AD DS deployment takes 60-90 minutes. The template includes an automatic wait mechanism to ensure domain services are ready before session hosts are deployed. See [AZURE_AD_DS_TIMING_FIX.md](./AZURE_AD_DS_TIMING_FIX.md) for technical details.

## Quick Start Deployment

### 1. Clone and Initialize
```bash
git clone https://github.com/koenraadhaedens/azd-avd-demo.git
cd azd-avd-demo
azd auth login
azd init
```

### 2. Configure Environment
```bash
# Required settings
azd env set AZURE_LOCATION "East US 2"

# Optional settings with defaults
azd env set AADDS_DOMAIN_NAME "contoso.local"  # Domain name for Azure AD DS (will be created)

# Optional settings with defaults
azd env set AVD_ADMIN_USERNAME "avdadmin"
azd env set VNET_ADDRESS_PREFIX "10.0.0.0/16"
azd env set SUBNET_ADDRESS_PREFIX "10.0.1.0/24"
azd env set SESSION_HOST_COUNT "2"
```

### 3. Deploy Infrastructure
```bash
azd up
```

When prompted, provide:
- **Environment name**: A unique identifier (e.g., "avd-demo-001")
- **VM Admin Password**: Secure password for session hosts (will be prompted securely)
- **Domain Admin Password**: Password for the Azure AD DS domain admin account (will be prompted securely)

### 4. Post-Deployment Configuration
The deployment automatically runs a post-provision script that:
- Creates "AVD Admins" and "AVD Users" Azure AD groups
- Assigns appropriate RBAC roles to storage accounts
- Configures FSLogix registry settings on session hosts
- Sets up App Attach directory structure

## Manual Post-Deployment Steps

### 1. Add Users to Groups
```powershell
# Get group IDs
$avdUsersGroup = Get-AzADGroup -DisplayName "AVD Users"
$avdAdminsGroup = Get-AzADGroup -DisplayName "AVD Admins"

# Add users (replace with actual user IDs)
Add-AzADGroupMember -MemberObjectId "user-object-id" -TargetGroupObjectId $avdUsersGroup.Id
Add-AzADGroupMember -MemberObjectId "admin-object-id" -TargetGroupObjectId $avdAdminsGroup.Id
```

### 2. Upload MSIX Packages (Optional)
```powershell
# Get storage context
$storageAccount = Get-AzStorageAccount -ResourceGroupName "rg-your-env-name" -Name "*appattach*"
$ctx = $storageAccount.Context

# Upload MSIX package
Set-AzStorageFileContent -ShareName "appattach" -Source "C:\path\to\package.msix" -Path "msix-packages/package.msix" -Context $ctx
```

## Resource Naming Convention

| Resource Type | Naming Pattern | Example |
|---------------|----------------|---------|
| Resource Group | `rg-{environmentName}` | `rg-avd-demo-001` |
| Host Pool | `hp-{environmentName}` | `hp-avd-demo-001` |
| Workspace | `ws-{environmentName}` | `ws-avd-demo-001` |
| Application Group | `ag-{environmentName}` | `ag-avd-demo-001` |
| Session Hosts | `vm-{environmentName}-{index}` | `vm-avd-demo-001-01` |
| Virtual Network | `vnet-{environmentName}` | `vnet-avd-demo-001` |
| FSLogix Storage | `st{environmentName}fslogix` | `stavddemo001fslogix` |
| App Attach Storage | `st{environmentName}appattach` | `stavddemo001appattach` |

## Accessing the Environment

### For End Users
1. Navigate to [AVD Web Client](https://rdweb.wvd.microsoft.com)
2. Sign in with Azure AD credentials
3. Click on the published desktop to launch session

### For Administrators
1. Access Azure portal
2. Navigate to Azure Virtual Desktop service
3. Manage host pools, application groups, and user assignments

## Configuration Details

### FSLogix Settings
The deployment configures the following FSLogix registry settings:
- **Profile Location**: `\\{storageaccount}.file.core.windows.net\profiles`
- **Profile Size**: 10GB (10240MB)
- **Dynamic Disks**: Enabled
- **Delete Local Profile**: Enabled

### Storage Configuration
- **FSLogix Storage**: Premium FileStorage with SMB Multichannel
- **App Attach Storage**: Standard StorageV2 with hot tier
- **Authentication**: Azure AD DS with Kerberos
- **Encryption**: AES-256-GCM for SMB channel encryption

### Network Security
- **NSG Rules**: Allow RDP from VNet, AVD service traffic outbound
- **Storage Access**: Private endpoints (can be configured post-deployment)
- **Session Host Security**: Domain-joined with automatic updates enabled

## Troubleshooting

### Common Issues

#### Domain Join Failures
```bash
# Check Azure AD DS status
az ad ds show --resource-group "aadds-rg" --name "contoso.com"

# Verify DNS configuration
nslookup contoso.com
```

#### Storage Access Issues
```powershell
# Verify RBAC assignments
Get-AzRoleAssignment -Scope "/subscriptions/sub-id/resourceGroups/rg-name/providers/Microsoft.Storage/storageAccounts/storage-name"

# Test storage connectivity from session host
Test-NetConnection storage-account-name.file.core.windows.net -Port 445
```

#### FSLogix Profile Issues
```powershell
# Check FSLogix configuration on session host
Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles"

# View FSLogix logs
Get-WinEvent -LogName "Microsoft-FSLogix-Apps/Operational" -MaxEvents 50
```

### Logging and Monitoring
- **Activity Logs**: Available in Azure portal for all resource operations
- **AVD Diagnostics**: Can be enabled for detailed session monitoring
- **FSLogix Logs**: Located in Windows Event Logs on session hosts

## Cost Optimization

### Development/Testing
- Use Standard_B2ms for session hosts
- Implement auto-shutdown schedules
- Use Standard_LRS storage for non-production

### Production
- Enable AVD Start VM on Connect for cost savings
- Implement scaling plans for dynamic capacity
- Monitor usage patterns and adjust VM sizes accordingly

## Cleanup

### Complete Environment Cleanup
```bash
azd down --force --purge
```

### Partial Cleanup (Keep Azure AD Groups)
```bash
azd down
# Manually delete Azure AD groups if no longer needed
```

## Security Best Practices

### Network Security
- Implement Azure Firewall or NVA for outbound traffic control
- Enable private endpoints for storage accounts
- Use NSG flow logs for network monitoring

### Identity and Access
- Implement Conditional Access policies for AVD access
- Enable MFA for all AVD users
- Regular review of group memberships and RBAC assignments

### Data Protection
- Enable soft delete on storage accounts
- Implement backup strategies for user profiles
- Consider customer-managed keys for storage encryption

## Support and Contributing

### Getting Help
- Review Azure Virtual Desktop documentation
- Check Azure Service Health for any service issues
- Use Azure Support for technical assistance

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request with detailed description

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Changelog

### v1.0.0 (Initial Release)
- Complete AVD infrastructure deployment
- FSLogix profile containers support
- App Attach storage configuration
- Automated RBAC and security setup
- Comprehensive documentation and troubleshooting guides
