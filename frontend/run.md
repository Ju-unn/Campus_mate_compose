# 실행 방법

Supabase 키는 소스에 넣지 않고 실행할 때 주입한다.

## 개발 실행

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

소셜 로그인(시작 화면)을 쓰려면 `--dart-define=KAKAO_NATIVE_APP_KEY=...` `--dart-define=GOOGLE_WEB_CLIENT_ID=...` 를 함께 넣고, 안드로이드 빌드에는 카카오 복귀 스킴용으로 같은 이름 `KAKAO_NATIVE_APP_KEY` 를 환경변수나 `android/local.properties` 에도 둔다(없으면 빌드는 되고 버튼만 실패 토스트).

**`flutter run`(디버그 서명)의 한계 — 소셜 로그인이 실패한다(2026-10-14 확인).** 카카오 · 구글 로그인과 Firebase 는 앱 서명 지문으로 앱을 알아보는데, 등록된 지문은 아래 두 키뿐이고 **디버그 서명은 어디에도 등록돼 있지 않다.** 그래서 `flutter run` · `--debug` 빌드는 화면 시험은 되지만 로그인 뒤 화면은 못 본다. 폰에서 로그인까지 시험하려면 둘 중 하나다:

- **릴리스 APK(업로드 키 서명)** — `flutter build apk --release ...` 뒤 `adb install`. 단 폰에 구글 플레이로 설치한 앱이 있으면 서명이 달라(아래 "구글 앱 서명 키") 덮어쓸 수 없다 — 지우고 깔거나 아래 내부 테스트를 쓴다
- **구글 플레이 내부 테스트 AAB** — 아래 "AAB 빌드" 로 만들어 플레이 콘솔 내부 테스트 트랙에 올리고 폰에서 플레이로 받는다(인앱결제 샌드박스 시험도 이 길이다)

### 안드로이드 서명 키 (값은 지문만 — 키 파일 · 비밀번호는 저장소 밖)

플레이 앱 서명을 켜 두어 키가 둘이다. 사용자에게 가는(플레이로 설치한) 앱은 구글 키로 다시 서명된다 — **업로드 키 지문만 등록하면 플레이 설치본의 로그인이 막힌다.** 두 키의 SHA-1 · SHA-256 을 Firebase 안드로이드 앱에, 구글 클라우드 OAuth 안드로이드 클라이언트에, 카카오 키 해시를 카카오 개발자 콘솔에 모두 등록했다(2026-10-14, 플레이 설치본에서 카카오 · 구글 로그인 성공 — 사용자 확인).

| 키 | 쓰는 곳 | SHA-1 | 카카오 키 해시 |
| --- | --- | --- | --- |
| **업로드 키**(릴리스 키스토어 — `android/key.properties` 가 가리킨다, gitignore 대상) | 직접 `adb install` 한 릴리스 APK · 플레이에 올리는 AAB | `63:56:4E:B2:1A:B0:F4:82:BC:3E:54:CE:2C:CC:B6:73:7A:3A:5B:EC` | (기록 없음) |
| **구글 앱 서명 키**(플레이가 보관) | 구글 플레이로 설치한 앱 | `3C:65:10:99:A7:8C:5D:D1:64:30:2D:CF:19:0A:A1:26:85:7C:6F:CE` | `PGUQmaeMXdFkMC3PGQqhJoV8b84=` |

구글 앱 서명 키 지문은 폰의 플레이 설치본을 `adb pull` 해 `apksigner verify --print-certs` 로 읽어 확정했다(플레이 콘솔 "앱 무결성" 화면의 값과 같다). `android/key.properties` 가 없으면 릴리스 빌드도 디버그 서명으로 떨어진다(`android/app/build.gradle.kts`).

### AAB 빌드 (구글 플레이 업로드)

```bash
flutter build appbundle --release --build-number=<N> --dart-define-from-file=<dart-define 파일>
```

- **versionCode(`--build-number`)는 업로드마다 +1** 한다 — 플레이는 이미 올린 번호를 다시 받지 않는다. `pubspec.yaml` 의 `version`(`1.0.0+1`)은 건드리지 않고 명령의 `--build-number` 로만 올린다. 2026-10-14 기준 **2 까지** 올렸다(다음은 3) — **2026-10-19 갱신: versionCode 13 은 플레이에서 이미 사용돼 14 로 다시 만드는 중이다**(Desktop `CampusMate_AAB\` 에 vc 별 파일이 있다). iOS TestFlight 는 빌드 21 이다. 번호는 `--build-number` 로만 올리고 `pubspec.yaml` 의 `version` 은 건드리지 않는다
- `--dart-define-from-file` 의 파일(키 · 주소가 든 JSON)은 저장소 밖에 둔다. 값 · 파일 내용은 이 문서에 적지 않는다
- 결과물 `build/app/outputs/bundle/release/app-release.aab` 를 플레이 콘솔 내부 테스트에 올린다(올리기는 사용자가 한다)

## 가입 흐름을 시험할 때 (2026-10-19 갱신)

새로 가입하는 계정은 **소셜 로그인 → 약관 동의(02-c) → (인증 방법 고르기 02-0) → 학교 메일 02 · 인증번호 03 → 학과·학번 3c → 온보딩** 순서다. 학생증 단계(3b)는 2026-10-17 에 없어졌다.

- **인증 방법 고르기(02-0)는 서버 스위치 `GRADUATE_VERIFICATION_ENABLED` 가 켜진 서버에서만 나온다.** 운영 서비스에는 아직 스위치가 없어서(= 꺼짐) **지금 운영 서버에 붙은 앱은 약관 동의 다음에 바로 02 학교 메일 입력이 나온다.** 스위치가 켜진 서버(시험용 로컬 서버 등)에서는 동의 다음에 카드 두 개("학교 메일로 인증" / "졸업증명서로 인증") 중 하나를 고르고 [다음] 을 한 번 눌러야 한다 — 학교 메일 길로 가면 02 가 앱바 뒤로가기 화살표와 함께 열린다.
- 졸업생 길("졸업증명서로 인증")은 신청 폼 → 대기 화면으로 이어지고 결과는 관리자 웹 "졸업생" 화면에서 승인 · 반려해야 난다. 시험 계정으로 켜는 절차 · 점검은 `backend/DEPLOY.md` §4-14, 화면 규칙은 `frontend/docs/DESIGN.md` §9 02-0 ~ 02-g-4, 결정 배경은 `docs/decisions/2026-10-19-graduate-verification-decision.md`.
- 자동 E2E 하네스(`e2e/`)는 스위치가 꺼진 서버에서는 02 를 바로 만나 고칠 것이 없다고 본다(**추정** — 이 문서 담당이 하네스를 돌리지 않았다). 스위치를 켠 서버를 시험할 때는 계정 공장과 E-GATE 계열 가설에 "방법 고르기 한 번"을 더해야 한다(계획서 `2026-10-19-graduate-verification.md` 6장).
- 저녁 알림 제한(방해 금지 22~08시)은 **새 가입자부터 꺼진 채** 시작한다 — 밤 알림 시험(보류 → 아침 묶음 발송)을 하려면 시험 계정의 설정(16d)에서 먼저 켠다.
- 알림을 눌러 들어간 화면에서 뒤로가기를 누르면 홈으로 간다(§8.8). 알림 이동 시험은 `test/core/push/push_route_open_test.dart` · `test/main_push_open_test.dart`.

## 테스트

```bash
flutter test
```

테스트는 키 없이 돌아간다. 네트워크에 붙는 코드는 테스트하지 않는다.

## 주의

`--dart-define` 값을 이 파일에 적지 않는다. 실제 키는 각자 로컬에 보관한다.

SUPABASE_ANON_KEY 에는 Supabase 대시보드의 publishable key(sb_publishable_…) 나 legacy anon key 어느 쪽을 넣어도 된다. 라이브러리 안에서 같은 자리다.

## iOS 빌드 (macOS + Xcode 필요)

Windows 에서는 iOS 를 빌드할 수 없다. 저장소의 `iOS build` 워크플로(`.github/workflows/ios-build.yml`)가 macOS 러너에서 컴파일만 확인한다 — iOS · pubspec · `lib/` 가 바뀐 PR 과 수동 실행(Actions 탭 > iOS build > Run workflow)으로 돈다. 실패하면 `gh run list --workflow "iOS build" --limit 3` 로 실행 번호를 찾고 `gh run view <번호> --log-failed` 로 실패한 단계 로그만 본다.

### 키 넣기 (값은 이 파일에 적지 않는다)

1. `ios/Flutter/Secrets.xcconfig.example` 을 같은 폴더의 `Secrets.xcconfig` 로 복사하고 세 값을 채운다. `Secrets.xcconfig` 는 gitignore 대상이다.
   - `KAKAO_NATIVE_APP_KEY`: 카카오 개발자 콘솔의 네이티브 앱 키(안드로이드와 같은 값)
   - `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_REVERSED_CLIENT_ID`: 구글 클라우드 콘솔의 iOS 클라이언트 ID 와 그것을 뒤집은 값(`GoogleService-Info.plist` 의 `CLIENT_ID`, `REVERSED_CLIENT_ID`)
2. Firebase 콘솔에서 받은 `GoogleService-Info.plist` 를 `ios/Runner/` 에 둔다(gitignore 대상). Xcode 에서 따로 추가할 필요 없다 — 빌드 단계 "Copy GoogleService-Info.plist" 가 있으면 앱에 넣고, 없으면 경고만 내고 푸시 없이 빌드한다.
3. 앱 코드가 받는 값은 안드로이드와 같다.

```bash
flutter run \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=KAKAO_NATIVE_APP_KEY=... --dart-define=GOOGLE_WEB_CLIENT_ID=...
```

CI 는 같은 두 파일(`Secrets.xcconfig`, `GoogleService-Info.plist`)을 가짜 값으로 임시 만든다. 값은 저장소에 두지 않는다.

### 푸시 환경 (APNs)

`Debug.xcconfig` 는 `APS_ENVIRONMENT = development`, `Release.xcconfig` 는 `production` 이다(`Runner.entitlements` 가 읽는다). 개발용 기기에서 릴리스 빌드를 돌려 서명 오류가 나면 `Secrets.xcconfig` 에 `APS_ENVIRONMENT = development` 를 한 줄 더한다.

### 애플 로그인

시작 화면의 'Apple로 로그인'은 iOS 에서만 보이고 키를 넣지 않는다 — `Runner.entitlements` 의 Sign in with Apple 과 Supabase 대시보드 Authentication > Providers > Apple 켜기 · Client IDs 에 번들 ID `io.github.juunn.campusmate` 넣기(사용자가 끝냄)로 묶인다.

### 최소 버전 · 기기

iOS 15.5 이상(ML Kit 얼굴 감지 요구), iPhone 전용, 세로 고정이다. iPad 를 지원하려면 `ios/Runner.xcodeproj/project.pbxproj` 의 `TARGETED_DEVICE_FAMILY = 1` 3곳을 `"1,2"` 로 되돌리고 `Info.plist` 에 `UISupportedInterfaceOrientations~ipad` 를 되살린다.

## TestFlight 로 아이폰에 설치하기 (맥 없이)

`iOS TestFlight` 워크플로(`.github/workflows/ios-testflight.yml`)가 macOS 러너에서 진짜 키로 빌드하고, App Store Connect API 키 하나로 서명해 TestFlight 에 올린다. 수동 실행만 되고 저장소 주인이 실행할 때만 돈다. 서명 방식(서명 없는 보관본 → 푸시 권한을 실은 임시 서명 → 애플 클라우드 배포 인증서로 내보내며 업로드)과 흔한 실패 대처는 그 파일 맨 위 주석에 있다. ~~애플 로그인은 아직 앱에 없어서 이 빌드로는 시험할 수 없다.~~ (2026-10-14 정정 — iOS 애플 로그인은 PR #482(2026-10-12)로 들어왔다, 위 "애플 로그인")

수동 실행 워크플로는 기본 브랜치(main)에 있어야 Actions 탭 목록에 뜬다. 그래서 첫 실행은 이 워크플로가 main 에 merge 된 뒤다.

### 처음 한 번만

1. developer.apple.com > Certificates, Identifiers & Profiles > Identifiers 에 앱 번들 ID(`ios/Runner.xcodeproj/project.pbxproj` 의 `PRODUCT_BUNDLE_IDENTIFIER`)를 App ID 로 등록하고 Push Notifications 를 켠다.
2. App Store Connect > 앱 > "+" > 신규 앱: 위 번들 ID 를 고르고 이름과 SKU 를 넣는다. 앱 기록이 없으면 업로드가 실패한다. 밀린 약관(비즈니스 > 계약) 동의도 끝낸다.
3. App Store Connect > 사용자 및 액세스 > 통합 > App Store Connect API > 팀 키 "+": 역할은 Admin(클라우드 배포 인증서를 만들려면 필요). `.p8` 은 한 번만 내려받을 수 있다. 키 ID 와 그 화면 위쪽의 Issuer ID 를 적어 둔다. 이 화면을 처음 열면 계정 소유자(Account Holder)가 Request Access(액세스 요청)를 눌러 API 사용을 켜야 키를 만들 수 있다.
4. Firebase 콘솔에서 같은 번들 ID 의 iOS 앱 `GoogleService-Info.plist` 를 받는다. 푸시를 받으려면 Firebase > 프로젝트 설정 > 클라우드 메시징에 APNs 인증 키(developer.apple.com > Keys 에서 만드는 별도의 .p8)를 올린다. 새로 받은 plist 에 `CLIENT_ID` · `REVERSED_CLIENT_ID` 가 없으면 Google Cloud 콘솔 > API 및 서비스 > 사용자 인증 정보 > OAuth 클라이언트 ID 만들기 > iOS(같은 번들 ID)로 iOS 클라이언트를 만들고, 그 클라이언트 ID 와 뒤집은 값(`com.googleusercontent.apps.…`)을 아래 `GOOGLE_IOS_CLIENT_ID` · `GOOGLE_REVERSED_CLIENT_ID` 에 넣는다. 지금 쓰는 plist 에는 둘 다 들어 있다.
5. 로그인 쪽: 카카오 개발자 콘솔 > 플랫폼 > iOS 에 번들 ID 를 등록하고, Supabase 대시보드의 구글 제공자 Client IDs 에 iOS 클라이언트 ID 가 없으면 쉼표로 더한다(웹 ID 가 맨 앞).
6. `ios-release` 환경이 이미 있으면 건너뛴다. 없으면 만든다(권장): GitHub 저장소 > Settings > Environments > New environment > 이름 `ios-release` > Deployment branches and tags 를 Selected branches and tags 로 바꾸고 `main` 을 더한다. 안 만들어도 첫 실행 때 GitHub 가 같은 이름으로 만들지만 보호 규칙이 없어 main 만 허용이 걸리지 않는다.
7. 아래 12개 비밀을 이름 그대로 환경 비밀(Environments > `ios-release` > Environment secrets > Add secret)에 넣고 저장소 비밀은 지운다. 이 저장소는 이미 옮겨 두었다. 값 앞뒤에 공백이나 줄바꿈을 넣지 않는다. 값은 이 파일에 적지 않는다.

   base64 두 개는 파일이 있는 폴더에서 PowerShell 을 열고 **한 줄씩** 만든다: 첫 줄 실행 → GitHub 의 `ASC_KEY_P8_B64` 칸에 붙여넣고 저장 → 둘째 줄 실행 → `IOS_GOOGLE_SERVICE_INFO_B64` 칸에 붙여넣고 저장. 두 줄을 한꺼번에 실행하면 클립보드가 둘째 값으로 덮어써진다. `Resolve-Path` 는 .NET 이 PowerShell 의 현재 폴더를 모르기 때문에 붙인다.

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path "AuthKey_키ID.p8"))) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path "GoogleService-Info.plist"))) | Set-Clipboard
```


| 이름 | 넣는 것 |
| --- | --- |
| `APPLE_TEAM_ID` | 애플 개발자 팀 ID |
| `ASC_KEY_ID` | App Store Connect API 키 ID |
| `ASC_ISSUER_ID` | 같은 화면의 Issuer ID |
| `ASC_KEY_P8_B64` | `.p8` 파일의 base64 |
| `IOS_GOOGLE_SERVICE_INFO_B64` | `GoogleService-Info.plist` 의 base64 |
| `KAKAO_NATIVE_APP_KEY` | 카카오 네이티브 앱 키 |
| `GOOGLE_WEB_CLIENT_ID` | 구글 웹 클라이언트 ID(앱이 serverClientId 로 쓰는 값) |
| `GOOGLE_IOS_CLIENT_ID` | plist 의 `CLIENT_ID` |
| `GOOGLE_REVERSED_CLIENT_ID` | plist 의 `REVERSED_CLIENT_ID` |
| `SUPABASE_URL` | Supabase 프로젝트 URL |
| `SUPABASE_ANON_KEY` | Supabase publishable(anon) 키 |
| `API_BASE_URL` | 운영 서버(Cloud Run) 주소 |

### 실행할 때마다

1. GitHub > Actions > iOS TestFlight > Run workflow(main). 30~40분쯤 걸린다. 빌드 번호는 실행 번호이고, 앱 버전 이름은 `pubspec.yaml` 의 `version` 그대로다.
2. 실패하면 빨간 단계의 `::error::` 줄을 본다(비밀은 이름만 찍힌다). 그 실행의 아티팩트 `ios-testflight-logs-<실행 번호>` 에 이 워크플로가 만든 로그 두 개(빌드 · 업로드)가 비밀과 실명을 지운 채 7일 남는다. xcodebuild 의 자세한 기록은 계정 정보가 섞여 올리지 않는다. 성공한 실행을 Re-run 하면 빌드 번호가 겹쳐 실패하니 늘 Run workflow 로 새로 돌린다.
3. 성공하면 App Store Connect > 앱 > TestFlight 에서 빌드 처리가 끝날 때까지 10~30분 기다린다(끝나면 애플 메일이 온다).
4. 처음 한 번: TestFlight > 내부 테스팅 > "+" 로 그룹을 만들고 테스터(App Store Connect 사용자인 본인 Apple ID)를 더한다. 이후 새 빌드는 그 그룹에 넣는다(그룹의 자동 배포를 켜 두면 생략).
5. 아이폰 App Store 에서 TestFlight 앱을 설치하고 같은 Apple ID 로 로그인해 초대받은 CampusMate 를 설치한다.

워크플로의 검사 스크립트 `.github/scripts/ios_testflight.py`(비밀 확인 · 번들 ID 확인 · 로그 비밀 지우기)를 고치면 저장소 루트에서 `python -m unittest discover -s .github/scripts -v` 를 돌린다(워크플로 구조 검사는 PyYAML 이 있을 때만 돈다 — `backend/.venv` 파이썬에는 있다).

## 앱 아이콘 교체

지금 아이콘은 시안 B 다: 흰 바탕에 분홍(#FF385C) 토끼 귀 하트 심볼, 그 아래 검은 `CampusMate` 글자(2026-10-12 사용자 결정, 직전의 분홍 바탕 심볼만 시안 A 를 바꿨다). 원본은 바탕화면의 `datingApp` 폴더 안 `design/designMaterials/google-play-logo-128.png` 한 장(128x128)뿐이다. 알림 아이콘은 따로 정한다(아래 "알림 아이콘").

글자 한계: 홈 화면 아이콘은 기기 화소와 상관없이 실제 크기가 손톱만 해서(48~60dp) 글자 높이가 1mm 남짓, 아이콘 아래 앱 이름의 절반쯤이다. 파일 화소로는 80px 이상에서 글자가 또렷하고, 58~72px 은 겨우, 48px 이하(iOS 알림·설정 @1x, 안드로이드 mdpi)는 회색 줄로 뭉개진다. 안드로이드 13+ 테마 아이콘(monochrome)도 같은 전경을 한 색으로 칠하므로 같은 한계다.

### 들어 있는 파일과 크기

| 자리 | 파일 | 크기(px) |
| --- | --- | --- |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` — `Contents.json` 에 적힌 15장. 정사각 전체를 흰 바탕으로 채움(모서리는 iOS 가 깎는다) | size x scale (20~1024). 알파 없음(RGB) |
| 안드로이드 7 이하 | `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` — 흰 정사각 위 로고, 원본 구도 그대로 | 48, 72, 96, 144, 192 |
| 안드로이드 8 이상(적응형) | `mipmap-anydpi-v26/ic_launcher.xml` 이 묶는 `mipmap-*/ic_launcher_foreground.png`(심볼+글자, 투명 바탕) + `values/colors.xml` 의 `ic_launcher_background`(#FFFFFF). monochrome 도 같은 전경 | 전경 108dp: 108, 162, 216, 324, 432. 로고 60.3x29.1dp, 가장 먼 픽셀이 반지름 32dp(66dp 안전 원 안, 1dp 여유) |
| 스토어(저장소 밖) | `CampusMate_문서/출시준비/스토어_아이콘/` 의 `google-play-512.png`, `app-store-1024.png`. 시안 A 때 파일은 같은 폴더 `*_A적용분.png` | 512(32비트, 투명 없음), 1024(알파 없음) |

`Contents.json` 의 iPad 항목은 그대로 두었다(앱은 iPhone 전용이라 쓰이지 않는다). 파일 이름을 바꾸면 `Contents.json` 도 같이 바꾼다.

### 이번에 만든 방법

새 의존성 없이 저장소 루트 `backend/.venv` 의 Pillow 로 만들었다. 원본이 128px 라 큰 크기는 확대본이다 — 심볼(분홍)과 글자(검정)의 덮임 비율을 따로 뽑아 8배로 키운 뒤(LANCZOS) 가장자리만 다시 세웠다(약한 흐림 + 레벨 조정, 모양은 새로 그리지 않음). 홈 화면 크기에서는 티가 나지 않지만 1024 를 100% 로 보면 글자 획과 윤곽이 조금 둥글고 흔들린다. 적응형 전경은 1dp=12px 캔버스에 놓고 밀도별로 정수배 BOX 축소한다(LANCZOS 는 저밀도에서 안전 원 밖으로 흐린 알파가 샌다). 스크립트는 `스토어_아이콘/도구/` 에 있다: `make_icons.py`(만들기 + `미리보기_B적용.png`), `verify_icons.py`(크기·알파·흰 바탕·심볼·글자·안전 영역·XML 참조·스토어 규격 검사). 시안 A 때 스크립트는 `*_A적용분.py`.

### 더 큰 원본이 생기면

1. 1024x1024 이상 PNG(바탕까지 꽉 찬 정사각형, 둥근 모서리 없음)나 벡터를 받는다. 안드로이드 전경용으로 로고(심볼+글자)만 있는 투명 PNG 가 있으면 더 좋다.
2. 위 표의 크기 목록 그대로 다시 만든다. 둘 중 하나:
   - 스크립트: `make_icons.py` 맨 위의 원본 파일 이름, `UP`(원본에서 1024 로 가는 배율), 바탕·심볼 색을 맞추고, 원본이 1024 이상이면 `CRISP = False` 로 둔다. `python -I make_icons.py <designMaterials> <frontend> <스토어_아이콘>` 뒤 `python -I verify_icons.py <frontend> <스토어_아이콘>` 이 `PASS 0` 이어야 한다.
   - `flutter_launcher_icons`: 아직 pubspec 에 없다 — 쓰기 전에 사용자 승인을 받고 dev_dependencies 에 더한다. 설정 예:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.0

flutter_launcher_icons:
  image_path: "assets/icon/app_icon.png"       # 1024, 바탕까지 꽉 찬 것
  android: true
  ios: true
  remove_alpha_ios: true        # App Store 는 투명도 있는 아이콘을 거절한다
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"   # 로고(심볼+글자)만, 투명 바탕, 가운데 66dp 원 안
```

   `dart run flutter_launcher_icons` 를 돌리면 iOS `AppIcon.appiconset` 과 안드로이드 `mipmap-*` 이 새로 만들어진다.
3. 빌드 없이 확인: `flutter analyze` 와 위 `verify_icons.py`.

## 알림 아이콘 (안드로이드 상태바, 2026-10-13 PR #503)

안드로이드 상태바 알림 아이콘은 **흰색 + 투명 바탕 실루엣**이어야 한다(시스템이 알파만 보고 색을 입힌다 — 컬러 앱 아이콘을 쓰면 흰 네모로 보인다).

| 자리 | 파일 | 크기 |
| --- | --- | --- |
| 안드로이드 | `android/app/src/main/res/drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_stat_campusmate.png` | 24dp 캔버스 — 24, 36, 48, 72, 96 px |
| 연결 | `AndroidManifest.xml` 의 `com.google.firebase.messaging.default_notification_icon` = `@drawable/ic_stat_campusmate` | FCM 이 띄우는 알림(앱이 뒤에 있을 때)과 앱이 직접 띄우는 앞 화면 알림이 같은 그림을 쓴다 |

**만든 방법**: iOS 1024 앱 아이콘(`AppIcon.appiconset` 의 1024)에서 **분홍 심볼이 덮인 정도를 알파로 뽑아 흰색으로 칠했다**(글자 · 흰 바탕은 버린다). 24dp 캔버스에 **사방 1dp 여백**을 두고 밀도별로 줄였다. 앱 아이콘을 바꾸면 이 아이콘도 같이 다시 만든다. iOS 는 알림에 앱 아이콘을 그대로 쓰므로 따로 만들 것이 없다.

**2026-10-19 추가(PR #618): 작은 아이콘 뒤 원 색.** 색을 안 주면 폰이 파란 원을 골랐다. `android/app/src/main/res/values/colors.xml` 의 `notification_accent`(`#FF385C`, `AppColors.primary` 와 같은 값)를 `AndroidManifest.xml` 의 `com.google.firebase.messaging.default_notification_color` 에 연결했고(앱이 꺼져 있을 때 FCM 알림), 앱이 떠 있을 때 띄우는 알림(`LocalSystemNotifications`)도 `AppColors.primary` 를 준다. `AppColors.primary` 를 바꾸면 `colors.xml` 도 같이 바꾼다(시험이 세 값이 같은지 본다). 앱 아이콘 전체를 알림 큰 그림으로 쓰는 방식은 출시 후 과제다.
