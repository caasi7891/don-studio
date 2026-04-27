#Requires -Version 5.1
<#
    don-studio: 영웅문 매매 녹화 시작 진입점.

    Flow:
      1. Single-instance mutex
      2. .env / device / disk / window pre-flight checks
      3. Launch ffmpeg (gdigrab + dshow virtual-audio-capturer)
      4. Validate ffmpeg startup (3s + file growth)
      5. Tray icon + Ctrl+Alt+S hotkey + Global\don-studio-stop event timer
      6. Disk space watchdog timer (5 min)
      7. Run Application message loop until OnStop fires
      8. Graceful Stop-FFmpegRecording (max 5 min)
      9. Spawn detached upload.ps1 and exit
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Dot-source modules
. (Join-Path $PSScriptRoot 'lib\dotenv.ps1')
. (Join-Path $PSScriptRoot 'lib\log.ps1')
. (Join-Path $PSScriptRoot 'lib\lock.ps1')
. (Join-Path $PSScriptRoot 'lib\window.ps1')
. (Join-Path $PSScriptRoot 'lib\ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'lib\tray.ps1')

Add-Type -AssemblyName System.Windows.Forms,System.Drawing

function Show-Toast {
    param(
        [string]$Title = 'don-studio',
        [Parameter(Mandatory)] [string]$Message,
        [System.Windows.Forms.ToolTipIcon]$Kind = [System.Windows.Forms.ToolTipIcon]::Info
    )
    try {
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.Visible = $true
        $n.ShowBalloonTip(5000, $Title, $Message, $Kind)
        Start-Sleep -Seconds 5
        $n.Visible = $false
        $n.Dispose()
    } catch {}
}

# ----- 1. Single-instance lock --------------------------------------------
if (-not (Acquire-SingleInstanceLock)) {
    Write-Log -Level WARN -Message 'start blocked: another instance is already recording'
    Show-Toast -Message '이미 녹화 중입니다. 트레이 메뉴 또는 Ctrl+Alt+S로 정지하세요.' -Kind Warning
    exit 0
}

try {
    # ----- 2. .env pre-flight -----
    $envPath = Join-Path $PSScriptRoot '.env'
    if (-not (Test-Path -LiteralPath $envPath)) {
        Show-Toast -Message '.env 파일이 없습니다. README 참고 후 설정하세요.' -Kind Error
        Write-Log -Level ERROR -Message '.env not found'
        exit 1
    }
    $envMap = Read-Dotenv -Path $envPath
    foreach ($k in 'CLIENT_ID','CLIENT_SECRET','REFRESH_TOKEN') {
        if ([string]::IsNullOrWhiteSpace($envMap[$k])) {
            Show-Toast -Message ".env에 $k 가 비어 있습니다. setup-oauth.ps1을 먼저 실행하세요." -Kind Error
            Write-Log -Level ERROR -Message "missing env key: $k"
            exit 1
        }
    }

    # ----- 3. Audio device check (R1, N7) -----
    if (-not (Test-AudioCaptureDevice)) {
        Show-Toast `
            -Message 'virtual-audio-capturer 디바이스가 없습니다. screen-capture-recorder 설치 후 다시 시도하세요.' `
            -Kind Error
        Write-Log -Level ERROR -Message 'virtual-audio-capturer not enumerable'
        exit 1
    }

    # ----- 4. Pre-flight disk check (R5) -----
    $recDir = Join-Path $PSScriptRoot 'recordings'
    if (-not (Test-Path -LiteralPath $recDir)) {
        New-Item -ItemType Directory -Path $recDir -Force | Out-Null
    }
    $recDriveRoot = ([System.IO.DirectoryInfo]$recDir).Root.FullName
    $recDrive = Get-PSDrive | Where-Object { $_.Root -eq $recDriveRoot } | Select-Object -First 1
    if ($recDrive -and $recDrive.Free -lt 5GB) {
        Show-Toast -Message "디스크 여유 공간 < 5GB ($([math]::Round($recDrive.Free/1GB,1))GB)" -Kind Error
        Write-Log -Level ERROR -Message "low disk before start: $($recDrive.Free) bytes"
        exit 1
    }

    # ----- 5. Find target window (R2, R6, R15) -----
    $hts = Find-HtsWindow
    if (-not $hts) {
        Show-Toast -Message '영웅문 창을 찾지 못했습니다. 영웅문을 먼저 실행하세요.' -Kind Error
        Write-Log -Level ERROR -Message 'no HTS window found'
        exit 1
    }
    if (-not (Test-WindowVisible $hts.MainWindowHandle)) {
        Show-Toast -Message '영웅문 창이 최소화/숨김 상태입니다. 보이게 둔 채로 다시 시작하세요.' -Kind Error
        Write-Log -Level ERROR -Message 'HTS window not visible'
        exit 1
    }
    $windowTitle = $hts.MainWindowTitle
    Write-Log -Message "[start] target window: '$windowTitle' (pid=$($hts.Id))"

    # ----- 6. Launch ffmpeg -----
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $output = Join-Path $recDir "$stamp-trade.mp4"
    $logDir = Join-Path $PSScriptRoot 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $ffLog = Join-Path $logDir "ffmpeg-$stamp.log"

    $rec = Start-FFmpegRecording `
        -WindowTitle $windowTitle `
        -OutputPath $output `
        -StderrLogPath $ffLog

    # ----- 7. Startup validation (MJ6) -----
    Start-Sleep -Seconds 3
    if ($rec.Process.HasExited) {
        $tail = ''
        if (Test-Path -LiteralPath $ffLog) {
            $tail = (Get-Content -LiteralPath $ffLog -Tail 20 -Encoding UTF8) -join "`n"
        }
        Write-Log -Level ERROR -Message "[ffmpeg] failed to start. tail:`n$tail"
        Show-Toast -Message 'ffmpeg 시작 실패. logs 폴더를 확인하세요.' -Kind Error
        Stop-FFmpegRecording -Recording $rec | Out-Null
        exit 1
    }

    # libx264 medium preset can buffer ~1-2s of look-ahead before the first
    # mdat write. Don't gate on growth (false positives); gate on "file got
    # created and has at least the mp4 header bytes".
    Start-Sleep -Seconds 2
    $size = if (Test-Path -LiteralPath $output) { (Get-Item -LiteralPath $output).Length } else { 0 }
    if ($size -le 0) {
        Write-Log -Level ERROR -Message "[ffmpeg] no output file or zero bytes after 5s (size=$size)"
        Show-Toast -Message '녹화 파일이 생성되지 않았습니다. 영웅문 창과 디바이스를 확인하세요.' -Kind Error
        Stop-FFmpegRecording -Recording $rec | Out-Null
        exit 1
    }
    Write-Log -Message "[ffmpeg] first bytes written ($size bytes) -- recording active"

    # ----- 8. Tray + hotkey + stop-event-poll timer -----
    # Use ApplicationContext + ExitThread for reliable Application.Run()
    # termination on PS 5.1. Plain Application.Run() / Application.Exit() can
    # silently fail to dispatch timer ticks or to terminate without a host.
    $appCtx = New-Object System.Windows.Forms.ApplicationContext
    $stopRequested = [ref]$false
    $onStop = {
        if (-not $stopRequested.Value) {
            $stopRequested.Value = $true
            Write-Log -Message '[stop] OnStop fired; exiting message loop'
            try { $appCtx.ExitThread() } catch { Write-Log -Level WARN -Message "[stop] ExitThread failed: $_" }
        }
    }.GetNewClosure()

    $ui = New-TrayUI -OnStop $onStop

    # ----- 9. Disk-watchdog timer (R5) -----
    $diskTimer = New-Object System.Windows.Forms.Timer
    $diskTimer.Interval = 300000   # 5 min
    $diskTimer.add_Tick({
        try {
            $drive = Get-PSDrive | Where-Object { $_.Root -eq $recDriveRoot } | Select-Object -First 1
            if ($drive -and $drive.Free -lt 5GB) {
                Write-Log -Level WARN -Message "[disk] free<5GB; auto-stopping"
                & $onStop
            }
        } catch {}
    })
    $diskTimer.Start()

    Write-Log -Message '[start] entering message loop (ApplicationContext)'
    [System.Windows.Forms.Application]::Run($appCtx)
    Write-Log -Message '[start] message loop exited'

    # ----- 10. Cleanup -----
    try { $diskTimer.Stop(); $diskTimer.Dispose() } catch {}
    Stop-FFmpegRecording -Recording $rec
    try { Get-EventSubscriber | Unregister-Event -ErrorAction SilentlyContinue } catch {}
    Dispose-TrayUI -Ui $ui
}
finally {
    Release-SingleInstanceLock
}

# ----- 11. Detached upload (MJ7) -----
if ($output -and (Test-Path -LiteralPath $output)) {
    Write-Log -Message "[upload] dispatching detached upload for $output"
    $uploadScript = Join-Path $PSScriptRoot 'upload.ps1'
    Start-Process `
        -FilePath 'powershell.exe' `
        -WindowStyle Hidden `
        -WorkingDirectory $PSScriptRoot `
        -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy','Bypass',
            '-File', $uploadScript,
            '-MediaPath', $output
        )
}

exit 0
