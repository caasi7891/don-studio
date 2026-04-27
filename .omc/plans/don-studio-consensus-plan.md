# Consensus Plan: don-studio (영웅문 매매 녹화 + YouTube 비공개 업로드)

**Source spec:** `.omc/specs/deep-interview-trade-recorder.md` (인터뷰 7라운드, 모호도 18%)
**Mode:** RALPLAN consensus (Planner → Architect → Critic) — short
**Iteration:** 2 (final) — Architect/Critic 합의 통과 (2025-04-27)
**Status:** APPROVED for execution

---

## 합의 요약

- **반복 1**: Critic이 REJECT — 2 CRITICAL (WM_HOTKEY 미수신, faststart 손상 체인) + 8 MAJOR + 7 MINOR.
- **반복 2 (v2)**: 모든 v1 결함 해결. Architect = APPROVE_WITH_IMPROVEMENTS (4 must-fix). Critic = APPROVE_WITH_IMPROVEMENTS (Architect 4개 검증 + 신규 CRITICAL 2 / MAJOR 2). 결론: "v3 불필요 — 외과적 수정만 필요."
- **본 문서**: v2 + Architect/Critic의 모든 must-fix(7) + 권장(7) 통합본.

---

## RALPLAN-DR Summary

### Principles
1. **의존성 최소화** — 무료/포터블, 1회성 사용자 설치까지만 허용.
2. **단일 사용자 단순화** — 본인 1인 PC, PS 5.1 기준.
3. **실패 시 데이터 보존** — 정지 시 graceful(최대 5분), 업로드 실패 시 원본 보존.
4. **콘텐츠 품질 1순위** — 호가/체결 텍스트 가독 + 영웅문 시스템 사운드 가청.
5. **단일 인스턴스 보장** — 녹화 중 시작 클릭은 mutex 차단; 업로드는 별도 프로세스.

### Decision Drivers
1. 콘텐츠 품질 (Round 2)
2. 운영 단순성 (Round 1·6)
3. 비용 0원 + 1인 운영 (Round 7)

### Viable Options (Round 7 결과 반영)
- **A. ffmpeg gdigrab + dshow virtual-audio-capturer + PS 5.1 NotifyIcon ✅ 선택**
- B. Stereo Mix — invalidated (하드웨어 의존성)
- C. NAudio→ffmpeg pipe — 단일 사용자 P2 약점, 그러나 P1·P4 우위. **v2.x follow-up 예약.**

---

## Requirements Summary

영웅문 foreground 윈도우의 30 fps mp4(H.264 + AAC) 녹화 + 시스템 사운드 캡처 + YouTube 비공개 업로드 + 업로드 성공 시 원본 자동 삭제. PS 5.1 + ffmpeg.exe + .env. 본인 1인 PC.

---

## Acceptance Criteria

| # | 기준 | 검증 방법 |
|---|------|----------|
| AC1 | 클릭 → ffmpeg 첫 프레임까지 ≤ **8 s** (validation 5 s + 여유 3 s 포함) | `[ffmpeg] first frame OK` 로그 타임스탬프 |
| AC2 | 정지 신호 → ffmpeg 프로세스 종료 ≤ 300 s (일반 케이스 1–3 s) | `$proc.HasExited == true` 시각 |
| AC3 | 호가·주문창 텍스트 가독 (사람 판단) | 30 s 녹화 → 1080p 재생 → 종목 코드/가격 식별 |
| AC4 | 영웅문 시스템 사운드 가청 (사람 판단) | `ffprobe -show_streams` audio stream 존재 + 청취 |
| AC5 | 정지 후 자동 업로드 시작 | 로그: `[upload] starting POST videos.insert` |
| AC6 | 업로드 성공 → 원본 자동 삭제 | `recordings/`에 mp4 부재 |
| AC7 | 업로드 실패 → 보존 + 다음 실행 재시도 | 인터넷 차단 시뮬 → `failed-uploads/` 이동 → 재실행 → 업로드 성공 |
| AC8 | `REFRESH_TOKEN` → access_token 자동 갱신 | `oauth2.googleapis.com/token` HTTP 200 + access_token |
| AC9 | 단일 인스턴스 (녹화 중 시작 클릭 무시) | `Get-Process ffmpeg` count == 1 |
| AC10 | 6 h 녹화 → 길이 ≈ 6 h ± 1 s, A/V drift < 50 ms | `ffprobe -show_format -show_streams` per-stream duration 비교 + 시작/종료 30 s clapboard |
| AC11 | 업로드 진행률 60 s 간격 로그 | `[upload] progress: <pct>% (<MB>/<total>MB)` 라인 N개 이상 |

---

## Implementation Steps

### Step 1 — 저장소 부트스트랩
```
/
  start-recording.ps1
  upload.ps1
  setup-oauth.ps1
  install-shortcut.ps1
  smoke-test.ps1
  .env.example
  .env                       # gitignore
  bin/ffmpeg.exe             # 사용자 다운로드(README 가이드)
  lib/
    dotenv.ps1
    oauth.ps1
    ffmpeg.ps1
    window.ps1
    lock.ps1
    log.ps1
    tray.ps1                 # NativeWindow + WndProc + NotifyIcon + EventWaitHandle 폴링 타이머
    upload-core.ps1          # chunked PUT + UTF-8 + [long] 산술
  recordings/
  failed-uploads/
  logs/
  assets/
    tray-icon.ico            # 누락 시 SystemIcons.Application으로 자동 fallback
```
- `.gitignore`: `.env`, `recordings/`, `failed-uploads/`, `logs/`, `bin/ffmpeg.exe`
- 모든 `.ps1` 헤더:
  ```powershell
  #Requires -Version 5.1
  $ErrorActionPreference = 'Stop'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  ```

### Step 2 — `setup-oauth.ps1` (1회성 OAuth 등록)
- `.env` 로드 → `CLIENT_ID/CLIENT_SECRET` 검증.
- `Get-Random -Min 49152 -Max 65535` → 빈 포트 → `[System.Net.HttpListener]` `http://127.0.0.1:<port>/` 기동.
- 브라우저 `Start-Process`:
  ```
  https://accounts.google.com/o/oauth2/v2/auth
    ?response_type=code
    &client_id=<CLIENT_ID>
    &redirect_uri=http://127.0.0.1:<port>/
    &scope=https://www.googleapis.com/auth/youtube.upload
    &access_type=offline
    &prompt=consent
  ```
- 콜백 수신(타임아웃 60 s) → `code` → `POST https://oauth2.googleapis.com/token` (form-urlencoded: grant_type=authorization_code, code, client_id, client_secret, redirect_uri).
- 응답에서 `refresh_token` 회수 → `.env`에 `REFRESH_TOKEN=` 추가/교체.
- 에러 분기: `error=access_denied` (사용자 거부), 60 s 타임아웃, 토큰 교환 실패(non-200) — 각각 명확한 콘솔 메시지.
- HttpListener `Stop()` + `Close()` 보장(finally).

### Step 3 — `lib/` 모듈

#### `lib/dotenv.ps1`
```powershell
function Read-Dotenv([string]$Path) {
  $h = @{}
  if (-not (Test-Path $Path)) { return $h }
  Get-Content $Path -Encoding UTF8 | ForEach-Object {
    $line = $_.TrimStart([char]0xFEFF)            # BOM 제거 (수정: Critic m-1)
    if ($line -match '^\s*#') { return }
    if ($line -match '^\s*$') { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 0) { return }
    $key = $line.Substring(0, $idx).Trim()
    $val = $line.Substring($idx + 1).Trim()
    if ($val -match '^"(.*)"$') { $val = $matches[1] }
    $h[$key] = $val
  }
  return $h
}
```

#### `lib/oauth.ps1`
```powershell
$script:tokenCache = @{ Token = $null; Expiry = [DateTime]::MinValue }

function Get-AccessTokenTtlSeconds {           # Critic missing-function 픽스
  return ($script:tokenCache.Expiry - (Get-Date)).TotalSeconds
}

function Get-AccessToken([switch]$Force) {
  if (-not $Force -and $script:tokenCache.Token -and (Get-AccessTokenTtlSeconds) -gt 600) {
    return $script:tokenCache.Token
  }
  $env = Read-Dotenv "$PSScriptRoot\..\.env"
  $body = "grant_type=refresh_token&refresh_token=$($env.REFRESH_TOKEN)" +
          "&client_id=$($env.CLIENT_ID)&client_secret=$($env.CLIENT_SECRET)"
  $resp = Invoke-RestMethod -Method POST -Uri "https://oauth2.googleapis.com/token" `
                            -ContentType "application/x-www-form-urlencoded" -Body $body
  $script:tokenCache.Token  = $resp.access_token
  $script:tokenCache.Expiry = (Get-Date).AddSeconds([int]$resp.expires_in - 60)
  return $resp.access_token
}
```
- 401 from token endpoint → `Invoke-RestMethod` throws → 호출자 `failed-uploads/` 보존 + setup-oauth 안내.

#### `lib/window.ps1`
```powershell
function Find-HtsWindow {
  $env = Read-Dotenv "$PSScriptRoot\..\.env"
  if ($env.WINDOW_TITLE_OVERRIDE) {
    return Get-Process | Where-Object { $_.MainWindowTitle -like "*$($env.WINDOW_TITLE_OVERRIDE)*" } | Select-Object -First 1
  }
  # 타이틀 우선, 프로세스명은 disambiguation only (Critic MJ5)
  $byTitle = Get-Process | Where-Object { $_.MainWindowTitle -match '영웅문|HEROES|Heroes' }
  if ($byTitle.Count -eq 0) { return $null }
  if ($byTitle.Count -eq 1) { return $byTitle[0] }
  $disambig = $byTitle | Where-Object { $_.ProcessName -match 'kiwoom|hero|khmini|khministarter' }
  return ($disambig | Select-Object -First 1) ?? $byTitle[0]
}

function Test-WindowVisible($hwnd) {
  Add-Type @"
  using System.Runtime.InteropServices;
  public class Win {
    [DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
  }
"@ -PassThru | Out-Null
  return ([Win]::IsWindowVisible($hwnd) -and -not [Win]::IsIconic($hwnd))
}
```

#### `lib/ffmpeg.ps1` — **C-NEW-1 (`$using:`) + MJ2 픽스**
```powershell
function Start-FFmpegRecording {
  param([string]$WindowTitle, [string]$OutputPath, [string]$StderrLogPath)
  $exe = Resolve-Path "$PSScriptRoot\..\bin\ffmpeg.exe"
  $args = @(
    '-y',
    '-f','gdigrab','-framerate','30','-i',"title=$WindowTitle",
    '-f','dshow','-i','audio=virtual-audio-capturer',
    '-c:v','libx264','-preset','medium','-crf','23','-pix_fmt','yuv420p',
    '-c:a','aac','-b:a','128k',
    $OutputPath
  )                                                       # +faststart 제거 (C2)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $proc = [System.Diagnostics.Process]::Start($psi)

  # stderr → 로그 파일 (Critic C-NEW-1: $using → -MessageData)
  Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -MessageData $StderrLogPath -Action {
    if ($EventArgs.Data) { Add-Content -Path $Event.MessageData -Value $EventArgs.Data }
  } | Out-Null
  $proc.BeginErrorReadLine()
  return $proc
}

function Stop-FFmpegRecording([System.Diagnostics.Process]$Process) {
  try {
    $Process.StandardInput.WriteLine("q")
    $Process.StandardInput.Flush()
  } catch {
    Write-Log -Level WARN -Message "stdin write failed; falling through"
  }
  $deadline = (Get-Date).AddMinutes(5)                    # C2 dynamic poll
  while (-not $Process.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
  }
  if (-not $Process.HasExited) {
    Write-Log -Level WARN -Message "[ffmpeg] timeout 5min, force kill"
    $Process.Kill()
  }
}
```

#### `lib/lock.ps1`
```powershell
$script:mutex = $null
function Acquire-SingleInstanceLock {
  $script:mutex = New-Object System.Threading.Mutex($false, "Global\don-studio-recording")
  return $script:mutex.WaitOne(0)
}
function Release-SingleInstanceLock {
  if ($script:mutex) { try { $script:mutex.ReleaseMutex() } catch {}; $script:mutex.Dispose(); $script:mutex = $null }
}
```

#### `lib/log.ps1`
```powershell
function Write-Log {
  param([ValidateSet('INFO','WARN','ERROR')] [string]$Level='INFO', [string]$Message)
  $log = "$PSScriptRoot\..\logs\recorder-$(Get-Date -Format yyyyMMdd).log"
  Add-Content -Path $log -Value ("[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message)
}
```

#### `lib/tray.ps1` — **C1(WM_HOTKEY) + M-NEW-3(EventWaitHandle 폴링) + m-2(아이콘 fallback) + m-6(RegisterHotKey 결과 검증)**
```powershell
if (-not ([System.Management.Automation.PSTypeName]'HotkeyWindow').Type) {   # N1 가드
  Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotkeyWindow : NativeWindow, IDisposable {
    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_CONTROL = 0x2; public const uint MOD_ALT = 0x1;
    public int HotkeyId = 1;
    public Action OnHotkey;
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public HotkeyWindow() { CreateHandle(new CreateParams()); }
    public bool Register(uint mods, uint vk) { return RegisterHotKey(this.Handle, HotkeyId, mods, vk); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && OnHotkey != null) { OnHotkey(); }
        base.WndProc(ref m);
    }
    public void Dispose() { UnregisterHotKey(this.Handle, HotkeyId); DestroyHandle(); }
}
"@
}

function New-TrayUI {
  param([scriptblock]$OnStop, [string]$StopEventName='Global\don-studio-stop')
  Add-Type -AssemblyName System.Windows.Forms,System.Drawing
  $tray = New-Object System.Windows.Forms.NotifyIcon
  $iconPath = "$PSScriptRoot\..\assets\tray-icon.ico"
  try { $tray.Icon = New-Object System.Drawing.Icon $iconPath }
  catch { $tray.Icon = [System.Drawing.SystemIcons]::Application }   # m-2 fallback
  $tray.Visible = $true
  $tray.Text = "don-studio recording"
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  ($menu.Items.Add("정지 (Ctrl+Alt+S)")).Add_Click({ & $OnStop })
  ($menu.Items.Add("로그 열기")).Add_Click({ Start-Process explorer.exe -ArgumentList "$PSScriptRoot\..\logs" })
  ($menu.Items.Add("녹화 폴더 열기")).Add_Click({ Start-Process explorer.exe -ArgumentList "$PSScriptRoot\..\recordings" })
  $tray.ContextMenuStrip = $menu

  $hot = New-Object HotkeyWindow
  $hot.OnHotkey = $OnStop
  $ok = $hot.Register([HotkeyWindow]::MOD_CONTROL -bor [HotkeyWindow]::MOD_ALT, 0x53)   # 'S'
  if (-not $ok) {                                                # m-6: 핫키 점유 시 명시 경고
    Write-Log -Level WARN -Message "RegisterHotKey failed (Ctrl+Alt+S already in use). Use tray menu to stop."
    $tray.ShowBalloonTip(3000, "don-studio", "Ctrl+Alt+S가 이미 다른 프로그램에 등록됨. 트레이 메뉴로 정지하세요.", [System.Windows.Forms.ToolTipIcon]::Warning)
  }

  # M-NEW-3: smoke-test stop 신호용 EventWaitHandle 폴링 타이머
  $stopEvt = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, $StopEventName)
  $stopTimer = New-Object System.Windows.Forms.Timer
  $stopTimer.Interval = 500
  $stopTimer.Add_Tick({ if ($stopEvt.WaitOne(0)) { & $OnStop } }.GetNewClosure())
  $stopTimer.Start()

  return [pscustomobject]@{
    Tray = $tray; Hotkey = $hot; StopEvent = $stopEvt; StopTimer = $stopTimer
  }
}

function Dispose-TrayUI($ui) {
  if ($ui.StopTimer) { $ui.StopTimer.Stop(); $ui.StopTimer.Dispose() }
  if ($ui.StopEvent) { $ui.StopEvent.Dispose() }
  if ($ui.Hotkey)    { $ui.Hotkey.Dispose() }
  if ($ui.Tray)      { $ui.Tray.Visible = $false; $ui.Tray.Dispose() }
}
```

#### `lib/upload-core.ps1` — **MJ3 + C-NEW-2 [long] + N2 UTF-8 + 308-noRange + 401 retry-counter + 5xx backoff**
```powershell
function Invoke-ResumableUpload {
  param([string]$FilePath, [hashtable]$Metadata)
  $bytes = [long](Get-Item $FilePath).Length        # [long] 명시
  $token = Get-AccessToken

  # 1) Initiate (UTF-8 인코딩 명시 — N2)
  $jsonStr = $Metadata | ConvertTo-Json -Compress
  $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
  $initResp = Invoke-WebRequest -Method POST `
    -Uri "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status" `
    -Headers @{
      "Authorization"           = "Bearer $token"
      "X-Upload-Content-Type"   = "video/mp4"
      "X-Upload-Content-Length" = "$bytes"
    } `
    -ContentType "application/json; charset=UTF-8" `
    -Body $jsonBytes
  $location = $initResp.Headers["Location"]

  # 2) Chunked PUT — 모두 [long] (C-NEW-2)
  [long]$chunkSize = 8MB
  [long]$offset    = 0
  $fs = [System.IO.File]::OpenRead($FilePath)
  $progressNext = (Get-Date).AddSeconds(60)
  $retry401 = 0
  $retry5xx = 0
  try {
    while ($offset -lt $bytes) {
      [long]$remaining = $bytes - $offset
      [long]$thisChunk = [System.Math]::Min($chunkSize, $remaining)   # 둘 다 [long] → overload OK
      $buf = New-Object byte[] $thisChunk
      $fs.Position = $offset
      $null = $fs.Read($buf, 0, $thisChunk)

      if ((Get-AccessTokenTtlSeconds) -lt 600) { $token = Get-AccessToken -Force }

      try {
        $resp = Invoke-WebRequest -Method PUT -Uri $location `
          -Headers @{
            "Authorization" = "Bearer $token"
            "Content-Range" = "bytes $offset-$($offset + $thisChunk - 1)/$bytes"
          } `
          -ContentType "video/mp4" -Body $buf -UseBasicParsing -ErrorAction Stop

        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300) {
          $obj = $resp.Content | ConvertFrom-Json
          return $obj.id
        }
      } catch [System.Net.WebException] {
        $r = $_.Exception.Response
        $code = [int]$r.StatusCode
        if ($code -eq 308) {
          $rangeHeader = $r.Headers["Range"]
          if ($rangeHeader -and $rangeHeader -match 'bytes=0-(\d+)') {
            $offset = [long]$matches[1] + 1                         # MJ3-A
            continue
          } else {
            $offset = [long]0; continue                              # MJ3-A: no-Range fallback
          }
        } elseif ($code -eq 401) {
          if ($retry401 -ge 2) { throw "401 after 2 token refreshes; aborting" }   # MJ3-B
          $retry401++; $token = Get-AccessToken -Force; continue
        } elseif ($code -ge 500 -and $code -lt 600) {
          if ($retry5xx -ge 3) { throw "5xx after 3 retries; aborting" }            # Critic missing
          $retry5xx++; Start-Sleep -Seconds ([int][Math]::Pow(2, $retry5xx)); continue
        } else { throw }
      }

      $offset += $thisChunk
      $retry5xx = 0    # 정상 청크 시 5xx 카운터 리셋
      if ((Get-Date) -ge $progressNext) {
        $pct = [math]::Round(($offset / $bytes) * 100, 1)
        Write-Log -Message ("[upload] progress: {0}% ({1}/{2} MB)" -f $pct, [math]::Round($offset/1MB,1), [math]::Round($bytes/1MB,1))
        $progressNext = (Get-Date).AddSeconds(60)
      }
    }
    throw "upload loop exited without 2xx response"
  } finally {
    $fs.Close()
  }
}
```

### Step 4 — `start-recording.ps1` (메인 진입)
1. Header (`#Requires -Version 5.1`, `$ErrorActionPreference='Stop'`, TLS 1.2).
2. Dot-source: `lib\dotenv.ps1`, `oauth.ps1`, `window.ps1`, `ffmpeg.ps1`, `lock.ps1`, `log.ps1`, `tray.ps1`.
3. `Acquire-SingleInstanceLock` → 실패 시 토스트 + exit 0.
4. `Read-Dotenv .env` → 필수 키(`CLIENT_ID/CLIENT_SECRET/REFRESH_TOKEN`) 검증 → 누락 시 토스트 + exit 1.
5. **사전 디바이스 검증** (N7): `& bin\ffmpeg.exe -list_devices true -f dshow -i dummy 2>&1 | Select-String "virtual-audio-capturer"` — 없으면 토스트("screen-capture-recorder 설치 필요") + URL 안내 + exit 1.
6. **사전 디스크 검증**: `recordings/` 가 위치한 드라이브의 free space ≥ 5 GB.
7. `Find-HtsWindow` 미발견 → 토스트 + exit 1. `Test-WindowVisible` 실패 → 토스트("창 보이게 두세요") + exit 1.
8. 출력 경로 + ffmpeg stderr 로그:
   ```
   $stamp = Get-Date -Format yyyyMMdd-HHmmss
   $output = "$PSScriptRoot\recordings\$stamp-trade.mp4"
   $ffLog  = "$PSScriptRoot\logs\ffmpeg-$stamp.log"
   ```
9. `$proc = Start-FFmpegRecording -WindowTitle ... -OutputPath $output -StderrLogPath $ffLog`.
10. **시작 검증** (3 s + 2 s):
    ```
    Start-Sleep -Seconds 3
    if ($proc.HasExited) { ... toast + tail $ffLog + exit 1 }
    $size1 = (Get-Item $output).Length
    Start-Sleep -Seconds 2
    if ((Get-Item $output).Length -le $size1) { $proc.Kill(); ... toast + exit 1 }
    Write-Log "[ffmpeg] first frame OK"
    ```
11. `$ui = New-TrayUI -OnStop { [System.Windows.Forms.Application]::Exit() }`.
12. **디스크 감시 타이머**:
    ```
    $diskTimer = New-Object System.Windows.Forms.Timer; $diskTimer.Interval = 300000
    $diskTimer.Add_Tick({
      $drv = (Get-Item $output).PSDrive          # Critic ambiguity 픽스: 정확한 드라이브
      if ((Get-PSDrive $drv).Free -lt 5GB) {
        Write-Log -Level WARN -Message "low disk; auto-stop"
        [System.Windows.Forms.Application]::Exit()
      }
    }); $diskTimer.Start()
    ```
13. `[System.Windows.Forms.Application]::Run()`.
14. **루프 종료 후 정리**:
    ```
    $diskTimer.Stop(); $diskTimer.Dispose()
    Stop-FFmpegRecording -Process $proc
    Get-EventSubscriber | Unregister-Event           # Critic missing: 구독 정리
    Dispose-TrayUI $ui
    Release-SingleInstanceLock
    ```
15. **Detached 업로드 호출** (MJ7 + m-4):
    ```
    Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -WorkingDirectory $PSScriptRoot -ArgumentList @(
      "-NoProfile","-ExecutionPolicy","Bypass","-File","$PSScriptRoot\upload.ps1","-MediaPath",$output
    )
    exit 0
    ```

### Step 5 — `upload.ps1`
```powershell
#Requires -Version 5.1
param([Parameter(Mandatory)] [string]$MediaPath)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Critic M-NEW-4: 명시적 import 리스트
. "$PSScriptRoot\lib\dotenv.ps1"
. "$PSScriptRoot\lib\log.ps1"
. "$PSScriptRoot\lib\oauth.ps1"
. "$PSScriptRoot\lib\upload-core.ps1"

function Show-Toast([string]$Title, [string]$Body) {
  Add-Type -AssemblyName System.Windows.Forms
  $n = New-Object System.Windows.Forms.NotifyIcon
  $n.Icon = [System.Drawing.SystemIcons]::Information
  $n.Visible = $true
  $n.ShowBalloonTip(5000, $Title, $Body, [System.Windows.Forms.ToolTipIcon]::Info)
  Start-Sleep -Seconds 6; $n.Dispose()
}

function Try-Upload([string]$Path) {
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  $title = "매매 기록 " + ($stem -replace '^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2}).*','$1-$2-$3 $4:$5')
  $meta = @{
    snippet = @{ title = $title; description = "" }
    status  = @{ privacyStatus = "private" }
  }
  try {
    $videoId = Invoke-ResumableUpload -FilePath $Path -Metadata $meta
    Write-Log -Message "[upload] success videoId=$videoId path=$Path"
    Remove-Item $Path -Force
    return $true
  } catch {
    Write-Log -Level ERROR -Message "[upload] failed path=$Path err=$_"
    $dest = "$PSScriptRoot\failed-uploads\" + (Split-Path $Path -Leaf)
    Move-Item -Path $Path -Destination $dest -Force
    Show-Toast "don-studio 업로드 실패" "원본은 failed-uploads/ 보존. 다음 실행 시 재시도."
    return $false
  }
}

# 1) failed-uploads/ 큐 먼저 처리
Get-ChildItem "$PSScriptRoot\failed-uploads\*.mp4" -ErrorAction SilentlyContinue | ForEach-Object {
  $null = Try-Upload $_.FullName
}
# 2) 이번 세션 파일 처리
if (Test-Path $MediaPath) { $null = Try-Upload $MediaPath }
exit 0
```

### Step 6 — `install-shortcut.ps1`
```powershell
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\녹화 시작.lnk")
$sc.TargetPath       = "powershell.exe"
$sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\start-recording.ps1`""
$sc.WorkingDirectory = $PSScriptRoot
$sc.IconLocation     = "$PSScriptRoot\assets\tray-icon.ico"
$sc.Save()
```

### Step 7 — `smoke-test.ps1`
- 디바이스 검증: `& bin\ffmpeg.exe -list_devices true -f dshow -i dummy 2>&1 | Select-String "virtual-audio-capturer"` — 없으면 FAIL 즉시.
- Notepad 띄우기 + 임의 텍스트 입력 + `[System.Media.SystemSounds]::Asterisk.Play()` 트리거.
- `WINDOW_TITLE_OVERRIDE=Notepad`로 임시 환경변수 설정.
- `Start-Process powershell -WindowStyle Hidden -ArgumentList "-File","start-recording.ps1"` 백그라운드.
- 10 s 대기 → **EventWaitHandle 신호** (M-NEW-3와 일치):
  ```powershell
  $evt = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Global\don-studio-stop')
  $null = $evt.Set()
  ```
- 업로드 완료 폴링 (`failed-uploads/` 부재 + log success 라인) 최대 5분.
- `videos.list?id=<videoId>&part=status` → `privacyStatus=private` 검증 → 영상 삭제(테스트 정리) → 로컬 mp4 부재 검증.
- 결과: PASS/FAIL 콘솔 출력.

### Step 8 — `README.md`
- 사전 준비:
  1. ffmpeg static-essentials([gyan.dev](https://www.gyan.dev/ffmpeg/builds/)) → `bin\ffmpeg.exe`
  2. screen-capture-recorder 설치 — 실패/미지원 시 v2.x NAudio 경로(ADR follow-up)
  3. Google Cloud Console: 프로젝트 + YouTube Data API v3 활성화 + OAuth Desktop 클라이언트 ID/Secret → `.env`
  4. `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` (1회)
  5. `powershell.exe -File setup-oauth.ps1` → 브라우저 OAuth → `REFRESH_TOKEN` 자동 저장
  6. `powershell.exe -File install-shortcut.ps1`
  7. `powershell.exe -File smoke-test.ps1` (선택, 권장)
- 일상: 영웅문 띄우기(MDI 모드 권장) → 바탕화면 더블클릭 → 트레이 확인 → Ctrl+Alt+S 또는 트레이 메뉴 정지 → 자동 업로드.
- 트러블슈팅: ffmpeg 미존재, virtual-audio-capturer 미존재(설치 가이드 URL), OAuth 만료, quota 소진(403), 디스크 부족, Ctrl+Alt+S 충돌(다른 앱이 점유) → 트레이 메뉴 백업.

---

## Risks and Mitigations

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|-----------|--------|------------|
| R1 | screen-capture-recorder 가상 디바이스 부재 | Mid | High | start-recording 시작 시 + smoke-test에서 `-list_devices` 검증, 부재 시 토스트 + URL |
| R2 | 영웅문 윈도우 타이틀 변경 | Mid | Mid | `WINDOW_TITLE_OVERRIDE` env, title 우선/process 보조 매칭 |
| R3 | OAuth refresh token 취소 | Low | High | 401 → setup-oauth 안내, mp4는 `failed-uploads/` 보존 |
| R4 | YouTube quota 소진 | Low | Mid | 403 → 자정+5분 재시도 / `failed-uploads/` 보존 |
| R5 | 디스크 부족 | Mid | High | 시작 전 + 5분 주기 검사(정확한 드라이브 기준), <5GB 시 graceful stop |
| R6 | 영웅문 창 minimize | High UX | Mid | `Test-WindowVisible` 시작 검사, README 명시 |
| R7 | ffmpeg 비정상 종료 | Low | Mid | stderr 로그 항시 캡처(`-MessageData`), 5분 graceful, faststart 제거로 정상 케이스 손상 0 |
| R8 | PowerShell ExecutionPolicy 차단 | Low | High | 바로가기 `-ExecutionPolicy Bypass`, README 1회 안내 |
| R9 | NotifyIcon 트레이 오버플로 (Win11) | Mid | Low | 핫키 백업 정상(C1 픽스), 핫키 충돌 시 토스트 경고(m-6) |
| R10 | mutex 잔존 | Low | Low | OS가 프로세스 종료 시 해제 + 명시적 dispose |
| R11 | screen-capture-recorder 미유지(2020 이후) | Mid (장기) | High | smoke-test 검증 + ADR follow-up: NAudio→ffmpeg-pipe 대체 v2.x 예약 |
| R12 | gdigrab `title=` 한글/특수문자 | Mid | Mid | hwnd 모드 fallback (ffmpeg 4.x+) — 1차 실패 시 자동 스위치 |
| R13 | 장시간 업로드가 새 녹화 차단 | High | Mid | upload.ps1 detached 프로세스 + 별도 mutex 없음 (MJ7) |
| R14 | access_token 1h TTL 초과 | Mid | Mid | 매 청크 전 TTL<10min force refresh, 401 catch → 갱신 후 재시도 (max 2) |
| R15 | 영웅문 다중 창 모드 | Mid | Mid | README MDI 권장, `WINDOW_TITLE_OVERRIDE` 수동 지정 |
| R16 | Ctrl+Alt+S 다른 앱 점유 | Low | Mid | RegisterHotKey false → 토스트 경고 + 트레이 메뉴 사용 안내 (m-6) |
| R17 | tray-icon.ico 누락 | Low | Low | SystemIcons.Application fallback (m-2) |

---

## Verification Steps

### 자동 (smoke-test.ps1)
1. `virtual-audio-capturer` 디바이스 enumerable 검증.
2. Notepad 10 s 녹화 → mp4 생성, `ffprobe` duration ≈ 10 s, audio stream 존재.
3. EventWaitHandle 신호로 정지 → 업로드 → `videos.list` privacyStatus=private 확인 → 영상 삭제 → 로컬 mp4 부재 검증.
4. PASS/FAIL 콘솔 출력.

### 단위 (Pester 권장)
- `lib/oauth.ps1`: 200/401/만료 시나리오 mock → 캐시·강제 갱신.
- `lib/window.ps1`: Notepad/Calculator 매칭 + `WINDOW_TITLE_OVERRIDE` 우선순위.
- `lib/lock.ps1`: 동시 두 인스턴스 → 두 번째 false.
- `lib/upload-core.ps1`: 308 (Range 있음/없음), 401 (재시도/한계 초과), 5xx (백오프), >2GB offset 시뮬.

### 수동 (release gate, AC 매핑)
- AC1·AC2: stopwatch + 로그.
- AC3·AC4: 30 s 영웅문 녹화 → 시청·청취.
- AC5–AC9: 시뮬레이션.
- AC10: 6 h Calculator 녹화 → `ffprobe -show_format -show_streams` per-stream duration + clapboard.
- AC11: 큰 파일 업로드 시 60 s 간격 progress 라인 확인.

---

## ADR (Architectural Decision Record)

### Decision
영웅문 매매 녹화 + YouTube 비공개 업로드 도구를 **PowerShell 5.1 + ffmpeg(`gdigrab` + dshow `virtual-audio-capturer`) + `.env` 자격증명** 단일 사용자 스택으로 구현한다.

### Drivers
1. 콘텐츠 품질 1순위(Round 2)
2. 운영 단순성(Round 1·6)
3. 비용 0원 + 1인 운영(Round 7)

### Alternatives Considered
- **B (Stereo Mix)**: invalidated — 하드웨어 의존성.
- **C (NAudio→ffmpeg pipe)**: 단일 ffmpeg 파이프라인 가능(P2 동등). P1·P4에서 우위. **본 v1에서는 단일 ffmpeg 명령어 디버깅 단순성·코드량 최소화 측면에서 A 선택. v2.x follow-up으로 보존.**

### Why Chosen
A는 단일 ffmpeg 명령어로 audio/video mux 자동, 코드 라인 수 최소, 단일 사용자에게 1회 driver 설치 부담 수용 가능.

### Consequences
- (+) 구현 단순.
- (+) PS 5.1만 필요 — 모든 Win10/11 기본 탑재.
- (–) screen-capture-recorder 미유지 위험(R11) — 향후 NAudio 마이그레이션 가능성.
- (–) 시스템 전역 audio mix → 다른 앱 음 혼입(P4 부분 약점, ADR 명시).
- (–) 영웅문 다중 창 모드 사용 시 메인 프레임만 캡처(R15).

### Follow-ups
1. **v2.x**: NAudio→ffmpeg-pipe audio 경로 (R11 mitigation, P1·P4 강화).
2. **v2.x**: PKCE OAuth (defense-in-depth).
3. **v2.x**: 영웅문 다중 창 자동 합성 (`xstack` 필터).
4. **모니터링**: smoke-test 일별 실행해 virtual-audio-capturer enumerable 자동 알림.

---

## Iteration Changelog

### v1 (rejected)
- Critic: 2 CRITICAL (WM_HOTKEY 누락, faststart 손상 체인) + 8 MAJOR + 7 MINOR.

### v2 (Architect APPROVE_WITH_IMPROVEMENTS, Critic APPROVE_WITH_IMPROVEMENTS)
- 모든 v1 결함 해결 + 신규 발견 4 must-fix.

### Final (이 문서)
**CRITICAL 픽스 (2):**
- C-NEW-1: `Register-ObjectEvent` `$using:ffLog` → `-MessageData $ffLog` + `$Event.MessageData` (PS 5.1에서 `$using:` 동작 안 함).
- C-NEW-2: 업로드 모든 산술 `[long]` 명시 (Int32 8MB + Int64 remaining → `[math]::Min` 충돌 방지, >2GB 파일 정상 처리).

**MAJOR 픽스 (5):**
- M-N2: `[System.Text.Encoding]::UTF8.GetBytes($json)`로 사전 인코딩 (Korean title 보존).
- M-MJ3-A: 308 응답에 Range 헤더 부재 시 `else { $offset = [long]0; continue }`.
- M-MJ3-B: 401 retry counter (max 2).
- M-NEW-3: 구체적 smoke-test 정지 메커니즘 — `Forms.Timer 500ms + EventWaitHandle.WaitOne(0)`.
- M-NEW-4: `upload.ps1`에 dot-source import 명시 리스트 추가.

**MINOR 픽스 (7):**
- m-1: BOM 제거 `TrimStart([char]0xFEFF)` (정규식 dead code 교체).
- m-2: tray-icon.ico 누락 → `SystemIcons.Application` fallback (try/catch).
- m-3: AC1 5 s → 8 s (validation 시간 마진 확보).
- m-4: `Start-Process -WorkingDirectory $PSScriptRoot` 명시.
- m-5: AC2 floor 1 s → "일반 1–3 s, max 300 s"로 완화.
- m-6: `RegisterHotKey` 반환값 검증 → false 시 토스트 경고.
- 5xx 백오프 (지수 backoff, max 3) + `Get-AccessTokenTtlSeconds` 함수 정의 + `Get-EventSubscriber | Unregister-Event` 정리 + 디스크 드라이브 정확화 + `$ErrorActionPreference='Stop'` 헤더.

**합의 통과 시점:** 2026-04-27.

