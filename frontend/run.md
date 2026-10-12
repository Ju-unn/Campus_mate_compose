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

지금 아이콘은 시안 B 다: 흰 바탕에 분홍(#FF385C) 토끼 귀 하트 심볼, 그 아래 검은 `CampusMate` 글자(2026-10-12 사용자 결정, 직전의 분홍 바탕 심볼만 시안 A 를 바꿨다). 원본은 바탕화면의 `datingApp` 폴더 안 `design/designMaterials/google-play-logo-128.png` 한 장(128x128)뿐이다. 알림 아이콘은 따로 정한다(여기서 다루지 않는다).

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
