#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Get-FFmpegPath {
    [CmdletBinding()] param()
    $candidate = Join-Path $PSScriptRoot '..\bin\ffmpeg.exe'
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "ffmpeg.exe not found at $candidate. Download a static build from https://www.gyan.dev/ffmpeg/builds/ and place it under bin/."
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Test-AudioCaptureDevice {
    <#
        Verifies that the dshow audio device "virtual-audio-capturer"
        (provided by screen-capture-recorder) is enumerable to ffmpeg.
        Returns $true / $false. Does not throw.
    #>
    [CmdletBinding()] param()
    try {
        $exe = Get-FFmpegPath
    } catch {
        return $false
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '-hide_banner -list_devices true -f dshow -i dummy'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stderr = $proc.StandardError.ReadToEnd()
    $null = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit(5000) | Out-Null
    return ($stderr -match 'virtual-audio-capturer')
}

function Quote-FFmpegArg([string]$Value) {
    if ($Value -match '\s|"') { return '"' + ($Value -replace '"','\"') + '"' }
    return $Value
}

function Start-FFmpegRecording {
    <#
        Launches ffmpeg with stdin redirected so Stop-FFmpegRecording can send 'q'.
        stderr is tee'd to $StderrLogPath via Register-ObjectEvent + -MessageData
        (avoids the $using: trap on PS 5.1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WindowTitle,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [string]$StderrLogPath,
        [string]$AudioDevice = 'virtual-audio-capturer',
        [int]$Framerate = 30,
        [int]$Crf = 23,
        [string]$Preset = 'medium'
    )

    $exe = Get-FFmpegPath

    # ffmpeg wants the title verbatim; we must quote because Korean characters
    # and spaces are common.
    $videoIn = "title=$WindowTitle"

    # crop=trunc(iw/2)*2:trunc(ih/2)*2 trims at most 1 px on width/height so the
    # frame is divisible by 2 -- yuv420p (libx264 default) requires even dims.
    # 영웅문4 default window often produces odd dimensions like 2554x1363.
    $argList = @(
        '-y',
        '-hide_banner',
        '-loglevel','warning',
        '-f','gdigrab','-framerate', $Framerate, '-i', $videoIn,
        '-f','dshow','-i',("audio=$AudioDevice"),
        '-vf','crop=trunc(iw/2)*2:trunc(ih/2)*2',
        '-c:v','libx264','-preset',$Preset,'-crf',$Crf,'-pix_fmt','yuv420p',
        '-c:a','aac','-b:a','128k',
        $OutputPath
    )

    $quoted = ($argList | ForEach-Object { Quote-FFmpegArg ([string]$_) }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $quoted
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)

    # Tee stderr -> log file. Use -MessageData (NOT $using:) because $using: is
    # only valid for Invoke-Command / Start-Job in PS 5.1.
    $sub = Register-ObjectEvent -InputObject $proc `
        -EventName ErrorDataReceived `
        -MessageData $StderrLogPath `
        -Action {
            if ($EventArgs.Data) {
                Add-Content -LiteralPath $Event.MessageData -Value $EventArgs.Data -Encoding UTF8
            }
        }
    $proc.BeginErrorReadLine()

    return [pscustomobject]@{
        Process       = $proc
        Subscription  = $sub
        StderrLogPath = $StderrLogPath
    }
}

function Stop-FFmpegRecording {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Recording,   # output of Start-FFmpegRecording
        [int]$TimeoutMinutes = 5
    )
    $proc = $Recording.Process

    if (-not $proc.HasExited) {
        try {
            $proc.StandardInput.WriteLine('q')
            $proc.StandardInput.Flush()
        } catch {
            # stdin may already be closed; we'll fall through to poll + kill.
        }

        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 200
        }

        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch {}
        }
    }

    if ($Recording.Subscription) {
        try { Unregister-Event -SubscriptionId $Recording.Subscription.Id -ErrorAction SilentlyContinue } catch {}
        try { $Recording.Subscription | Remove-Job -Force -ErrorAction SilentlyContinue } catch {}
    }
}
