# don-studio

> 영웅문(키움 HTS)으로 매매하는 화면을 시스템 사운드와 함께 녹화하고, 정지 즉시 YouTube 비공개 영상으로 자동 업로드하는 **본인 1인용 PowerShell 도구**.

```
바탕화면 더블클릭 → ffmpeg가 영웅문 창 + 시스템 사운드 녹화
       ↓
Ctrl+Alt+S 또는 트레이 메뉴 정지
       ↓
YouTube 비공개 업로드 (resumable, chunked)
       ↓
업로드 성공 시 로컬 mp4 자동 삭제 / 실패 시 보존 + 다음 실행에서 재시도
```

- **비용 0원**: PowerShell 5.1 + ffmpeg + 무료 Google Cloud 프로젝트.
- **Windows 전용 (영웅문 자체가 Windows 한정).**
- **본인 1인 PC 한정** — `.env`에 자격증명 평문 저장. 배포·다중 사용자 시나리오 비고려.

## 왜 이렇게 만들었나

- **OBS Studio + 자동 업로드 매크로**도 가능하지만, 매매 직후 손이 더 많이 간다. "한 클릭 시작 / 한 단축키 정지 / 자동 업로드"의 한 손 흐름이 핵심.
- 단일 사용자 한정이라 **EXE 빌드·코드 서명·verification 부담을 모두 제거**. PowerShell 스크립트 + ffmpeg 바이너리 + `.env`만으로 동작.
- 설계 과정 (deep-interview → consensus plan) 전체 기록은 [`.omc/specs/`](./.omc/specs/) 와 [`.omc/plans/`](./.omc/plans/) 에 보존되어 있다.

---

## 1. 사전 준비 (1회성)

### 1-1. ffmpeg
1. <https://www.gyan.dev/ffmpeg/builds/>의 **release essentials**(static) 다운로드.
2. 압축 풀어 `ffmpeg.exe`, `ffprobe.exe`를 `bin/`에 복사.
3. 검증: `.\bin\ffmpeg.exe -version`

### 1-2. screen-capture-recorder (가상 오디오 디바이스)
1. <https://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases>에서 인스톨러 다운로드.
2. 설치 후 PC 재부팅 권장.
3. 검증:
   ```powershell
   .\bin\ffmpeg.exe -hide_banner -list_devices true -f dshow -i dummy 2>&1 | Select-String "virtual-audio-capturer"
   ```
   결과에 `"virtual-audio-capturer"` 줄이 나와야 함.

> ℹ️ 이 프로젝트가 미유지(2020 이후) 상태. 작동하지 않으면 [`.omc/plans/don-studio-consensus-plan.md`](./.omc/plans/don-studio-consensus-plan.md)의 ADR follow-up에 NAudio→ffmpeg-pipe 대체 경로 명시.

### 1-3. Google Cloud / OAuth
1. <https://console.cloud.google.com/>에서 새 프로젝트 생성.
2. **APIs & Services → Library** → *YouTube Data API v3* **활성화**.
3. **APIs & Services → OAuth 동의 화면**:
   - User Type: **External / Testing**.
   - 본인 Google 계정을 **Test users**에 추가.
4. **APIs & Services → Credentials → + Create credentials → OAuth client ID**:
   - Application type: **Desktop app**.
   - Client ID / Client secret 보관.
5. `.env.example`을 복사해 `.env` 만들고 채우기:
   ```
   CLIENT_ID=...apps.googleusercontent.com
   CLIENT_SECRET=...
   REFRESH_TOKEN=
   ```
   (`REFRESH_TOKEN`은 다음 단계에서 자동 발급)

### 1-4. PowerShell 실행 정책 (1회성)
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 1-5. OAuth refresh_token 발급
```powershell
.\setup-oauth.ps1
```
브라우저 → 본인 Google 계정 로그인 → "허용" → "OAuth 등록 완료" 페이지 닫기. 자동으로 `.env`에 `REFRESH_TOKEN=` 라인이 추가됨.

### 1-6. 바탕화면 바로가기
```powershell
.\install-shortcut.ps1
```
바탕화면에 `녹화 시작.lnk` 생성.

### 1-7. (권장) Smoke test
영웅문 켜기 전 Notepad로 전 구간 자동 검증:
```powershell
.\smoke-test.ps1
```
업로드 후 테스트 영상은 자동 삭제됨. (`[FAIL] privacy/cleanup verification` 한 줄은 `youtube.upload` 스코프 한계로 발생하는 정상 동작 — 테스트 영상은 YouTube Studio에서 수동 삭제.)

---

## 2. 일상 사용

1. 영웅문(영웅문4 등) 실행. **MDI 단일 창 모드 권장** — 다중 창 모드 시 메인 프레임만 캡처됨.
2. 바탕화면 `녹화 시작.lnk` 더블클릭. 시스템 트레이에 don-studio 아이콘 등장.
3. 매매 종료 시 정지:
   - 트레이 아이콘 우클릭 → **"정지 (Ctrl+Alt+S)"**, 또는
   - 어디서나 **`Ctrl+Alt+S`** 단축키.
4. 정지 즉시 ffmpeg가 graceful 종료 + 백그라운드 PowerShell이 YouTube 비공개 업로드.
5. 업로드 성공 시 `recordings/`의 mp4가 자동 삭제. 실패 시 `failed-uploads/`에 보존 → 다음 실행에서 자동 재시도.

업로드 진행 상황 확인:
```powershell
Get-Content "logs\recorder-$(Get-Date -Format yyyyMMdd).log" -Tail 30
```

---

## 3. 주의 / 한계

- **`.env`는 평문 자격증명 저장소**. 다른 사람과 공유 금지. `.gitignore`에 포함됨.
- **영웅문 창을 최소화하지 말 것** — gdigrab은 보이는 픽셀만 캡처.
- **다중 창 모드 시** 메인 프레임만 녹화. 호가창/주문창을 별도 popup으로 분리해 쓰면 잘려 나감.
- **시스템 사운드는 PC 전체 mix**가 캡처됨. 녹화 중 디스코드·브라우저 알림 등은 끄는 것이 안전.
- **YouTube quota** 기본 10,000 units/day, 1 업로드 ≈ 1,600 units → **약 6회/일** 한도. quota 초과 시 자정 이후 재시도.
- **영웅문 창 크기가 홀수**(예: 2554×1363)여도 자동으로 1픽셀만 잘라 짝수로 맞춤 (libx264 yuv420p 요구사항).
- **장시간 녹화**: 1080p 30fps CRF23 기준 약 4 GB/시간. 디스크 여유 < 5 GB가 되면 자동 정지.
- **업로드 토큰 만료**: 1시간 TTL. 매우 큰 파일(>5 GB)은 업로드 중 자동 갱신.

---

## 4. 트러블슈팅

| 증상 | 대처 |
|------|------|
| `.env not found` 토스트 | `.env.example` 복사해 `.env`로 만들고 키 채우기. |
| `virtual-audio-capturer 디바이스가 없습니다` | screen-capture-recorder 재설치 + PC 재부팅. |
| `영웅문 창을 찾지 못했습니다` | 영웅문이 실행 중인지 확인. 타이틀이 다르면 `.env`의 `WINDOW_TITLE_OVERRIDE=영웅문...` 으로 부분 일치 패턴 지정. |
| `영웅문 창이 최소화/숨김 상태` | gdigrab은 보이는 픽셀만. 창을 띄워둔 채로 재시도. |
| `녹화 파일이 생성되지 않았습니다` | `logs/ffmpeg-<시각>.log` 끝부분 확인. 흔한 원인: 디바이스 점유, 코덱 파라미터 충돌. |
| `Ctrl+Alt+S` 안 먹음 | 다른 앱(엔비디아 ShadowPlay, OBS, 디스코드 등)이 단축키 점유. **트레이 메뉴 "정지"** 사용. |
| 업로드 실패 토스트 | `failed-uploads/`에 mp4 보존됨. 인터넷 복구 후 `start-recording.ps1` 다시 실행하면 큐 자동 드레인. |
| `403 quotaExceeded` | YouTube Data API 일일 quota 초과. 자정 이후 재시도. |
| 디스크 < 5 GB 자동 정지 | `recordings/` 드라이브 공간 확보 후 재시작. |
| 트레이 아이콘이 안 보임 (Win11 오버플로) | 시스템 트레이 ↑ 버튼 → don-studio 아이콘 우클릭 → "작업 표시줄에 표시". |

---

## 5. 디렉터리 구조

```
don-studio/
  start-recording.ps1     # 메인: ApplicationContext + 트레이 + 핫키 + ffmpeg
  upload.ps1              # detached 업로더 (failed-uploads/ 큐도 처리)
  setup-oauth.ps1         # 1회성 refresh_token 발급 (state CSRF guard)
  install-shortcut.ps1    # 바탕화면 바로가기 생성
  smoke-test.ps1          # Notepad 기반 E2E 자동 검증
  .env.example            # 자격증명 템플릿
  bin/                    # ffmpeg.exe / ffprobe.exe (gitignore)
  lib/
    dotenv.ps1            # .env 파서 (BOM·따옴표 처리)
    log.ps1               # 일자별 로그
    lock.ps1              # Named Mutex (AbandonedMutexException 처리)
    oauth.ps1             # access_token 캐시(600s TTL margin) + 갱신
    window.ps1            # 영웅문 창 탐색 + 가시성 검사 + override
    ffmpeg.ps1            # ProcessStartInfo + crop=짝수 + graceful stop(5min)
    tray.ps1              # NotifyIcon + WM_HOTKEY NativeWindow + Forms.Timer
    upload-core.ps1       # YouTube resumable chunked upload (8 MiB, [long] 산술,
                          # UTF-8 body, 308/401/5xx 처리, 60s progress)
  recordings/             # 임시 mp4 (업로드 성공 시 비워짐)
  failed-uploads/         # 업로드 실패 큐
  logs/                   # 일자별 recorder + ffmpeg stderr
  assets/tray-icon.ico    # 선택 — 누락 시 SystemIcons.Application 자동 fallback
  .omc/
    specs/                # deep-interview spec (인터뷰 7라운드, 모호도 18%)
    plans/                # ralplan consensus plan (Architect/Critic 2 iteration)
```

---

## 6. 설계 메모

이 프로젝트는 *deep-interview → ralplan consensus → autopilot* 3단계 파이프라인으로 짜였다:

1. **Deep Interview** ([`.omc/specs/deep-interview-trade-recorder.md`](./.omc/specs/deep-interview-trade-recorder.md))
   - 7라운드 Socratic 질문, Contrarian/Simplifier 모드 적용.
   - 모호도 100% → **18%** (임계값 ≤ 20%).
2. **Ralplan Consensus** ([`.omc/plans/don-studio-consensus-plan.md`](./.omc/plans/don-studio-consensus-plan.md))
   - Planner → Architect → Critic 합의 루프.
   - v1 REJECT(2 CRITICAL + 8 MAJOR) → v2 APPROVE_WITH_IMPROVEMENTS.
   - 14개 외과적 픽스 통합 (`$using:` 함정, `[long]` overflow, UTF-8 인코딩, 308/401 핸들링 등).
3. **Autopilot** — Phase 2(Execution) → Phase 3(QA = AST) → Phase 4(Architect/Security/Code-reviewer 3중 검증).

---

## 7. 라이선스 / 종속 컴포넌트

- 본 저장소 코드: 개인 사용. 라이선스 별도 명시 없음(원하시면 PR 환영).
- ffmpeg: LGPL/GPL static 빌드(gyan.dev) — 개인 사용 OK.
- screen-capture-recorder: MIT.
- YouTube Data API v3: Google 무료 quota 한도 내 사용.

---

## 8. 면책

- 본 도구는 1인 사용을 가정하며, 매매 영상의 법적·세무적 활용 가능 여부는 사용자가 판단.
- YouTube ToS·키움증권 약관·개인정보보호법 등 관련 규정은 사용자 책임.
- 코드는 *현 상태 그대로(as-is)* 제공. 매매 손실·데이터 손실에 대한 책임 없음.
