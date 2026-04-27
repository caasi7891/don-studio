#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# Module-scoped token cache. Reset to defaults at dot-source time.
$script:DonStudioTokenCache = @{
    Token  = $null
    Expiry = [DateTime]::MinValue
}

function Get-AccessTokenTtlSeconds {
    [CmdletBinding()] param()
    return ($script:DonStudioTokenCache.Expiry - (Get-Date)).TotalSeconds
}

function Get-AccessToken {
    [CmdletBinding()]
    param([switch]$Force)

    if (-not $Force -and
        $script:DonStudioTokenCache.Token -and
        (Get-AccessTokenTtlSeconds) -gt 600) {
        return $script:DonStudioTokenCache.Token
    }

    if (-not (Get-Command Read-Dotenv -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'dotenv.ps1')
    }

    $envPath = Resolve-Path -LiteralPath "$PSScriptRoot\..\.env"
    $envMap = Read-Dotenv -Path $envPath
    foreach ($k in 'CLIENT_ID','CLIENT_SECRET','REFRESH_TOKEN') {
        if (-not $envMap.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($envMap[$k])) {
            throw ".env is missing required key: $k"
        }
    }

    $body = @(
        "grant_type=refresh_token",
        "refresh_token=$([uri]::EscapeDataString($envMap.REFRESH_TOKEN))",
        "client_id=$([uri]::EscapeDataString($envMap.CLIENT_ID))",
        "client_secret=$([uri]::EscapeDataString($envMap.CLIENT_SECRET))"
    ) -join '&'

    $resp = Invoke-RestMethod `
        -Method POST `
        -Uri 'https://oauth2.googleapis.com/token' `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $body

    $script:DonStudioTokenCache.Token  = $resp.access_token
    $script:DonStudioTokenCache.Expiry = (Get-Date).AddSeconds([int]$resp.expires_in - 60)
    return $resp.access_token
}
