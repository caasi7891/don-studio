# Deep Interview Spec: don-studio (영웅문 → YouTube Private 매매 녹화)

## Metadata
- **Project Name**: `don-studio`
- **Repository / CWD**: `<repo-root>/don-studio`
- Interview ID: `don-studio-2026-04-27`
- Rounds: 7
- Final Ambiguity Score: **18%**
- Type: greenfield
- Generated: 2026-04-27
- Threshold: 20%
- Status: **PASSED**
- User Scope: single user (the user themselves only — no distribution)

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.85 | 0.40 | 0.340 |
| Constraint Clarity | 0.85 | 0.30 | 0.255 |
| Success Criteria | 0.75 | 0.30 | 0.225 |
| **Total Clarity** | | | **0.820** |
| **Ambiguity** | | | **0.180 (18%)** |

## Goal
한 번의 바탕화면 아이콘 클릭으로 **영웅문 foreground window**의 영상과 **시스템 사운드(WASAPI loopback)**를 녹화하고, 정지 시 그 결과를 **YouTube에 비공개(private)로 자동 업로드**한 뒤 업로드 성공 시 로컬 원본을 자동 삭제하는, **본인 전용 PowerShell + ffmpeg 기반 도구**를 만든다.

## Constraints
- **OS**: Windows (영웅문이 Windows 전용이므로). PowerShell 5.1+ 또는 PowerShell 7 가정.
- **개발/운영 비용 0원**: ffmpeg(LGPL/GPL 빌드), PowerShell, YouTube Data API v3 무료 쿼터(기본 10,000 units/day), Google Cloud 무료 프로젝트.
- **기술 스택**: PowerShell (.ps1) + ffmpeg.exe + YouTube Data API v3 (REST 호출, .NET HttpClient 또는 `Invoke-RestMethod`).
- **자격증명 보관**: 스크립트와 같은 폴더의 `.env` 파일에 사용자가 직접 기입 (`CLIENT_ID`, `CLIENT_SECRET`, `REFRESH_TOKEN`). 평문 보관(단일 사용자, 본인 PC).
- **사용자 인터랙션**:
  - **시작**: 바탕화면 바로가기(`녹화 시작.lnk`) 클릭 → `start-recording.ps1` 실행.
  - **정지**: 시스템 트레이 아이콘 메뉴 + 글로벌 단축키. PowerShell에서 `[System.Windows.Forms.NotifyIcon]` + Win32 P/Invoke `RegisterHotKey`로 구현.
- **녹화 범위**: 영웅문의 foreground window만 (전체 화면·다른 앱 미포함).
- **오디오**: 시스템 사운드(WASAPI loopback) 단일 트랙. 마이크 미사용.
- **파일 라이프사이클**: 업로드 성공 시 로컬 원본 자동 삭제. 업로드 실패 시 원본 보존 + 로그에 기록 + 다음 실행에서 재시도 큐 처리.
- **단일 인스턴스**: 이미 녹화 중이면 새 시작 클릭은 무시(또는 토스트 알림).

## Non-Goals (명시적 제외)
- 다중 사용자 배포·EXE 패키징·코드 서명.
- 마이크/사용자 해설 녹음 및 오디오 믹싱.
- 영웅문이 아닌 다른 프로그램의 녹화.
- 실시간 영상 편집·자동 자막·썸네일 생성.
- 비공개 외 공개 범위(public, unlisted) 업로드.
- 영웅문 자동 매매/주문 연동.
- 듀얼 모니터 합성·풀스크린·영역 지정 캡처.

## Acceptance Criteria
- [ ] 바탕화면 바로가기를 클릭하면 5초 이내 영웅문 foreground window 녹화가 시작된다.
- [ ] 시스템 트레이 아이콘 메뉴 또는 글로벌 단축키로 녹화가 즉시 정지된다.
- [ ] 녹화된 mp4(H.264 + AAC) 파일에서 영웅문의 호가창·주문창의 텍스트가 사람이 읽을 수 있는 수준으로 보인다 (기본값: 1920×1080 30fps H.264 medium, AAC 128kbps).
- [ ] 녹화된 파일에서 영웅문의 시스템 사운드(체결음·알림음)가 들린다.
- [ ] 녹화 정지 후 자동으로 YouTube Data API v3 비공개 업로드가 시작된다.
- [ ] 업로드 성공 시 (HTTP 200 + videoId 회신) 로컬 원본 mp4가 자동 삭제된다.
- [ ] 업로드 실패 시 원본은 보존되고, 다음 실행 시 자동 재시도된다.
- [ ] `.env`의 `REFRESH_TOKEN`만으로 매 실행마다 access token을 자동 갱신한다 (재로그인 불필요).
- [ ] 이미 녹화 중인 상태에서 시작 바로가기를 다시 클릭해도 두 번째 ffmpeg 인스턴스는 띄워지지 않는다.
- [ ] 6시간 연속 녹화 중 프레임 드롭/오디오 비동기 없이 동작한다 (Constrant Clarity 보조 검증).

## Assumptions Exposed & Resolved
| Assumption | Challenge (어느 라운드) | Resolution |
|------------|-----------------------|------------|
| 클릭하면 시작, 정지는 자동 | Round 1 (Goal 약점 타겟팅) | **트레이 아이콘 + 글로벌 단축키**로 명시적 정지 |
| 영웅문 창만 녹화하면 충분 | Round 4 (Contrarian 모드) | 의도적으로 창만 — 개인정보·산만함 제거가 풀스크린 맥락보다 중요 |
| 풀 오디오(시스템+마이크 믹싱)가 필요 | Round 6 (Simplifier 모드) | **시스템 사운드만**으로도 가치 충분 — 마이크 미사용 |
| "비용 0원" = 단일 .exe 패키징 | Round 3 → Round 7 (사후 번복) | **PowerShell + ffmpeg + .env** — 본인 1인 전용이므로 빌드·서명·배포 부담 모두 제거 |
| 업로드 후 원본을 보관해야 안전 | Round 5 | YouTube 비공개 자체가 백업이므로 **업로드 성공 시 자동 삭제**, 실패 시에만 보존 |

## Technical Context (Greenfield)

### 권장 기술 구성
- **녹화**:
  - 영상 캡처: `ffmpeg -f gdigrab -framerate 30 -i title="영웅문..."` 또는 `-i desktop` 후 후처리 crop. 영웅문의 정확한 윈도우 타이틀은 실행 시 `Get-Process`로 동적 조회.
  - 오디오 캡처: `ffmpeg -f dshow -i audio="virtual-audio-capturer"` 또는 ffmpeg 빌드의 WASAPI 지원 활용. 더 깔끔한 옵션은 [`screen-capture-recorder`](https://github.com/rdp/screen-capture-recorder-to-video-windows-free) (무료) 가상 디바이스.
  - 컨테이너: mp4 (H.264 video + AAC audio).
- **트레이 아이콘 + 단축키**:
  - PowerShell `Add-Type -AssemblyName System.Windows.Forms` → `NotifyIcon`.
  - 글로벌 단축키: `RegisterHotKey` Win32 P/Invoke로 등록.
  - 정지 시 `Stop-Process -Id $ffmpegPid` (graceful: 먼저 `q` 키 stdin 입력 후 timeout 시 강제 종료).
- **YouTube 업로드**:
  - YouTube Data API v3 `videos.insert` (resumable upload, multipart).
  - Scope: `https://www.googleapis.com/auth/youtube.upload`.
  - Refresh token 흐름으로 access token 자동 갱신.
  - `privacyStatus: "private"` 고정.
- **디렉터리 구조 제안**:
  ```
  trade-recorder/
    start-recording.ps1     # 시작 + 트레이 아이콘 호스팅
    upload.ps1              # 업로드 + 자동 삭제 + 재시도 큐
    .env                    # CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN (gitignore)
    bin/ffmpeg.exe          # 동봉 또는 PATH 활용
    recordings/             # 녹화 임시 저장 (업로드 후 비워짐)
    failed-uploads/         # 업로드 실패 큐
    logs/recorder.log       # 일일 로그
  ```
- **첫 실행 OAuth 셋업 (1회성, 사용자 본인이 수행)**:
  1. Google Cloud Console에서 프로젝트 생성 → YouTube Data API v3 활성화.
  2. OAuth 2.0 클라이언트 ID 생성 (Desktop application 타입).
  3. `client_id` / `client_secret`을 `.env`에 저장.
  4. 별도 `setup-oauth.ps1` 1회 실행 → 브라우저로 OAuth consent → 받은 `refresh_token`을 `.env`에 추가.

### 기본값 (실행자가 별도 결정 가능)
- 해상도: 1920×1080 (영웅문 창 크기에 맞춰 자동 조정 가능).
- 프레임레이트: 30fps.
- 비트레이트: video CRF 23 (medium preset), audio AAC 128kbps.
- 파일명 규칙: `yyyyMMdd-HHmmss-trade.mp4`.
- 업로드 제목 기본값: `매매 기록 yyyy-MM-dd HH:mm`.
- 업로드 설명 기본값: 빈 문자열 (사용자가 YouTube Studio에서 후편집).

## Ontology (Key Entities)

| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| Desktop Shortcut | core | name, target_script, icon | triggers Recording Session |
| Tray Icon | supporting | icon_handle, context_menu | controls Recording Session |
| Hotkey | supporting | key_combo, scope=global | stops Recording Session |
| 영웅문 (Kiwoom HTS) | external system | window_handle, process_name | recorded by Recording Session |
| Recording Session | core | start_time, end_time, output_path, ffmpeg_pid | produces Recording File |
| Recording File | core | path, duration, size, codec | uploaded by Upload Job |
| YouTube Private Video | external system | video_id, privacy_status=private | created by Upload Job |
| Trade Action | core (acceptance signal) | visual_clarity, audio_clarity | observable in Recording File |
| .env Credentials | supporting | CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN | authorizes Upload Job |
| Upload Job | core (process) | file_path, status, retry_count | bridges Recording File ↔ YouTube Private Video |
| PowerShell Tool | supporting | start-recording.ps1, upload.ps1, setup-oauth.ps1 | hosts all sessions |

## Ontology Convergence

| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 6 | 6 | - | - | N/A |
| 2 | 7 | 1 (Trade Action) | 0 | 6 | 86% |
| 3 | 8 | 1 (Single Executable) | 0 | 7 | 88% |
| 4 | 8 | 0 | 0 | 8 | 100% |
| 5 | 8 | 0 | 0 | 8 | 100% |
| 6 | 8 | 0 | 0 | 8 | 100% |
| 7 | 9–10 | 1 (.env Credentials) + 1 (Upload Job 명시화) | 1 (Single Executable → PowerShell Tool, 같은 type/배포 산출물 역할 유지) | 8 | 89% |

수렴 신호: Round 4–6 동안 100% 안정 → Round 7에서 사용자 의도적 stack 변경으로 1개 renamed + 1개 추가. **renamed는 stability에 포함**(개념 지속, 이름만 변경).

## Interview Transcript

<details>
<summary>Full Q&A (7 rounds)</summary>

### Round 1 — Goal Clarity 타겟
**Q:** 바탕화면 아이콘을 한 번 클릭하면 녹화가 시작된다고 하셨는데, 녹화는 어떻게 종료(정지)되어야 하나요?
**A:** 시스템 트레이 + 핫키
**Ambiguity:** 71.5% (Goal: 0.45, Constraints: 0.25, Criteria: 0.10)

### Round 2 — Success Criteria 타겟
**Q:** 이 프로그램이 "성공적으로 작동했다"고 판단하실 가장 결정적인 기준 한 가지는 무엇입니까?
**A:** 매매 행동이 올바로 보이고 들린다 (콘텐츠 품질 우선)
**Ambiguity:** 58% (Goal: 0.45, Constraints: 0.25, Criteria: 0.55)

### Round 3 — Constraint Clarity 타겟
**Q:** "개발 비용 0원" 제약을 만족하면서, 이 도구를 어떤 형태로 설치/실행하는 게 가장 자연스러운가요?
**A:** 단일 .exe 파일 (종속성 없음) — *Round 7에서 사용자 본인이 번복*
**Ambiguity:** 49% (Goal: 0.45, Constraints: 0.55, Criteria: 0.55)

### Round 4 — Goal Clarity (Contrarian 모드)
**Q:** 녹화 범위 가정을 다시 검증. 풀스크린/멀티모니터가 더 나을 수 있다는 도전. "나의 매매 영상"에 가장 가까운 시나리오는?
**A:** 영웅문 창만 (foreground window capture) — 가정이 의도적이었음을 확인 (Contrarian 검증 통과)
**Ambiguity:** 43% (Goal: 0.60, Constraints: 0.55, Criteria: 0.55)

### Round 5 — Constraint Clarity 타겟
**Q:** 녹화 종료 후 YouTube 비공개 업로드가 끝나면, 로컬 원본 영상 파일은 어떻게 처리해야 하나요?
**A:** 업로드 성공 시 자동 삭제 (실패 시 보존 + 재시도 함의)
**Ambiguity:** 38.5% (Goal: 0.60, Constraints: 0.70, Criteria: 0.55)

### Round 6 — Success Criteria (Simplifier 모드)
**Q:** 가장 단순한 형태로도 가치가 있으려면, 영상에서 "무엇이 들리면 충분"한가요?
**A:** 영웅문 시스템 사운드만 (체결음·알림) — 마이크/믹싱 제거 (Simplifier 통과)
**Ambiguity:** 22.5% (Goal: 0.85, Constraints: 0.70, Criteria: 0.75)

### Round 7 — Constraint Clarity 타겟
**Q:** YouTube API 비공개 업로드를 위한 OAuth 자격증명을 누가/어떻게 준비하는 게 자연스러울까요?
**A (자유 입력):** "그냥 ffmpeg랑 powershell 형태로 가자. .env에다 사용자가 넣을게. 사용자는 나 혼자거"
- 효과: Round 3 결정(.exe 빌드) 번복 → PowerShell + ffmpeg + .env. 단일 사용자 명시.
**Ambiguity:** 18% ✅ 임계값 통과

</details>
