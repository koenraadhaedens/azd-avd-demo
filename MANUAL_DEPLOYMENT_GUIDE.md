# Manual ADDS Deployment Guide

This deployment has been modified to work with a manually configured Active Directory Domain Services (ADDS) environment instead of automatically deploying Azure AD Domain Services.

## Prerequisites

### 1. Azure Permissions
- **AVD Subscription**: Owner or Contributor permissions for deploying AVD resources
- **Domain Controller VNet**: Network Contributor permissions on the VNet where domain controller is located
- **Cross-Subscription**: If domain controller is in a different subscription, ensure appropriate permissions

### 2. Active Directory Domain Services
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
- **DNS Server IP**: You must know the IP address of your domain controller/DNS server
- **Domain Controller VNet**: You must know the resource ID of the VNet where your domain controller is located
- **Network Peering**: Both forward and reverse VNet peering will be automatically created
- **Permissions**: Ensure you have Network Contributor access to the domain controller VNet
- Configure DNS settings to point to your domain controllers
- Open required ports for domain communication (TCP 88, 135, 139, 389, 445, 464, 636, 3268, 3269; UDP 53, 88, 123, 389, 464)

## Environment Variables

Before running `azd up`, set the following environment variables:

```bash
# Required - Domain join credentials (domain will be auto-detected from username)
azd env set DOMAIN_JOIN_USERNAME "your-domain\\username"  # or "username@domain.com"
azd env set DOMAIN_JOIN_PASSWORD "your-password"

# Required - DNS server for domain resolution
azd env set DNS_SERVER_IP "192.168.1.10"  # IP of your domain controller

# Required - VNet where domain controller is located
azd env set DOMAIN_CONTROLLER_VNET_ID "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-domain/providers/Microsoft.Network/virtualNetworks/vnet-domain"

# Standard deployment variables
azd env set WIN_VM_PASSWORD "your-vm-password"
azd env set AZURE_LOCATION "East US 2"
```

**Note**: The domain name is automatically extracted from the `DOMAIN_JOIN_USERNAME`. You can use either:
- Domain\\Username format: `CONTOSO\\avdjoin` → extracts "CONTOSO"
- UPN format: `avdjoin@contoso.local` → extracts "contoso.local"

**Examples:**
- `azd env set DOMAIN_JOIN_USERNAME "CONTOSO\\svc-avdjoin"`
- `azd env set DOMAIN_JOIN_USERNAME "avdjoin@corp.company.com"`
- `azd env set DOMAIN_JOIN_USERNAME "company\\domainjoin"`
- `azd env set DNS_SERVER_IP "10.0.0.4"`  # On-premises DC
- `azd env set DNS_SERVER_IP "192.168.1.10"`  # Local network DC
- `azd env set DOMAIN_CONTROLLER_VNET_ID "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-domain/providers/Microsoft.Network/virtualNetworks/vnet-domain"`

## Deployment Steps

1. **Verify Prerequisites**
   - Confirm your domain is accessible
   - Identify your DNS server IP address:
   ```powershell
   .\scripts\detect-dns-server.ps1 -DomainName "contoso.local"
   ```
   - Find your domain controller VNet resource ID:
   ```powershell
   .\scripts\get-vnet-info.ps1 -DnsServerIp "192.168.1.10"
   ```
   - Test domain extraction logic:
   ```powershell
   .\scripts\test-domain-extraction.ps1 -Username "CONTOSO\avdjoin"
   ```
   - Test domain join credentials using the validation script:
   ```powershell
   .\scripts\validate-domain-credentials.ps1 -DomainName "contoso.local" -Username "contoso\avdjoin" -Password "YourPassword" -DnsServerIp "192.168.1.10"
   ```
   - Verify DNS resolution

2. **Set Environment Variables**
   ```bash
   azd env set DOMAIN_JOIN_USERNAME "yourdomain\\avdjoin"  # Domain auto-detected
   azd env set DOMAIN_JOIN_PASSWORD "SecurePassword123!"
   azd env set DNS_SERVER_IP "192.168.1.10"  # Your domain controller IP
   azd env set DOMAIN_CONTROLLER_VNET_ID "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/vnet-domain"
   azd env set WIN_VM_PASSWORD "VMPassword123!"
   ```

3. **Run Deployment**
   ```bash
   azd up
   ```
   The deployment will automatically:
   - Create AVD VNet with custom DNS configuration
   - Set up forward VNet peering (AVD → Domain Controller)
   - Set up reverse VNet peering (Domain Controller → AVD)
   - Deploy session hosts and join them to the domain

4. **Validate Deployment (Recommended)**
   ```powershell
   .\scripts\validate-deployment.ps1 -EnvironmentName "your-azd-env-name"
   ```

## Post-Deployment Verification

### 1. Verify Network Connectivity
- Check VNet peering status in Azure Portal
- Verify deployment output shows `vnetPeeringStatus: Connected`
- Test DNS resolution from AVD VNet to domain

### 2. Verify Domain Join
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
- **Check VNet DNS configuration**: Ensure DNS servers point to your domain controller
- **Test DNS resolution**: Use `nslookup domain.com dns-server-ip` to verify
- Test connectivity from Azure VMs to domain controllers

### DNS Configuration Issues
- **Error**: "The specified domain either does not exist or could not be contacted"
  - **Solution**: Verify DNS server IP is correct and accessible from Azure VNet
  - **Solution**: Check that DNS server can resolve the domain name
  
### VNet Peering Issues
- **Error**: "Address space overlaps"
  - **Solution**: Ensure AVD VNet address space doesn't overlap with domain controller VNet
  - **Solution**: Modify `VNET_ADDRESS_PREFIX` parameter (default: 10.0.0.0/16)

- **Error**: "Insufficient permissions" on reverse peering
  - **Solution**: Ensure you have Network Contributor role on the domain controller VNet
  - **Solution**: Grant permissions before running deployment: `azd up`

- **Error**: Peering shows "Disconnected" state
  - **Solution**: Check that both peerings are created automatically during deployment
  - **Solution**: Verify no network policies are blocking the connection
  - **Solution**: Check deployment outputs for `vnetPeeringStatus`

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
- **Custom DNS configuration**: VNet configured with your domain controller's IP
- **Automatic VNet peering**: Bidirectional peering between AVD VNet and domain controller VNet
- Storage accounts for FSLogix and App Attach
- Network infrastructure with domain-aware DNS settings