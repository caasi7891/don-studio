#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Invoke-ResumableUpload {
    <#
        YouTube Data API v3 resumable upload.

        Fixes baked in (per ralplan iteration 2 consensus):
          - all offset/size variables are [long] (handles >2GB files)
          - JSON metadata pre-encoded as UTF-8 bytes (preserves Korean title)
          - 308 Resume Incomplete with AND without Range header handled
          - 401 retry counter (max 2)
          - 5xx retry with exponential backoff (max 3)
          - 60s wall-clock progress logging

        Returns the videoId on success. Throws on terminal failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [hashtable]$Metadata
    )

    if (-not (Get-Command Get-AccessToken -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'oauth.ps1')
    }
    if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'log.ps1')
    }

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Upload source not found: $FilePath"
    }

    [long]$bytes = (Get-Item -LiteralPath $FilePath).Length
    if ($bytes -le 0) { throw "Upload source is empty: $FilePath" }

    $token = Get-AccessToken

    # ----- 1) Initiate (UTF-8 body bytes; PS 5.1 default-codepage trap fix) -----
    $jsonStr   = $Metadata | ConvertTo-Json -Compress
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)

    $initHeaders = @{
        'Authorization'           = "Bearer $token"
        'X-Upload-Content-Type'   = 'video/mp4'
        'X-Upload-Content-Length' = "$bytes"
    }

    $initResp = Invoke-WebRequest `
        -Method POST `
        -Uri 'https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status' `
        -Headers $initHeaders `
        -ContentType 'application/json; charset=UTF-8' `
        -Body $jsonBytes `
        -UseBasicParsing

    $location = $initResp.Headers['Location']
    if (-not $location) { throw 'Resumable initiate did not return a Location header' }
    if ($location -is [array]) { $location = $location[0] }

    Write-Log -Message ("[upload] initiated bytes=$bytes path=$FilePath")

    # ----- 2) Chunked PUT loop (all-[long] arithmetic) -----
    [long]$chunkSize = 8MB
    [long]$offset    = 0
    $retry401 = 0
    $retry5xx = 0
    $progressNext = (Get-Date).AddSeconds(60)

    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        while ($offset -lt $bytes) {
            [long]$remaining = $bytes - $offset
            [long]$thisChunk = [System.Math]::Min([long]$chunkSize, [long]$remaining)

            $buf = New-Object byte[] $thisChunk
            $fs.Position = $offset
            $null = $fs.Read($buf, 0, [int]$thisChunk)

            if ((Get-AccessTokenTtlSeconds) -lt 600) {
                $token = Get-AccessToken -Force
            }

            $rangeValue = "bytes $offset-$($offset + $thisChunk - 1)/$bytes"
            $putHeaders = @{
                'Authorization' = "Bearer $token"
                'Content-Range' = $rangeValue
            }

            try {
                $resp = Invoke-WebRequest `
                    -Method PUT `
                    -Uri $location `
                    -Headers $putHeaders `
                    -ContentType 'video/mp4' `
                    -Body $buf `
                    -UseBasicParsing `
                    -ErrorAction Stop

                if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
                    $obj = $resp.Content | ConvertFrom-Json
                    Write-Log -Message ("[upload] success videoId={0}" -f $obj.id)
                    return $obj.id
                }
            } catch [System.Net.WebException] {
                $r = $_.Exception.Response
                if ($null -eq $r) { throw }
                $code = [int]$r.StatusCode

                if ($code -eq 308) {
                    $rangeHeader = $null
                    try { $rangeHeader = $r.Headers['Range'] } catch {}

                    if ($rangeHeader -and ($rangeHeader -match 'bytes=0-(\d+)')) {
                        $offset = [long]$matches[1] + 1
                    } else {
                        # 308 with no Range = nothing committed yet
                        $offset = [long]0
                    }
                    $retry5xx = 0
                    continue
                }
                elseif ($code -eq 401) {
                    if ($retry401 -ge 2) {
                        throw "Upload aborted: 401 after 2 token refreshes"
                    }
                    $retry401++
                    $token = Get-AccessToken -Force
                    continue
                }
                elseif ($code -ge 500 -and $code -lt 600) {
                    if ($retry5xx -ge 3) {
                        throw "Upload aborted: 5xx after 3 retries (last=$code)"
                    }
                    $retry5xx++
                    $sleep = [int][Math]::Pow(2, $retry5xx)   # 2,4,8s
                    Write-Log -Level WARN -Message "[upload] 5xx ($code); backoff ${sleep}s"
                    Start-Sleep -Seconds $sleep
                    continue
                }
                else {
                    throw
                }
            }

            $offset   += $thisChunk
            $retry5xx  = 0    # any successful (non-error) chunk resets backoff

            if ((Get-Date) -ge $progressNext) {
                $pct = [math]::Round(($offset / $bytes) * 100, 1)
                $mb  = [math]::Round($offset / 1MB, 1)
                $tmb = [math]::Round($bytes / 1MB, 1)
                Write-Log -Message ("[upload] progress: {0}% ({1}/{2} MB)" -f $pct, $mb, $tmb)
                $progressNext = (Get-Date).AddSeconds(60)
            }
        }
    }
    finally {
        $fs.Close()
        $fs.Dispose()
    }

    throw "Upload loop exited without 2xx response (offset=$offset bytes=$bytes)"
}
