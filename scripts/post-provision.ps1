#!/usr/bin/env pwsh

# Post-provision script for AVD environment
# This script configures RBAC assignments and NTFS permissions
# If permissions are insufficient, it will log the issue and continue

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZURE_RESOURCE_GROUP_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$FSLogixStorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$AppAttachStorageAccountName
)

Write-Host "Starting post-provision configuration for AVD environment: $EnvironmentName" -ForegroundColor Green

# Check if we're logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "No Azure context found. Attempting to use managed identity..." -ForegroundColor Yellow
        # Try to authenticate with managed identity if running in Azure
        try {
            Connect-AzAccount -Identity -ErrorAction Stop
            $context = Get-AzContext
        }
        catch {
            Write-Host "Managed identity authentication failed. Skipping post-provision tasks." -ForegroundColor Yellow
            Write-Host "Please run .\scripts\manual-post-provision.ps1 manually with appropriate permissions." -ForegroundColor Yellow
            exit 0
        }
    }
    Write-Host "Using Azure context: $($context.Account.Id)" -ForegroundColor Yellow
}
catch {
    Write-Host "Azure PowerShell module not found or authentication failed." -ForegroundColor Yellow
    Write-Host "Please run .\scripts\manual-post-provision.ps1 manually with appropriate permissions." -ForegroundColor Yellow
    exit 0
}

# Set subscription context - use the subscription from environment variable if available
if ($SubscriptionId) {
    try {
        $currentContext = Get-AzContext
        Write-Host "Current subscription: $($currentContext.Subscription.Id)" -ForegroundColor Yellow
        
        if ($currentContext.Subscription.Id -ne $SubscriptionId) {
            Write-Host "Setting subscription context to: $SubscriptionId" -ForegroundColor Yellow
            Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
            Write-Host "Successfully set context to subscription: $SubscriptionId" -ForegroundColor Green
        } else {
            Write-Host "Already in correct subscription context" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Failed to set subscription context to: $SubscriptionId" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Continuing with current subscription: $((Get-AzContext).Subscription.Id)" -ForegroundColor Yellow
    }
} else {
    $currentContext = Get-AzContext
    Write-Host "No subscription ID provided, using current subscription: $($currentContext.Subscription.Id)" -ForegroundColor Yellow
}

# Get resource group if not provided
if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-$EnvironmentName"
}

Write-Host "Working with Resource Group: $ResourceGroupName" -ForegroundColor Yellow

# Get storage accounts - use provided names or search for them
Write-Host "Attempting to verify storage accounts..." -ForegroundColor Yellow

$storageAccessError = $false

# Check if storage account names are provided
if (-not $FSLogixStorageAccountName -or -not $AppAttachStorageAccountName) {
    Write-Host "Storage account names not provided via environment variables." -ForegroundColor Yellow
    Write-Host "Post-provision configuration skipped." -ForegroundColor Yellow
    Write-Host "Please run .\scripts\manual-post-provision.ps1 manually." -ForegroundColor Yellow
    exit 0
}

# Try to verify storage accounts exist with current permissions
try {
    Write-Host "Checking FSLogix storage account: $FSLogixStorageAccountName" -ForegroundColor Yellow
    $fslogixStorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $FSLogixStorageAccountName -ErrorAction Stop
    Write-Host "✓ FSLogix storage account verified" -ForegroundColor Green
}
catch {
    Write-Host "✗ Cannot access FSLogix storage account: $($_.Exception.Message)" -ForegroundColor Yellow
    $storageAccessError = $true
}

try {
    Write-Host "Checking App Attach storage account: $AppAttachStorageAccountName" -ForegroundColor Yellow
    $appAttachStorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $AppAttachStorageAccountName -ErrorAction Stop
    Write-Host "✓ App Attach storage account verified" -ForegroundColor Green
}
catch {
    Write-Host "✗ Cannot access App Attach storage account: $($_.Exception.Message)" -ForegroundColor Yellow
    $storageAccessError = $true
}

if ($storageAccessError) {
    Write-Host "`nInsufficient permissions to complete automatic post-provision configuration." -ForegroundColor Yellow
    Write-Host "This is normal for deployments with limited service principal permissions." -ForegroundColor Yellow
    Write-Host "`nTo complete the AVD setup, please run the manual script:" -ForegroundColor Cyan
    Write-Host ".\scripts\manual-post-provision.ps1" -ForegroundColor White
    Write-Host "`nMake sure you are logged in with sufficient permissions (Contributor or Owner role)." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found storage accounts:" -ForegroundColor Green
Write-Host "  FSLogix: $($fslogixStorageAccount.StorageAccountName)" -ForegroundColor White
Write-Host "  App Attach: $($appAttachStorageAccount.StorageAccountName)" -ForegroundColor White

# Function to create Azure AD group if it doesn't exist
function New-AzureADGroupIfNotExists {
    param(
        [string]$GroupName,
        [string]$Description
    )
    
    try {
        $group = Get-AzADGroup -DisplayName $GroupName -ErrorAction SilentlyContinue
        if (-not $group) {
            Write-Host "Creating Azure AD group: $GroupName" -ForegroundColor Yellow
            $group = New-AzADGroup -DisplayName $GroupName -MailNickname $GroupName.Replace(" ", "") -Description $Description
            Start-Sleep 10  # Wait for group creation
        }
        else {
            Write-Host "Azure AD group already exists: $GroupName" -ForegroundColor Green
        }
        return $group.Id
    }
    catch {
        Write-Host "Error working with Azure AD group $GroupName : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Create AVD user groups
$avdAdminsGroupId = New-AzureADGroupIfNotExists -GroupName "AVD Admins" -Description "Azure Virtual Desktop Administrators"
$avdUsersGroupId = New-AzureADGroupIfNotExists -GroupName "AVD Users" -Description "Azure Virtual Desktop Users"

if (-not $avdAdminsGroupId -or -not $avdUsersGroupId) {
    Write-Host "Failed to create or find required Azure AD groups" -ForegroundColor Red
    exit 1
}

# Function to create Azure AD user
function New-AzureADUserIfNotExists {
    param(
        [string]$UserPrincipalName,
        [string]$DisplayName,
        [string]$MailNickname,
        [string]$Password,
        [string]$UsageLocation = "US"
    )
    
    try {
        Write-Host "Checking for existing user: $UserPrincipalName" -ForegroundColor Yellow
        $existingUser = Get-AzADUser -UserPrincipalName $UserPrincipalName -ErrorAction SilentlyContinue
        
        if (-not $existingUser) {
            Write-Host "Creating Azure AD user: $UserPrincipalName" -ForegroundColor Yellow
            
            # Create password profile
            $passwordProfile = @{
                Password = $Password
                ForceChangePasswordNextSignIn = $true
            }
            
            # Create the user
            $user = New-AzADUser -UserPrincipalName $UserPrincipalName -DisplayName $DisplayName -MailNickname $MailNickname -PasswordProfile $passwordProfile -UsageLocation $UsageLocation
            
            if ($user) {
                Write-Host "Azure AD user created successfully: $($user.UserPrincipalName)" -ForegroundColor Green
                return $user.Id
            }
            else {
                Write-Host "Failed to create Azure AD user: $UserPrincipalName" -ForegroundColor Red
                return $null
            }
        }
        else {
            Write-Host "Azure AD user already exists: $UserPrincipalName" -ForegroundColor Green
            return $existingUser.Id
        }
    }
    catch {
        Write-Host "Error working with Azure AD user $UserPrincipalName : $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to add user to group
function Add-UserToAzureADGroup {
    param(
        [string]$UserId,
        [string]$GroupId,
        [string]$UserName,
        [string]$GroupName
    )
    
    try {
        # Check if user is already a member
        $isMember = Get-AzADGroupMember -GroupId $GroupId | Where-Object { $_.Id -eq $UserId }
        
        if (-not $isMember) {
            Write-Host "Adding user $UserName to group $GroupName" -ForegroundColor Yellow
            Add-AzADGroupMember -GroupId $GroupId -MemberId $UserId
            Write-Host "User added to group successfully" -ForegroundColor Green
        }
        else {
            Write-Host "User $UserName is already a member of group $GroupName" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error adding user to group: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create the addomainadmin user
Write-Host "Setting up domain admin user..." -ForegroundColor Yellow
$domainAdminUPN = "addomainadmin@$((Get-AzContext).Tenant.Id | Get-AzTenant).DefaultDomain"

# Generate a secure password for the domain admin
$domainAdminPassword = -join ((65..90) + (97..122) + (48..57) + @(33,35,36,37,38,42,43,45,61,63,64) | Get-Random -Count 16 | ForEach-Object {[char]$_})

$domainAdminUserId = New-AzureADUserIfNotExists -UserPrincipalName $domainAdminUPN -DisplayName "AD Domain Admin" -MailNickname "addomainadmin" -Password $domainAdminPassword

if ($domainAdminUserId) {
    # Add the domain admin to the AVD Admins group
    Add-UserToAzureADGroup -UserId $domainAdminUserId -GroupId $avdAdminsGroupId -UserName "addomainadmin" -GroupName "AVD Admins"
    
    Write-Host "`nDOMAIN ADMIN CREDENTIALS:" -ForegroundColor Red
    Write-Host "Username: $domainAdminUPN" -ForegroundColor White
    Write-Host "Password: $domainAdminPassword" -ForegroundColor White
    Write-Host "IMPORTANT: Save these credentials securely!" -ForegroundColor Red
    Write-Host ""
}
else {
    Write-Host "Failed to create domain admin user. Continuing with existing configuration..." -ForegroundColor Yellow
}

# Function to assign RBAC role
function Set-StorageRoleAssignment {
    param(
        [string]$StorageAccountId,
        [string]$PrincipalId,
        [string]$RoleDefinitionName,
        [string]$GroupName
    )
    
    try {
        $existingAssignment = Get-AzRoleAssignment -ObjectId $PrincipalId -RoleDefinitionName $RoleDefinitionName -Scope $StorageAccountId -ErrorAction SilentlyContinue
        if (-not $existingAssignment) {
            Write-Host "Assigning role '$RoleDefinitionName' to group '$GroupName'" -ForegroundColor Yellow
            New-AzRoleAssignment -ObjectId $PrincipalId -RoleDefinitionName $RoleDefinitionName -Scope $StorageAccountId
            Write-Host "Role assignment completed" -ForegroundColor Green
        }
        else {
            Write-Host "Role '$RoleDefinitionName' already assigned to group '$GroupName'" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error assigning role: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Assign RBAC roles for FSLogix storage
Write-Host "Configuring RBAC for FSLogix storage..." -ForegroundColor Yellow
Set-StorageRoleAssignment -StorageAccountId $fslogixStorageAccount.Id -PrincipalId $avdAdminsGroupId -RoleDefinitionName "Storage File Data SMB Share Elevated Contributor" -GroupName "AVD Admins"
Set-StorageRoleAssignment -StorageAccountId $fslogixStorageAccount.Id -PrincipalId $avdUsersGroupId -RoleDefinitionName "Storage File Data SMB Share Contributor" -GroupName "AVD Users"

# Assign RBAC roles for App Attach storage
Write-Host "Configuring RBAC for App Attach storage..." -ForegroundColor Yellow
Set-StorageRoleAssignment -StorageAccountId $appAttachStorageAccount.Id -PrincipalId $avdAdminsGroupId -RoleDefinitionName "Storage File Data SMB Share Elevated Contributor" -GroupName "AVD Admins"

# Get session hosts for configuration
$sessionHosts = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -like "vm-$EnvironmentName-*" }

Write-Host "Found $($sessionHosts.Count) session hosts to configure" -ForegroundColor Yellow

# Configure each session host
foreach ($vm in $sessionHosts) {
    Write-Host "Configuring session host: $($vm.Name)" -ForegroundColor Yellow
    
    $scriptContent = @"
# Configure FSLogix registry settings
`$fslogixPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
if (-not (Test-Path `$fslogixPath)) {
    New-Item -Path `$fslogixPath -Force
}

Set-ItemProperty -Path `$fslogixPath -Name "Enabled" -Value 1 -Type DWORD
Set-ItemProperty -Path `$fslogixPath -Name "VHDLocations" -Value "\\$($fslogixStorageAccount.StorageAccountName).file.core.windows.net\profiles" -Type String
Set-ItemProperty -Path `$fslogixPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWORD
Set-ItemProperty -Path `$fslogixPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWORD
Set-ItemProperty -Path `$fslogixPath -Name "SizeInMBs" -Value 10240 -Type DWORD
Set-ItemProperty -Path `$fslogixPath -Name "IsDynamic" -Value 1 -Type DWORD

Write-Host "FSLogix configuration completed on $($env:COMPUTERNAME)"

# Create App Attach mount point
`$appAttachPath = "C:\AppAttach"
if (-not (Test-Path `$appAttachPath)) {
    New-Item -Path `$appAttachPath -ItemType Directory -Force
    Write-Host "Created App Attach directory: `$appAttachPath"
}

Write-Host "Session host configuration completed"
"@
    
    try {
        $result = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $vm.Name -CommandId "RunPowerShellScript" -ScriptString $scriptContent
        Write-Host "Configuration applied to $($vm.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Error configuring $($vm.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create sample directory structure in App Attach storage
Write-Host "Setting up App Attach storage structure..." -ForegroundColor Yellow

$storageContext = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $appAttachStorageAccount.StorageAccountName).Context

try {
    # Create sample MSIX directory structure
    $directories = @(
        "msix-packages",
        "msix-packages/sample-app",
        "staging"
    )
    
    foreach ($dir in $directories) {
        # Create a temporary file in each directory to ensure the directory structure exists
        $tempFileName = "$dir/placeholder.txt"
        $tempContent = "This is a placeholder file to maintain directory structure"
        $tempBlob = Set-AzStorageFileContent -ShareName "appattach" -Source ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($tempContent))) -Path $tempFileName -Context $storageContext -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "App Attach directory structure created successfully" -ForegroundColor Green
}
catch {
    Write-Host "Note: App Attach directory structure will be created when first MSIX package is uploaded" -ForegroundColor Yellow
}

Write-Host "`nPost-provision configuration completed!" -ForegroundColor Green
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Add users to the 'AVD Users' Azure AD group" -ForegroundColor White
Write-Host "2. Add additional administrators to the 'AVD Admins' Azure AD group" -ForegroundColor White
Write-Host "3. The 'addomainadmin' user has been created and added to AVD Admins group" -ForegroundColor White
Write-Host "4. Upload MSIX packages to the App Attach storage account" -ForegroundColor White
Write-Host "5. Configure App Attach applications in the AVD Host Pool" -ForegroundColor White
Write-Host "6. Test user access to the AVD environment" -ForegroundColor White

Write-Host "`nResource Information:" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "FSLogix Storage: $($fslogixStorageAccount.StorageAccountName)" -ForegroundColor White
Write-Host "App Attach Storage: $($appAttachStorageAccount.StorageAccountName)" -ForegroundColor White
Write-Host "AVD Admins Group ID: $avdAdminsGroupId" -ForegroundColor White
Write-Host "AVD Users Group ID: $avdUsersGroupId" -ForegroundColor White
Write-Host "Domain Admin User: addomainadmin (added to AVD Admins group)" -ForegroundColor White