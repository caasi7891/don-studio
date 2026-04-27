#Requires -Version 5.1
<#
    End-to-end smoke test against Notepad (so it can run without 영웅문).

    Verifies:
      1. virtual-audio-capturer device is enumerable to ffmpeg
      2. Notepad is recorded for ~10 seconds
      3. Recording is stopped via Global\don-studio-stop EventWaitHandle
      4. mp4 exists, is non-empty, and contains a valid audio stream
      5. Upload completes (or moves to failed-uploads/)
      6. (If upload succeeded) the resulting YouTube video is private

    Pass/Fail printed to stdout.
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'lib\dotenv.ps1')
. (Join-Path $PSScriptRoot 'lib\log.ps1')
. (Join-Path $PSScriptRoot 'lib\oauth.ps1')
. (Join-Path $PSScriptRoot 'lib\ffmpeg.ps1')

$results = New-Object System.Collections.Generic.List[object]
function Add-Result($name, $pass, $detail = '') {
    $results.Add([pscustomobject]@{ Name = $name; Pass = [bool]$pass; Detail = $detail })
    $tag = if ($pass) { 'PASS' } else { 'FAIL' }
    $color = if ($pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} {2}" -f $tag, $name, $detail) -ForegroundColor $color
}

# ----- 1. Audio device probe -----
Add-Result 'audio device' (Test-AudioCaptureDevice) 'virtual-audio-capturer enumerable via ffmpeg dshow'

# ----- 2. .env sanity -----
$envPath = Join-Path $PSScriptRoot '.env'
$envOk = (Test-Path -LiteralPath $envPath) -and
         ((Read-Dotenv -Path $envPath).REFRESH_TOKEN)
Add-Result '.env REFRESH_TOKEN present' $envOk

# ----- 3. Notepad as fake target -----
Write-Host 'Launching Notepad as recording target...' -ForegroundColor DarkGray
$notepad = Start-Process -FilePath 'notepad.exe' -PassThru
Start-Sleep -Seconds 1

# Override window pattern via environment variable (process scope).
# Find-HtsWindow checks $env:WINDOW_TITLE_OVERRIDE first, so this is inherited
# by the spawned start-recording.ps1 child process.
$prevOverride = $env:WINDOW_TITLE_OVERRIDE
$env:WINDOW_TITLE_OVERRIDE = 'Notepad'

# ----- 4. Spawn start-recording in background -----
$startScript = Join-Path $PSScriptRoot 'start-recording.ps1'
$rec = Start-Process `
    -FilePath 'powershell.exe' `
    -WindowStyle Hidden `
    -PassThru `
    -WorkingDirectory $PSScriptRoot `
    -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$startScript)

# Wait for ffmpeg to actually start producing frames
$recordingsDir = Join-Path $PSScriptRoot 'recordings'
$start = Get-Date
$mp4 = $null
while ((Get-Date) - $start -lt [TimeSpan]::FromSeconds(15)) {
    $mp4 = Get-ChildItem -LiteralPath $recordingsDir -Filter '*-trade.mp4' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1
    if ($mp4 -and $mp4.Length -gt 0) { break }
    Start-Sleep -Milliseconds 500
}
$detail = if ($mp4) { $mp4.FullName } else { 'no mp4 detected' }
Add-Result 'recording started' ($mp4 -ne $null) $detail

# Hold ~10s of "trading"
Start-Sleep -Seconds 10
[System.Media.SystemSounds]::Asterisk.Play()
Start-Sleep -Seconds 1

# ----- 5. Signal stop via EventWaitHandle (M-NEW-3) -----
$evt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Global\don-studio-stop')
$null = $evt.Set()
$evt.Dispose()

# Wait for recorder process to exit (graceful stop + detached upload spawn)
$recExited = $rec.WaitForExit(60000)
Add-Result 'recorder exited gracefully' $recExited

# Restore env
if ($prevOverride) { $env:WINDOW_TITLE_OVERRIDE = $prevOverride } else { Remove-Item Env:WINDOW_TITLE_OVERRIDE -ErrorAction SilentlyContinue }

# Cleanup notepad
try { $notepad | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}

# ----- 6. mp4 exists + audio stream check -----
if ($mp4) {
    $mp4Now = Get-Item -LiteralPath $mp4.FullName -ErrorAction SilentlyContinue
    $mp4StillThere = $null -ne $mp4Now
    if ($mp4StillThere) {
        # Upload may not have run yet OR may have failed and moved to failed-uploads/.
        Add-Result 'mp4 size > 0' ($mp4Now.Length -gt 0) ("size=$($mp4Now.Length) bytes")

        $ffprobe = Join-Path $PSScriptRoot 'bin\ffprobe.exe'
        if (Test-Path -LiteralPath $ffprobe) {
            $streams = & $ffprobe -v error -show_entries stream=codec_type -of csv=p=0 $mp4Now.FullName 2>&1
            $hasAudio = ($streams -match 'audio')
            $hasVideo = ($streams -match 'video')
            Add-Result 'video stream present' ([bool]$hasVideo)
            Add-Result 'audio stream present' ([bool]$hasAudio)
        } else {
            Add-Result 'ffprobe present (skipped stream check)' $false 'bin/ffprobe.exe missing'
        }
    } else {
        # Upload likely succeeded and removed the file.
        Add-Result 'mp4 removed by successful upload' $true 'recordings/ no longer contains the file'
    }
}

# ----- 7. Wait for upload to finish (poll log for success / failed-uploads/) -----
$uploadDeadline = (Get-Date).AddMinutes(5)
$uploadOutcome = 'unknown'
$videoId = $null
while ((Get-Date) -lt $uploadDeadline) {
    $logFile = Join-Path $PSScriptRoot ("logs\recorder-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    if (Test-Path -LiteralPath $logFile) {
        $tail = Get-Content -LiteralPath $logFile -Tail 50 -Encoding UTF8 -ErrorAction SilentlyContinue
        $successLine = $tail | Where-Object { $_ -match '\[upload\] success videoId=([\w\-]+)' } | Select-Object -Last 1
        if ($successLine -and $successLine -match 'videoId=([\w\-]+)') {
            $videoId = $matches[1]
            $uploadOutcome = 'success'
            break
        }
        $failedLine = $tail | Where-Object { $_ -match '\[upload\] failed' } | Select-Object -Last 1
        if ($failedLine) {
            $uploadOutcome = 'failed'
            break
        }
    }
    Start-Sleep -Seconds 2
}
Add-Result 'upload completed' ($uploadOutcome -eq 'success') "outcome=$uploadOutcome videoId=$videoId"

# ----- 8. Verify privacyStatus=private + cleanup test video -----
if ($videoId) {
    try {
        $tok = Get-AccessToken
        $vresp = Invoke-RestMethod `
            -Method GET `
            -Uri "https://www.googleapis.com/youtube/v3/videos?part=status&id=$videoId" `
            -Headers @{ Authorization = "Bearer $tok" }
        $status = $vresp.items[0].status.privacyStatus
        Add-Result 'privacyStatus=private' ($status -eq 'private') "actual=$status"

        # Cleanup the test video so we don't pollute the channel.
        Invoke-WebRequest `
            -Method DELETE `
            -Uri "https://www.googleapis.com/youtube/v3/videos?id=$videoId" `
            -Headers @{ Authorization = "Bearer $tok" } `
            -UseBasicParsing | Out-Null
        Add-Result 'test video deleted' $true "videoId=$videoId"
    } catch {
        Add-Result 'privacy/cleanup verification' $false $_.Exception.Message
    }
}

# ----- Summary -----
$total = $results.Count
$passed = ($results | Where-Object { $_.Pass }).Count
Write-Host ("`nSummary: {0}/{1} passed" -f $passed, $total) -ForegroundColor Cyan
if ($passed -ne $total) { exit 1 } else { exit 0 }
