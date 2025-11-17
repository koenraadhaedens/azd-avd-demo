# DNS Server Detection Script
# This script helps identify the DNS server IP for your domain

param(
    [Parameter(Mandatory=$false)]
    [string]$DomainName
)

Write-Host "=== DNS Server Detection Tool ===" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrEmpty($DomainName)) {
    # Try to get domain from current machine
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
        if ($computerSystem.PartOfDomain) {
            $DomainName = $computerSystem.Domain
            Write-Host "Detected current domain: $DomainName" -ForegroundColor Green
        } else {
            Write-Host "This machine is not domain-joined. Please provide domain name:" -ForegroundColor Yellow
            Write-Host "  .\scripts\detect-dns-server.ps1 -DomainName 'your.domain.com'" -ForegroundColor White
            exit 1
        }
    } catch {
        Write-Host "Could not detect domain. Please provide domain name as parameter." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Analyzing DNS configuration for domain: $DomainName" -ForegroundColor Yellow
Write-Host ""

# Method 1: Get DNS servers from network adapters
Write-Host "1. Network Adapter DNS Servers:" -ForegroundColor Yellow
try {
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    foreach ($adapter in $adapters) {
        $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
        if ($dnsServers.ServerAddresses) {
            Write-Host "   Interface: $($adapter.Name)" -ForegroundColor Cyan
            foreach ($dns in $dnsServers.ServerAddresses) {
                Write-Host "   → $dns" -ForegroundColor Green
            }
        }
    }
} catch {
    Write-Host "   Could not retrieve network adapter DNS settings" -ForegroundColor Red
}

Write-Host ""

# Method 2: Resolve domain controllers via DNS
Write-Host "2. Domain Controllers for $DomainName :" -ForegroundColor Yellow
try {
    $dcRecords = Resolve-DnsName "_ldap._tcp.$DomainName" -Type SRV -ErrorAction Stop
    foreach ($dc in $dcRecords) {
        Write-Host "   DC: $($dc.NameTarget) (Priority: $($dc.Priority))" -ForegroundColor Green
        
        # Try to resolve the IP of each DC
        try {
            $dcIp = Resolve-DnsName $dc.NameTarget -Type A -ErrorAction Stop
            Write-Host "      IP: $($dcIp.IPAddress)" -ForegroundColor Cyan
        } catch {
            Write-Host "      IP: Could not resolve" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "   Could not find domain controllers for $DomainName" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Method 3: Check current DNS cache
Write-Host "3. DNS Cache entries for $DomainName :" -ForegroundColor Yellow
try {
    $cacheEntries = Get-DnsClientCache | Where-Object {$_.Name -like "*$DomainName*"} | Select-Object Name, Data -Unique
    if ($cacheEntries) {
        foreach ($entry in $cacheEntries) {
            Write-Host "   $($entry.Name) → $($entry.Data)" -ForegroundColor Green
        }
    } else {
        Write-Host "   No cached entries found for $DomainName" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   Could not retrieve DNS cache" -ForegroundColor Red
}

Write-Host ""

# Method 4: Test common DNS ports
Write-Host "4. Testing DNS connectivity:" -ForegroundColor Yellow
$commonDnsServers = @()

# Get unique DNS servers from network adapters
$adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
foreach ($adapter in $adapters) {
    $dnsServers = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    if ($dnsServers.ServerAddresses) {
        $commonDnsServers += $dnsServers.ServerAddresses
    }
}

$commonDnsServers = $commonDnsServers | Select-Object -Unique

foreach ($dnsServer in $commonDnsServers) {
    Write-Host "   Testing $dnsServer ..." -ForegroundColor Cyan
    try {
        $testResult = Test-NetConnection -ComputerName $dnsServer -Port 53 -WarningAction SilentlyContinue
        if ($testResult.TcpTestSucceeded) {
            Write-Host "   ✓ $dnsServer - Port 53 accessible" -ForegroundColor Green
            
            # Test DNS query
            try {
                $queryResult = Resolve-DnsName $DomainName -Server $dnsServer -ErrorAction Stop
                Write-Host "   ✓ $dnsServer - Can resolve $DomainName" -ForegroundColor Green
            } catch {
                Write-Host "   ⚠ $dnsServer - Port accessible but cannot resolve $DomainName" -ForegroundColor Yellow
            }
        } else {
            Write-Host "   ✗ $dnsServer - Port 53 not accessible" -ForegroundColor Red
        }
    } catch {
        Write-Host "   ✗ $dnsServer - Connection failed" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Recommendations ===" -ForegroundColor Cyan

if ($commonDnsServers) {
    Write-Host "Based on the analysis above, consider using one of these DNS servers:" -ForegroundColor Green
    foreach ($server in $commonDnsServers) {
        Write-Host "  azd env set DNS_SERVER_IP `"$server`"" -ForegroundColor White
    }
} else {
    Write-Host "No suitable DNS servers found. You may need to:" -ForegroundColor Yellow
    Write-Host "• Check your network configuration" -ForegroundColor White
    Write-Host "• Ensure this machine can reach your domain controllers" -ForegroundColor White
    Write-Host "• Contact your network administrator for DNS server information" -ForegroundColor White
}

Write-Host ""
Write-Host "Note: Use the DNS server IP that can resolve your domain name for Azure VNet configuration." -ForegroundColor Cyan