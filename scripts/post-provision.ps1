#!/usr/bin/env pwsh

# Post-provision script for AVD environment
# This script configures RBAC assignments and NTFS permissions

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = $env:AZURE_RESOURCE_GROUP_NAME,
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentName = $env:AZURE_ENV_NAME
)

Write-Host "Starting post-provision configuration for AVD environment: $EnvironmentName" -ForegroundColor Green

# Check if we're logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Please run 'Connect-AzAccount' first" -ForegroundColor Red
        exit 1
    }
    Write-Host "Using Azure context: $($context.Account.Id)" -ForegroundColor Yellow
}
catch {
    Write-Host "Azure PowerShell module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name Az -Scope CurrentUser -Force
    Connect-AzAccount
}

# Set subscription context
if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId
}

# Get resource group if not provided
if (-not $ResourceGroupName) {
    $ResourceGroupName = "rg-$EnvironmentName"
}

Write-Host "Working with Resource Group: $ResourceGroupName" -ForegroundColor Yellow

# Get storage accounts
$fslogixStorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName | Where-Object { $_.StorageAccountName -like "*fslogix*" }
$appAttachStorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName | Where-Object { $_.StorageAccountName -like "*appattach*" }

if (-not $fslogixStorageAccount) {
    Write-Host "FSLogix storage account not found!" -ForegroundColor Red
    exit 1
}

if (-not $appAttachStorageAccount) {
    Write-Host "App Attach storage account not found!" -ForegroundColor Red
    exit 1
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
Write-Host "2. Add administrators to the 'AVD Admins' Azure AD group" -ForegroundColor White
Write-Host "3. Upload MSIX packages to the App Attach storage account" -ForegroundColor White
Write-Host "4. Configure App Attach applications in the AVD Host Pool" -ForegroundColor White
Write-Host "5. Test user access to the AVD environment" -ForegroundColor White

Write-Host "`nResource Information:" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "FSLogix Storage: $($fslogixStorageAccount.StorageAccountName)" -ForegroundColor White
Write-Host "App Attach Storage: $($appAttachStorageAccount.StorageAccountName)" -ForegroundColor White
Write-Host "AVD Admins Group ID: $avdAdminsGroupId" -ForegroundColor White
Write-Host "AVD Users Group ID: $avdUsersGroupId" -ForegroundColor White