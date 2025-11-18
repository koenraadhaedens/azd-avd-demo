#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Validates FSLogix configuration and tests profile functionality

.DESCRIPTION
    This script validates the complete FSLogix setup including:
    - Storage account accessibility
    - NTFS permissions
    - FSLogix registry settings
    - Profile creation test

.PARAMETER StorageAccountName
    Name of the FSLogix storage account

.PARAMETER FileShareName
    Name of the FSLogix file share

.PARAMETER DomainName
    Azure AD DS domain name

.PARAMETER TestUserSAM
    (Optional) Test user SAM account name for profile creation test

.EXAMPLE
    .\Test-FSLogixConfiguration.ps1 -StorageAccountName "stfslogix123" -FileShareName "profiles" -DomainName "contoso.com"

.EXAMPLE
    .\Test-FSLogixConfiguration.ps1 -StorageAccountName "stfslogix123" -FileShareName "profiles" -DomainName "contoso.com" -TestUserSAM "testuser"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$FileShareName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$false)]
    [string]$TestUserSAM
)

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force

# Create log directory
$LogPath = "C:\AVDDeployment"
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force
}

# Start logging
Start-Transcript -Path "$LogPath\TestFSLogix.log" -Force

Write-Host "=== FSLogix Configuration Validation ===" -ForegroundColor Green
Write-Host "Storage Account: $StorageAccountName"
Write-Host "File Share: $FileShareName"
Write-Host "Domain: $DomainName"
Write-Host "Test User: $(if($TestUserSAM) { $TestUserSAM } else { 'None specified' })"
Write-Host ""

$testResults = @{}
$overallSuccess = $true

# Test 1: Storage Connectivity
Write-Host "Test 1: Storage Connectivity" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

try {
    $storageAccountFqdn = "$StorageAccountName.file.core.windows.net"
    $uncPath = "\\$storageAccountFqdn\$FileShareName"
    
    Write-Host "Testing connectivity to: $storageAccountFqdn" -ForegroundColor Yellow
    
    $connectionTest = Test-NetConnection -ComputerName $storageAccountFqdn -Port 445 -WarningAction SilentlyContinue
    
    if ($connectionTest.TcpTestSucceeded) {
        Write-Host "✓ SMB connectivity successful (Port 445 open)" -ForegroundColor Green
        $testResults["StorageConnectivity"] = "PASS"
    }
    else {
        Write-Host "✗ SMB connectivity failed (Port 445 blocked)" -ForegroundColor Red
        $testResults["StorageConnectivity"] = "FAIL"
        $overallSuccess = $false
    }
}
catch {
    Write-Host "✗ Storage connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults["StorageConnectivity"] = "FAIL"
    $overallSuccess = $false
}

Write-Host ""

# Test 2: File Share Access
Write-Host "Test 2: File Share Access" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan

try {
    Write-Host "Testing access to: $uncPath" -ForegroundColor Yellow
    
    if (Test-Path $uncPath) {
        Write-Host "✓ File share is accessible" -ForegroundColor Green
        
        # Test write permissions
        $testFile = Join-Path $uncPath "fslogix-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').tmp"
        try {
            "FSLogix Test File" | Out-File -FilePath $testFile -Force
            
            if (Test-Path $testFile) {
                Write-Host "✓ Write permissions confirmed" -ForegroundColor Green
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                $testResults["FileShareAccess"] = "PASS"
            }
            else {
                Write-Host "✗ Write test failed" -ForegroundColor Red
                $testResults["FileShareAccess"] = "FAIL"
                $overallSuccess = $false
            }
        }
        catch {
            Write-Host "✗ Write permissions test failed: $($_.Exception.Message)" -ForegroundColor Red
            $testResults["FileShareAccess"] = "FAIL"
            $overallSuccess = $false
        }
    }
    else {
        Write-Host "✗ File share is not accessible" -ForegroundColor Red
        $testResults["FileShareAccess"] = "FAIL"
        $overallSuccess = $false
    }
}
catch {
    Write-Host "✗ File share access test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults["FileShareAccess"] = "FAIL"
    $overallSuccess = $false
}

Write-Host ""

# Test 3: FSLogix Registry Configuration
Write-Host "Test 3: FSLogix Registry Configuration" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

try {
    $fslogixRegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
    
    if (Test-Path $fslogixRegPath) {
        Write-Host "✓ FSLogix registry key exists" -ForegroundColor Green
        
        $requiredSettings = @{
            "Enabled" = 1
            "VHDLocations" = $uncPath
            "VolumeType" = "VHDX"
            "SizeInMBs" = 10240
            "IsDynamic" = 1
        }
        
        $settingsValid = $true
        foreach ($setting in $requiredSettings.Keys) {
            try {
                $value = Get-ItemProperty -Path $fslogixRegPath -Name $setting -ErrorAction Stop
                $actualValue = $value.$setting
                $expectedValue = $requiredSettings[$setting]
                
                if ($actualValue -eq $expectedValue) {
                    Write-Host "✓ $setting = $actualValue" -ForegroundColor Green
                }
                else {
                    Write-Host "✗ $setting = $actualValue (expected: $expectedValue)" -ForegroundColor Red
                    $settingsValid = $false
                }
            }
            catch {
                Write-Host "✗ $setting not configured" -ForegroundColor Red
                $settingsValid = $false
            }
        }
        
        if ($settingsValid) {
            $testResults["FSLogixRegistry"] = "PASS"
        }
        else {
            $testResults["FSLogixRegistry"] = "FAIL"
            $overallSuccess = $false
        }
    }
    else {
        Write-Host "✗ FSLogix registry key not found" -ForegroundColor Red
        $testResults["FSLogixRegistry"] = "FAIL"
        $overallSuccess = $false
    }
}
catch {
    Write-Host "✗ FSLogix registry test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults["FSLogixRegistry"] = "FAIL"
    $overallSuccess = $false
}

Write-Host ""

# Test 4: NTFS Permissions
Write-Host "Test 4: NTFS Permissions" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

try {
    if (Test-Path $uncPath) {
        Write-Host "Checking NTFS permissions on: $uncPath" -ForegroundColor Yellow
        
        $acl = Get-Acl -Path $uncPath
        $permissions = $acl.Access
        
        $expectedGroups = @(
            "$DomainName\AAD DC Administrators",
            "$DomainName\AAD DC Users",
            "CREATOR OWNER"
        )
        
        $permissionsValid = $true
        foreach ($group in $expectedGroups) {
            $groupPermission = $permissions | Where-Object { $_.IdentityReference -eq $group }
            
            if ($groupPermission) {
                Write-Host "✓ Found permissions for: $group" -ForegroundColor Green
                Write-Host "  Rights: $($groupPermission.FileSystemRights)" -ForegroundColor White
            }
            else {
                Write-Host "✗ Missing permissions for: $group" -ForegroundColor Red
                $permissionsValid = $false
            }
        }
        
        if ($permissionsValid) {
            $testResults["NTFSPermissions"] = "PASS"
        }
        else {
            $testResults["NTFSPermissions"] = "FAIL"
            $overallSuccess = $false
        }
    }
    else {
        Write-Host "✗ Cannot check NTFS permissions - file share not accessible" -ForegroundColor Red
        $testResults["NTFSPermissions"] = "FAIL"
        $overallSuccess = $false
    }
}
catch {
    Write-Host "✗ NTFS permissions test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults["NTFSPermissions"] = "FAIL"
    $overallSuccess = $false
}

Write-Host ""

# Test 5: Domain Authentication
Write-Host "Test 5: Domain Authentication" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

try {
    $computerInfo = Get-ComputerInfo
    
    if ($computerInfo.PartOfDomain) {
        $currentDomain = $computerInfo.Domain
        
        if ($currentDomain -eq $DomainName) {
            Write-Host "✓ Computer is joined to correct domain: $currentDomain" -ForegroundColor Green
            $testResults["DomainAuth"] = "PASS"
        }
        else {
            Write-Host "✗ Computer is joined to wrong domain: $currentDomain (expected: $DomainName)" -ForegroundColor Red
            $testResults["DomainAuth"] = "FAIL"
            $overallSuccess = $false
        }
    }
    else {
        Write-Host "✗ Computer is not domain joined" -ForegroundColor Red
        Write-Host "  Current workgroup: $($computerInfo.Workgroup)" -ForegroundColor White
        $testResults["DomainAuth"] = "FAIL"
        $overallSuccess = $false
    }
}
catch {
    Write-Host "✗ Domain authentication test failed: $($_.Exception.Message)" -ForegroundColor Red
    $testResults["DomainAuth"] = "FAIL"
    $overallSuccess = $false
}

Write-Host ""

# Test 6: Profile Creation Test (Optional)
if ($TestUserSAM) {
    Write-Host "Test 6: Profile Creation Test" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    
    try {
        $profilePath = Join-Path $uncPath $TestUserSAM
        
        Write-Host "Testing profile creation for user: $TestUserSAM" -ForegroundColor Yellow
        Write-Host "Expected profile path: $profilePath" -ForegroundColor White
        
        if (Test-Path $profilePath) {
            Write-Host "✓ User profile directory exists" -ForegroundColor Green
            
            # Check for VHDX files
            $vhdxFiles = Get-ChildItem -Path $profilePath -Filter "*.vhdx" -ErrorAction SilentlyContinue
            
            if ($vhdxFiles) {
                Write-Host "✓ Profile VHDX files found:" -ForegroundColor Green
                foreach ($vhdx in $vhdxFiles) {
                    Write-Host "  - $($vhdx.Name) ($([math]::Round($vhdx.Length/1MB, 2)) MB)" -ForegroundColor White
                }
                $testResults["ProfileCreation"] = "PASS"
            }
            else {
                Write-Host "! Profile directory exists but no VHDX files found" -ForegroundColor Yellow
                Write-Host "  This may be normal if the user hasn't logged in recently" -ForegroundColor Yellow
                $testResults["ProfileCreation"] = "PARTIAL"
            }
        }
        else {
            Write-Host "! User profile directory does not exist" -ForegroundColor Yellow
            Write-Host "  This is normal if the user hasn't logged in yet" -ForegroundColor Yellow
            $testResults["ProfileCreation"] = "NOTFOUND"
        }
    }
    catch {
        Write-Host "✗ Profile creation test failed: $($_.Exception.Message)" -ForegroundColor Red
        $testResults["ProfileCreation"] = "FAIL"
    }
    
    Write-Host ""
}

# Summary
Write-Host "=== Test Results Summary ===" -ForegroundColor Green
Write-Host "============================" -ForegroundColor Green

foreach ($test in $testResults.Keys) {
    $result = $testResults[$test]
    $color = switch ($result) {
        "PASS" { "Green" }
        "PARTIAL" { "Yellow" }
        "NOTFOUND" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }
    
    Write-Host "$test`: $result" -ForegroundColor $color
}

Write-Host ""

if ($overallSuccess) {
    Write-Host "✓ Overall Result: FSLogix configuration is valid!" -ForegroundColor Green
}
else {
    Write-Host "✗ Overall Result: FSLogix configuration has issues that need attention" -ForegroundColor Red
    Write-Host ""
    Write-Host "Recommended actions:" -ForegroundColor Yellow
    Write-Host "1. Check network connectivity and firewall settings" -ForegroundColor White
    Write-Host "2. Verify Azure AD DS is properly configured" -ForegroundColor White
    Write-Host "3. Run Set-FSLogixNTFSPermissions.ps1 to fix permissions" -ForegroundColor White
    Write-Host "4. Check FSLogix installation and registry settings" -ForegroundColor White
}

Write-Host ""
Write-Host "Log file location: $LogPath\TestFSLogix.log" -ForegroundColor Cyan

Stop-Transcript