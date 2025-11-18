#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$FileShareName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$false)]
    [string]$AdminGroupName = "AAD DC Administrators",
    
    [Parameter(Mandatory=$false)]
    [string]$UserGroupName = "AAD DC Users"
)

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force

# Create log directory
$LogPath = "C:\AVDDeployment"
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force
}

# Start logging
Start-Transcript -Path "$LogPath\SetFSLogixNTFSPermissions.log" -Force

Write-Host "Starting FSLogix NTFS permissions configuration..." -ForegroundColor Green
Write-Host "Storage Account: $StorageAccountName"
Write-Host "File Share: $FileShareName"
Write-Host "Domain: $DomainName"

try {
    # Get storage account key for authentication
    Write-Host "Connecting to Azure Storage..." -ForegroundColor Yellow
    
    # Mount the file share using storage account key
    $uncPath = "\\$StorageAccountName.file.core.windows.net\$FileShareName"
    $driveLetter = "Z:"
    
    Write-Host "Mapping network drive to $uncPath..." -ForegroundColor Yellow
    
    # Try to map the drive (this will use Kerberos authentication if domain-joined)
    try {
        New-PSDrive -Name "FSLogixShare" -PSProvider FileSystem -Root $uncPath -Persist -ErrorAction Stop
        $mountPath = "$($driveLetter)"
    }
    catch {
        Write-Warning "Failed to mount drive with Kerberos. Error: $($_.Exception.Message)"
        Write-Host "Attempting to access UNC path directly..." -ForegroundColor Yellow
        $mountPath = $uncPath
    }
    
    Write-Host "Setting NTFS permissions on FSLogix share..." -ForegroundColor Yellow
    
    # Define the permissions structure for FSLogix
    $permissions = @(
        @{
            Principal = "BUILTIN\Administrators"
            Rights = "FullControl"
            Inheritance = "ContainerInherit,ObjectInherit"
            Propagation = "None"
        },
        @{
            Principal = "$DomainName\$AdminGroupName"
            Rights = "FullControl"
            Inheritance = "ContainerInherit,ObjectInherit"
            Propagation = "None"
        },
        @{
            Principal = "$DomainName\$UserGroupName"
            Rights = "Modify"
            Inheritance = "ContainerInherit,ObjectInherit"
            Propagation = "None"
        },
        @{
            Principal = "CREATOR OWNER"
            Rights = "FullControl"
            Inheritance = "ContainerInherit,ObjectInherit"
            Propagation = "InheritOnly"
        }
    )
    
    # Get current ACL
    $acl = Get-Acl -Path $mountPath
    
    # Remove existing permissions (except inherited ones)
    Write-Host "Removing existing explicit permissions..." -ForegroundColor Yellow
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance and remove inherited permissions
    
    # Add new permissions
    foreach ($permission in $permissions) {
        Write-Host "Setting permissions for $($permission.Principal)..." -ForegroundColor Yellow
        
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $permission.Principal,
            $permission.Rights,
            $permission.Inheritance,
            $permission.Propagation,
            "Allow"
        )
        
        $acl.SetAccessRule($accessRule)
    }
    
    # Apply the ACL
    Write-Host "Applying NTFS permissions..." -ForegroundColor Yellow
    Set-Acl -Path $mountPath -AclObject $acl
    
    Write-Host "✓ NTFS permissions configured successfully!" -ForegroundColor Green
    
    # Verify permissions
    Write-Host "Verifying permissions..." -ForegroundColor Yellow
    $finalAcl = Get-Acl -Path $mountPath
    Write-Host "Current permissions on $mountPath:" -ForegroundColor Cyan
    foreach ($access in $finalAcl.Access) {
        Write-Host "  $($access.IdentityReference): $($access.FileSystemRights) ($($access.AccessControlType))" -ForegroundColor White
    }
    
    # Create sample FSLogix folder structure
    Write-Host "Creating FSLogix folder structure..." -ForegroundColor Yellow
    $fslogixFolders = @("Profiles", "ODFC", "Search")
    
    foreach ($folder in $fslogixFolders) {
        $folderPath = Join-Path $mountPath $folder
        if (!(Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force
            Write-Host "Created folder: $folderPath" -ForegroundColor Green
            
            # Set specific permissions on each folder
            $folderAcl = Get-Acl -Path $folderPath
            $folderAcl.SetAccessRuleProtection($false, $true)  # Enable inheritance
            Set-Acl -Path $folderPath -AclObject $folderAcl
        }
    }
    
    Write-Host "✓ FSLogix folder structure created successfully!" -ForegroundColor Green
    
}
catch {
    Write-Error "Failed to configure NTFS permissions: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.Exception.StackTrace)"
    
    # Additional troubleshooting information
    Write-Host "Troubleshooting information:" -ForegroundColor Yellow
    Write-Host "Current user: $env:USERNAME" -ForegroundColor White
    Write-Host "Domain: $env:USERDOMAIN" -ForegroundColor White
    Write-Host "Computer name: $env:COMPUTERNAME" -ForegroundColor White
    
    # Test domain connectivity
    try {
        $domainController = (Get-ADDomainController -Domain $DomainName -ErrorAction SilentlyContinue).HostName
        if ($domainController) {
            Write-Host "Domain controller: $domainController" -ForegroundColor White
        }
    }
    catch {
        Write-Warning "Could not query domain controller: $($_.Exception.Message)"
    }
}
finally {
    # Clean up mapped drive
    try {
        if (Get-PSDrive -Name "FSLogixShare" -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name "FSLogixShare" -Force
            Write-Host "Cleaned up mapped drive" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to clean up mapped drive: $($_.Exception.Message)"
    }
}

Write-Host "FSLogix NTFS permissions configuration completed!" -ForegroundColor Green

Stop-Transcript