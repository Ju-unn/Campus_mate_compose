# 실행 방법

Supabase 키는 소스에 넣지 않고 실행할 때 주입한다.

## 개발 실행

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<프로젝트>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

소셜 로그인(시작 화면)을 쓰려면 `--dart-define=KAKAO_NATIVE_APP_KEY=...` `--dart-define=GOOGLE_WEB_CLIENT_ID=...` 를 함께 넣고, 안드로이드 빌드에는 카카오 복귀 스킴용으로 같은 이름 `KAKAO_NATIVE_APP_KEY` 를 환경변수나 `android/local.properties` 에도 둔다(없으면 빌드는 되고 버튼만 실패 토스트).

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

### 최소 버전 · 기기

iOS 15.5 이상(ML Kit 얼굴 감지 요구), iPhone 전용, 세로 고정이다. iPad 를 지원하려면 `ios/Runner.xcodeproj/project.pbxproj` 의 `TARGETED_DEVICE_FAMILY = 1` 3곳을 `"1,2"` 로 되돌리고 `Info.plist` 에 `UISupportedInterfaceOrientations~ipad` 를 되살린다.

## 앱 아이콘 교체

지금은 안드로이드와 iOS 모두 Flutter 기본 로고다. 최종 아이콘이 정해지면 `flutter_launcher_icons` 로 한 장에서 두 OS 아이콘을 만든다(이 패키지는 아직 pubspec 에 없다 — 쓰기 전에 사용자 승인을 받고 dev_dependencies 에 더한다).

1. 1024x1024 PNG 한 장을 준비한다(iOS 는 투명 배경 · 둥근 모서리 없이, 정사각형 그대로). 예: `assets/icon/app_icon.png`
2. 아래 설정을 `pubspec.yaml` 맨 아래(또는 `flutter_launcher_icons.yaml`)에 둔다.

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.0

flutter_launcher_icons:
  image_path: "assets/icon/app_icon.png"
  android: true
  ios: true
  remove_alpha_ios: true        # App Store 는 투명도 있는 아이콘을 거절한다
  adaptive_icon_background: "#FFFFFF"      # 안드로이드 적응형 아이콘 배경색(디자인 확정 후 값 교체)
  adaptive_icon_foreground: "assets/icon/app_icon_foreground.png"
```

3. `dart run flutter_launcher_icons` 를 실행하면 iOS `AppIcon.appiconset` 과 안드로이드 `mipmap-*` 이 새로 만들어진다.
