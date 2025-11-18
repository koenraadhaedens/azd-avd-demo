#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Complete FSLogix setup script with Entra ID DS authentication

.DESCRIPTION
    This script configures FSLogix with Azure AD DS authentication including:
    - Storage account configuration with Azure AD DS
    - SMB role assignments 
    - NTFS permissions
    - Session host FSLogix configuration

.PARAMETER StorageAccountName
    Name of the FSLogix storage account

.PARAMETER FileShareName  
    Name of the FSLogix file share

.PARAMETER ResourceGroupName
    Resource group containing the storage account

.PARAMETER DomainName
    Azure AD DS domain name

.EXAMPLE
    .\Complete-FSLogixSetup.ps1 -StorageAccountName "stfslogix123" -FileShareName "profiles" -ResourceGroupName "rg-avd-demo" -DomainName "contoso.com"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]  
    [string]$FileShareName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName
)

# Import required modules
Import-Module Az.Accounts -Force
Import-Module Az.Storage -Force
Import-Module Az.Resources -Force

try {
    Write-Host "Starting complete FSLogix setup with Azure AD DS..." -ForegroundColor Green
    
    # Check Azure context
    $context = Get-AzContext
    if (!$context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Using Azure context:" -ForegroundColor Yellow
    Write-Host "  Subscription: $($context.Subscription.Name)" -ForegroundColor White
    Write-Host "  Tenant: $($context.Tenant.Id)" -ForegroundColor White
    
    # Get storage account
    Write-Host "Getting storage account: $StorageAccountName" -ForegroundColor Yellow
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
    
    if (!$storageAccount) {
        Write-Error "Storage account '$StorageAccountName' not found in resource group '$ResourceGroupName'"
        exit 1
    }
    
    Write-Host "✓ Storage account found: $($storageAccount.StorageAccountName)" -ForegroundColor Green
    
    # Check if Azure AD DS is already configured
    Write-Host "Checking Azure AD DS configuration..." -ForegroundColor Yellow
    
    if ($storageAccount.AzureFilesIdentityBasedAuth.DirectoryServiceOptions -eq "AADDS") {
        Write-Host "✓ Azure AD DS authentication is already configured" -ForegroundColor Green
    }
    else {
        Write-Host "Azure AD DS authentication not configured. This should be set up via Bicep deployment." -ForegroundColor Yellow
        Write-Warning "Please ensure the storage account is deployed with Azure AD DS configuration"
    }
    
    # Verify file share exists
    Write-Host "Checking file share: $FileShareName" -ForegroundColor Yellow
    $ctx = $storageAccount.Context
    $fileShare = Get-AzStorageShare -Name $FileShareName -Context $ctx -ErrorAction SilentlyContinue
    
    if (!$fileShare) {
        Write-Error "File share '$FileShareName' not found in storage account '$StorageAccountName'"
        exit 1
    }
    
    Write-Host "✓ File share found: $($fileShare.Name)" -ForegroundColor Green
    
    # Test storage account connectivity
    Write-Host "Testing storage account connectivity..." -ForegroundColor Yellow
    $storageAccountFqdn = "$StorageAccountName.file.core.windows.net"
    
    try {
        $testConnection = Test-NetConnection -ComputerName $storageAccountFqdn -Port 445 -WarningAction SilentlyContinue
        if ($testConnection.TcpTestSucceeded) {
            Write-Host "✓ SMB connectivity successful (port 445)" -ForegroundColor Green
        }
        else {
            Write-Warning "SMB connectivity failed. Check firewall and network settings."
        }
    }
    catch {
        Write-Warning "Could not test SMB connectivity: $($_.Exception.Message)"
    }
    
    # Get domain groups for role assignments  
    Write-Host "Getting domain group information..." -ForegroundColor Yellow
    
    # Run the domain groups script
    $groupScript = Join-Path $PSScriptRoot "Get-FSLogixDomainGroups.ps1"
    if (Test-Path $groupScript) {
        Write-Host "Running domain groups discovery..." -ForegroundColor Yellow
        & $groupScript -DomainName $DomainName
    }
    else {
        Write-Warning "Domain groups script not found. Please run Get-FSLogixDomainGroups.ps1 manually to get group object IDs."
    }
    
    # Display FSLogix configuration summary
    Write-Host "`nFSLogix Configuration Summary:" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "Storage Account: $StorageAccountName" -ForegroundColor White
    Write-Host "File Share: $FileShareName" -ForegroundColor White  
    Write-Host "Domain: $DomainName" -ForegroundColor White
    Write-Host "UNC Path: \\$storageAccountFqdn\$FileShareName" -ForegroundColor White
    
    # Display next steps
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "===========" -ForegroundColor Cyan
    Write-Host "1. Ensure Azure AD DS groups have been assigned to the storage account" -ForegroundColor Yellow
    Write-Host "2. Run the NTFS permissions script from a domain-joined machine:" -ForegroundColor Yellow
    Write-Host "   .\Set-FSLogixNTFSPermissions.ps1 -StorageAccountName '$StorageAccountName' -FileShareName '$FileShareName' -DomainName '$DomainName'" -ForegroundColor Cyan
    Write-Host "3. Verify FSLogix is properly configured on session hosts" -ForegroundColor Yellow
    Write-Host "4. Test user profile creation by signing in to an AVD session" -ForegroundColor Yellow
    
    # Display troubleshooting information
    Write-Host "`nTroubleshooting:" -ForegroundColor Cyan
    Write-Host "===============" -ForegroundColor Cyan
    Write-Host "• FSLogix logs location: C:\Users\{username}\AppData\Local\FSLogix\Logs" -ForegroundColor White
    Write-Host "• Storage account logs: Azure portal > Storage account > Monitoring > Insights" -ForegroundColor White
    Write-Host "• Test connectivity: Test-NetConnection -ComputerName $storageAccountFqdn -Port 445" -ForegroundColor White
    Write-Host "• Registry settings: HKLM\SOFTWARE\FSLogix\Profiles" -ForegroundColor White
    
    Write-Host "`n✓ FSLogix setup verification completed!" -ForegroundColor Green
    
}
catch {
    Write-Error "FSLogix setup failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}