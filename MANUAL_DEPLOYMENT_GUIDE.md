# Manual ADDS Deployment Guide

This deployment has been modified to work with a manually configured Active Directory Domain Services (ADDS) environment instead of automatically deploying Azure AD Domain Services.

## Prerequisites

### 1. Active Directory Domain Services
- You must have an existing ADDS environment (on-premises or Azure-based)
- The domain must be accessible from Azure Virtual Networks
- DNS resolution must be properly configured

### 2. Domain Join User Account
**CRITICAL**: Before running the deployment, you must create a user account with the following characteristics:

- **Username**: Can be any valid domain username (e.g., `avdjoin`, `domainjoin`, `svc-avdjoin`)
- **Domain Rights**: The account must have the following permissions:
  - **Add workstations to domain** (SeAddWorkstationPrivilege)
  - **Log on as a service** (if using a service account)
  - Member of **Domain Users** group (minimum)
  - Optionally: Member of **Domain Computers** group

### 3. Network Connectivity
- Ensure network connectivity between Azure VNet and your domain controllers
- Configure DNS settings to point to your domain controllers
- Open required ports for domain communication (TCP 88, 135, 139, 389, 445, 464, 636, 3268, 3269; UDP 53, 88, 123, 389, 464)

## Environment Variables

Before running `azd up`, set the following environment variables:

```bash
# Required - Domain join credentials
azd env set DOMAIN_JOIN_USERNAME "your-domain\\username"
azd env set DOMAIN_JOIN_PASSWORD "your-password"

# Required - Domain configuration
azd env set DOMAIN_NAME "yourdomain.local"

# Standard deployment variables
azd env set WIN_VM_PASSWORD "your-vm-password"
azd env set AZURE_LOCATION "East US 2"
```

## Deployment Steps

1. **Verify Prerequisites**
   - Confirm your domain is accessible
   - Test domain join credentials using the validation script:
   ```powershell
   .\scripts\validate-domain-credentials.ps1 -DomainName "contoso.local" -Username "contoso\avdjoin" -Password "YourPassword"
   ```
   - Verify DNS resolution

2. **Set Environment Variables**
   ```bash
   azd env set DOMAIN_JOIN_USERNAME "yourdomain\\avdjoin"
   azd env set DOMAIN_JOIN_PASSWORD "SecurePassword123!"
   azd env set DOMAIN_NAME "contoso.local"
   azd env set WIN_VM_PASSWORD "VMPassword123!"
   ```

3. **Run Deployment**
   ```bash
   azd up
   ```

## Post-Deployment Configuration

### 1. Verify Domain Join
- Check that session hosts successfully joined the domain
- Verify they appear in the correct OU (default: Computers container)

### 2. Configure Group Policy (if needed)
- Apply any required AVD-specific group policies
- Configure FSLogix policies if using custom settings

### 3. User Access
- Add users to the AVD application group
- Ensure users have appropriate permissions on the FSLogix file share

## Troubleshooting

### Domain Join Failures
- **Error**: "The specified domain either does not exist or could not be contacted"
  - **Solution**: Verify DNS configuration and network connectivity
  
- **Error**: "Access denied" during domain join
  - **Solution**: Verify the domain join user has "Add workstations to domain" rights

- **Error**: "The trust relationship between this workstation and the primary domain failed"
  - **Solution**: Check time synchronization between VMs and domain controllers

### Network Issues
- Verify NSG rules allow domain traffic
- Check DNS server configuration in VNet
- Test connectivity from Azure VMs to domain controllers

## Security Considerations

1. **Service Account**: Consider using a dedicated service account for domain joins
2. **Password Security**: Use Azure Key Vault to store sensitive passwords
3. **Network Isolation**: Implement proper network segmentation
4. **Monitoring**: Enable monitoring and logging for security events

## Architecture Changes

This deployment removes the following components that were in the original Azure AD DS version:
- Azure AD Domain Services
- Managed Identity for ADDS management
- User creation scripts
- ADDS synchronization wait logic
- ADDS-specific subnet

The simplified architecture focuses on:
- AVD infrastructure (host pools, workspaces, application groups)
- Session host VMs with domain join
- Storage accounts for FSLogix and App Attach
- Network infrastructure