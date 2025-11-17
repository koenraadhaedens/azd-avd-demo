# Test Domain Extraction Logic
# This script tests the same logic used in the Bicep template for extracting domain from username

param(
    [Parameter(Mandatory=$true)]
    [string]$Username
)

Write-Host "Testing domain extraction for username: '$Username'" -ForegroundColor Cyan
Write-Host ""

# Mimic the Bicep logic
if ($Username -like "*\*") {
    # Domain\Username format
    $domain = $Username.Split('\')[0]
    Write-Host "Format: Domain\Username" -ForegroundColor Yellow
    Write-Host "Extracted domain: '$domain'" -ForegroundColor Green
} elseif ($Username -like "*@*") {
    # UPN format
    $domain = $Username.Split('@')[1]
    Write-Host "Format: UPN (username@domain)" -ForegroundColor Yellow
    Write-Host "Extracted domain: '$domain'" -ForegroundColor Green
} else {
    # No domain found
    Write-Host "Format: Username only (no domain detected)" -ForegroundColor Yellow
    Write-Host "Will use default: 'contoso.local'" -ForegroundColor Red
    $domain = "contoso.local"
}

Write-Host ""
Write-Host "Recommended environment variable:" -ForegroundColor Cyan
Write-Host "  azd env set DOMAIN_JOIN_USERNAME `"$Username`"" -ForegroundColor White
Write-Host ""
Write-Host "Domain that will be used: $domain" -ForegroundColor Green