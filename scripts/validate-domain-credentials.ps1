# Validate Domain Join Credentials Script
# This script helps validate that the domain join credentials work correctly

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$true)]
    [string]$Password,
    
    [Parameter(Mandatory=$false)]
    [string]$DnsServerIp
)

Write-Host "=== Domain Join Credentials Validation ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Domain accessibility
Write-Host "1. Testing domain accessibility..." -ForegroundColor Yellow
try {
    $domain = Get-ADDomain -Server $DomainName -ErrorAction Stop
    Write-Host "   ✓ Domain '$($domain.DNSRoot)' is accessible" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Cannot access domain '$DomainName'" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: Credential validation
Write-Host "2. Testing credentials..." -ForegroundColor Yellow
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)

try {
    $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainName)
    $isValid = $context.ValidateCredentials($Username, $Password)
    
    if ($isValid) {
        Write-Host "   ✓ Credentials are valid" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Invalid credentials" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "   ✗ Cannot validate credentials" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 3: Check user permissions (attempt to query computer objects)
Write-Host "3. Testing domain join permissions..." -ForegroundColor Yellow
try {
    # Try to search for computer objects to test read permissions
    $searcher = New-Object System.DirectoryServices.DirectorySearcher
    $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainName", $Username, $Password)
    $searcher.Filter = "(objectClass=computer)"
    $searcher.PageSize = 1
    $searcher.SearchScope = "Subtree"
    
    $results = $searcher.FindAll()
    Write-Host "   ✓ User can query computer objects in domain" -ForegroundColor Green
    
} catch {
    Write-Host "   ⚠ Warning: Cannot query computer objects - this might affect domain join" -ForegroundColor Yellow
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Test 4: DNS resolution
Write-Host "4. Testing DNS resolution for domain..." -ForegroundColor Yellow

# Test specific DNS server if provided
if ($DnsServerIp) {
    Write-Host "   Testing DNS server: $DnsServerIp" -ForegroundColor Cyan
    try {
        $dnsResult = Resolve-DnsName $DomainName -Server $DnsServerIp -ErrorAction Stop
        Write-Host "   ✓ DNS resolution successful using '$DnsServerIp'" -ForegroundColor Green
        
        # Test domain controller resolution via specific DNS server
        try {
            $dcResult = Resolve-DnsName "_ldap._tcp.$DomainName" -Type SRV -Server $DnsServerIp -ErrorAction Stop
            Write-Host "   ✓ Found $($dcResult.Count) domain controller(s) via '$DnsServerIp'" -ForegroundColor Green
        } catch {
            Write-Host "   ⚠ Warning: Cannot resolve domain controllers via SRV record using '$DnsServerIp'" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "   ✗ DNS resolution failed using server '$DnsServerIp'" -ForegroundColor Red
        Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    # Use system DNS
    try {
        $dnsResult = Resolve-DnsName $DomainName -ErrorAction Stop
        Write-Host "   ✓ DNS resolution successful for '$DomainName' (using system DNS)" -ForegroundColor Green
        
        # Try to resolve domain controllers
        try {
            $dcResult = Resolve-DnsName "_ldap._tcp.$DomainName" -Type SRV -ErrorAction Stop
            Write-Host "   ✓ Found $($dcResult.Count) domain controller(s)" -ForegroundColor Green
        } catch {
            Write-Host "   ⚠ Warning: Cannot resolve domain controllers via SRV record" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "   ✗ DNS resolution failed for '$DomainName'" -ForegroundColor Red
        Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Validation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "If all tests passed, you can proceed with the deployment." -ForegroundColor Green
Write-Host "If any tests failed, please resolve the issues before running 'azd up'." -ForegroundColor Yellow
Write-Host ""
Write-Host "To set environment variables for deployment:" -ForegroundColor Cyan
Write-Host "  azd env set DOMAIN_JOIN_USERNAME `"$Username`"" -ForegroundColor White
Write-Host "  azd env set DOMAIN_JOIN_PASSWORD `"$Password`"" -ForegroundColor White
if ($DnsServerIp) {
    Write-Host "  azd env set DNS_SERVER_IP `"$DnsServerIp`"" -ForegroundColor White
}
Write-Host ""
Write-Host "Note: Domain name will be automatically extracted from the username" -ForegroundColor Yellow