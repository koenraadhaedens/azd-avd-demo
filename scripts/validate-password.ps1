#!/usr/bin/env pwsh

# Password Validation Script for Azure AD Domain Services Deployment
# This script validates that passwords are compatible with deployment scripts

param(
    [Parameter(Mandatory=$false)]
    [string]$TestPassword
)

Write-Host "=== Password Validation for Azure AD DS Deployment ===" -ForegroundColor Cyan

if (-not $TestPassword) {
    Write-Host "Usage: .\validate-password.ps1 -TestPassword 'YourPassword123!'" -ForegroundColor Yellow
    Write-Host "This script validates password compatibility with deployment scripts." -ForegroundColor Gray
    exit 0
}

Write-Host "`nTesting password compatibility..." -ForegroundColor Yellow

# Test for problematic patterns
$issues = @()

# Check for PowerShell time units (ms, s, m, h, d)
if ($TestPassword -match '\d+(ms|s|m|h|d)\b') {
    $issues += "Contains time unit pattern (e.g., '123ms', '5s') - PowerShell may interpret as time measurements"
}

# Check for PowerShell operators
$powershellOperators = @('&', '|', ';', '`', '$', '(', ')', '{', '}', '[', ']')
foreach ($operator in $powershellOperators) {
    if ($TestPassword.Contains($operator)) {
        $issues += "Contains PowerShell operator '$operator' - may cause command interpretation issues"
    }
}

# Check for whitespace
if ($TestPassword -match '\s') {
    $issues += "Contains whitespace - may cause parameter parsing issues"
}

# Check for quotes
if ($TestPassword.Contains('"') -or $TestPassword.Contains("'")) {
    $issues += "Contains quotes - may cause string parsing issues"
}

# Check basic Azure AD complexity requirements
$hasLower = $TestPassword -cmatch '[a-z]'
$hasUpper = $TestPassword -cmatch '[A-Z]'
$hasNumber = $TestPassword -match '\d'
$hasSpecial = $TestPassword -match '[^a-zA-Z0-9]'
$isLongEnough = $TestPassword.Length -ge 8

Write-Host "`n=== Azure AD Complexity Requirements ===" -ForegroundColor Cyan

if ($hasLower) {
    Write-Host "✓ Contains lowercase letters" -ForegroundColor Green
} else {
    Write-Host "✗ Missing lowercase letters" -ForegroundColor Red
    $issues += "Does not meet Azure AD requirement: must contain lowercase letters"
}

if ($hasUpper) {
    Write-Host "✓ Contains uppercase letters" -ForegroundColor Green
} else {
    Write-Host "✗ Missing uppercase letters" -ForegroundColor Red
    $issues += "Does not meet Azure AD requirement: must contain uppercase letters"
}

if ($hasNumber) {
    Write-Host "✓ Contains numbers" -ForegroundColor Green
} else {
    Write-Host "✗ Missing numbers" -ForegroundColor Red
    $issues += "Does not meet Azure AD requirement: must contain numbers"
}

if ($hasSpecial) {
    Write-Host "✓ Contains special characters" -ForegroundColor Green
} else {
    Write-Host "✗ Missing special characters" -ForegroundColor Red
    $issues += "Does not meet Azure AD requirement: must contain special characters"
}

if ($isLongEnough) {
    Write-Host "✓ At least 8 characters long" -ForegroundColor Green
} else {
    Write-Host "✗ Less than 8 characters" -ForegroundColor Red
    $issues += "Does not meet Azure AD requirement: must be at least 8 characters long"
}

Write-Host "`n=== Deployment Script Compatibility ===" -ForegroundColor Cyan

if ($issues.Count -eq 0) {
    Write-Host "✅ Password appears compatible with deployment scripts!" -ForegroundColor Green
    Write-Host "✅ Meets Azure AD complexity requirements!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Password compatibility issues found:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "   • $issue" -ForegroundColor Red
    }
}

Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan

if ($issues.Count -gt 0) {
    Write-Host "Consider using a password like:" -ForegroundColor Yellow
    Write-Host "   MySecurePass123!   (avoids operators and time patterns)" -ForegroundColor White
    Write-Host "   AzureDemo2025#     (simple but meets requirements)" -ForegroundColor White
    Write-Host "   ComplexPass789@    (good complexity without problematic characters)" -ForegroundColor White
} else {
    Write-Host "✓ Your password should work well with the deployment scripts!" -ForegroundColor Green
}

Write-Host "`nNote: The deployment scripts now use environment variables instead of" -ForegroundColor Gray
Write-Host "command-line arguments, which reduces but doesn't eliminate all potential issues." -ForegroundColor Gray

Write-Host "`n=== Safe Special Characters ===" -ForegroundColor Cyan
Write-Host "These special characters are generally safe to use:" -ForegroundColor Gray
Write-Host "   ! @ # % ^ * + = - _ . ?" -ForegroundColor White

Write-Host "`nCharacters to avoid:" -ForegroundColor Gray
Write-Host "   & | ; ` $ ( ) { } [ ] ' \" and numbers followed by time units (ms, s, m, h, d)" -ForegroundColor White