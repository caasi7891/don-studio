#Requires -Version 5.1
<#
    One-time OAuth bootstrap for the YouTube Data API v3.

    Prerequisites:
      - Google Cloud project with YouTube Data API v3 enabled
      - OAuth 2.0 Desktop client credentials in .env (CLIENT_ID, CLIENT_SECRET)

    Effect:
      - Spins up a local HttpListener on a random high port
      - Opens the browser to Google's OAuth consent page
      - Captures the authorization code from the loopback redirect
      - Exchanges the code for a refresh_token
      - Writes REFRESH_TOKEN= back into .env (preserves other keys)
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'lib\dotenv.ps1')
. (Join-Path $PSScriptRoot 'lib\log.ps1')

$envPath = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    Write-Host '.env not found. Create it from .env.example and fill CLIENT_ID/CLIENT_SECRET first.' -ForegroundColor Red
    exit 1
}

$envMap = Read-Dotenv -Path $envPath
foreach ($k in 'CLIENT_ID','CLIENT_SECRET') {
    if ([string]::IsNullOrWhiteSpace($envMap[$k])) {
        Write-Host ".env is missing $k. Fill it from Google Cloud Console (OAuth Desktop client) first." -ForegroundColor Red
        exit 1
    }
}

# 1) Pick an ephemeral port and start a loopback HttpListener.
$port = Get-Random -Minimum 49152 -Maximum 65535
$prefix = "http://127.0.0.1:$port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()

$scope = 'https://www.googleapis.com/auth/youtube.upload'

# CSRF guard for the loopback callback (RFC 6749 state parameter).
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$stateBytes = New-Object byte[] 32
$rng.GetBytes($stateBytes)
$rng.Dispose()
$stateNonce = ([Convert]::ToBase64String($stateBytes)) -replace '[+/=]',''

$authUrl = (
    'https://accounts.google.com/o/oauth2/v2/auth' +
    '?response_type=code' +
    '&client_id='     + [uri]::EscapeDataString($envMap.CLIENT_ID) +
    '&redirect_uri='  + [uri]::EscapeDataString($prefix) +
    '&scope='         + [uri]::EscapeDataString($scope) +
    '&state='         + [uri]::EscapeDataString($stateNonce) +
    '&access_type=offline' +
    '&prompt=consent'
)

Write-Host "Opening browser for Google OAuth consent ..." -ForegroundColor Cyan
Write-Host "Listening on $prefix" -ForegroundColor DarkGray
Start-Process $authUrl

# 2) Wait up to 120s for the callback.
$deadline = (Get-Date).AddSeconds(120)
$code = $null
$err = $null
try {
    $task = $listener.GetContextAsync()
    while (-not $task.IsCompleted) {
        if ((Get-Date) -gt $deadline) {
            throw 'OAuth callback timeout (120s). Aborting.'
        }
        Start-Sleep -Milliseconds 200
    }
    $ctx = $task.Result
    $req = $ctx.Request
    $code           = $req.QueryString['code']
    $err            = $req.QueryString['error']
    $returnedState  = $req.QueryString['state']

    if ($code -and ($returnedState -ne $stateNonce)) {
        $err = 'state_mismatch'
        $code = $null
    }

    $resp = $ctx.Response
    if ($code) {
        $html = '<!doctype html><meta charset="utf-8"><title>don-studio</title><h2>OAuth 등록 완료</h2><p>이 창은 닫아도 됩니다.</p>'
    } else {
        $html = "<!doctype html><meta charset='utf-8'><title>don-studio</title><h2>OAuth 실패</h2><p>$err</p>"
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
    $resp.ContentType = 'text/html; charset=utf-8'
    $resp.ContentLength64 = $bytes.Length
    $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    $resp.OutputStream.Close()
}
finally {
    try { $listener.Stop() } catch {}
    try { $listener.Close() } catch {}
}

if ($err) { Write-Host "OAuth error: $err" -ForegroundColor Red; exit 1 }
if (-not $code) { Write-Host 'No authorization code received.' -ForegroundColor Red; exit 1 }

# 3) Exchange code for refresh_token.
$tokenBody = @(
    "code=$([uri]::EscapeDataString($code))",
    "client_id=$([uri]::EscapeDataString($envMap.CLIENT_ID))",
    "client_secret=$([uri]::EscapeDataString($envMap.CLIENT_SECRET))",
    "redirect_uri=$([uri]::EscapeDataString($prefix))",
    'grant_type=authorization_code'
) -join '&'

try {
    $tok = Invoke-RestMethod `
        -Method POST `
        -Uri 'https://oauth2.googleapis.com/token' `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $tokenBody
} catch {
    Write-Host "Token exchange failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $tok.refresh_token) {
    Write-Host 'Token endpoint did not return a refresh_token. Make sure prompt=consent and access_type=offline are set.' -ForegroundColor Red
    exit 1
}

# 4) Persist REFRESH_TOKEN into .env (replace existing line if present).
$lines = @(Get-Content -LiteralPath $envPath -Encoding UTF8)
$found = $false
$out = foreach ($line in $lines) {
    if ($line -match '^\s*REFRESH_TOKEN\s*=') {
        $found = $true
        "REFRESH_TOKEN=$($tok.refresh_token)"
    } else {
        $line
    }
}
if (-not $found) {
    $out = @($out + "REFRESH_TOKEN=$($tok.refresh_token)")
}
Set-Content -LiteralPath $envPath -Value $out -Encoding UTF8

Write-Host 'REFRESH_TOKEN written to .env. Setup complete.' -ForegroundColor Green
Write-Log -Message '[setup-oauth] refresh_token written to .env'
exit 0
