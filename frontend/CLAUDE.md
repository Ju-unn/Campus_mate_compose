# CLAUDE.md — CampusMate

이 문서는 **CampusMate** 프로젝트에서 코드를 작성하거나 수정할 때 반드시 따라야 하는 **지금 규칙**을 정의한다. 규칙이 바뀐 경위(언제 · 누가 · 어느 PR)는 여기 적지 않는다 — git 이력과 `../docs/decisions/` 결정 기록에 있다.

- **언어**: Dart
- **프로젝트 형태**: Flutter 앱 (Android + iOS), MVVM + Riverpod
- **백엔드**: FastAPI (비즈니스 로직) + Supabase (Auth·DB·RLS·Storage)
- **코드/네이밍**: 영어 / **주석·설명·문서**: 한국어

> ⚠️ **이 저장소는 공개(public)다.** `github.com/Ju-unn/Campus_mate_compose` 단일 저장소이고,
> 이 문서가 있는 `frontend/` 가 Flutter 프로젝트 루트다 (`backend/` 는 FastAPI 자리, `docs/` 는 공통 문서, `supabase/` 는 마이그레이션·시드·pgTAP 자리 — 셋 다 저장소 루트에 있고 `frontend/` 안이 아니다).
> 키·`.env`·실존 인물 사진을 커밋하지 않는다. 자세한 규칙은 `../docs/GIT.md`.
>
> ℹ️ 디자인 원본(`datingApp.pen`, 시안 미리보기, 경쟁사 리서치)은 이 저장소에 없다. OneDrive `datingApp`
> 저장소(Pencil 편집용)에 있고, 이 문서와 `docs/DESIGN.md` 는 거기서 결론만 옮겨온 것이다.

---

## 1. 필수 사항 (최우선 규칙)

1. **UI 작업 전에 `docs/DESIGN.md` 를 먼저 읽을 것.** 추측으로 화면을 만들지 않는다. 시안 원본(Pencil `.pen`)과 화면 미리보기 PNG는 이 저장소에 없고 OneDrive `datingApp` 저장소에 있다 — 필요하면 그쪽에서 확인한다. 화면 구현에 바로 쓸 PNG 자산은 `assets/images/`에 있다.
2. **색·타이포·간격·라운드·모션은 DESIGN.md 의 토큰만 사용할 것.** 위젯 안에 `Color(0xFF...)` 리터럴을 직접 쓰지 않는다. `lib/core/theme/` 의 상수를 통해서만 참조한다.
3. **dp 값은 화면 비율에 대응시킬 것.** 고정이 맞는 값(아이콘 크기, 코너 반경, 테두리 두께)만 그대로 쓴다.
4. **애매한 부분은 임의로 결정하지 말고 사용자에게 먼저 질문할 것.**
5. **하나의 작업이 끝나면 거기서 멈추고 사용자의 검토를 받을 것.**
6. **MVVM 에 맞게, 기능(조각)별로 패키지를 나눌 것.** 각 기능 아래 `model/{repository,data}` / `view` / `viewmodel` 을 둔다 (§3.2 — auth · profile · billing 은 세부 기능 폴더가 한 층 더 있다).
7. **모든 비(non-)private 클래스는 테스트를 가질 것.** 테스트 없는 클래스가 포함된 채로 커밋 메시지를 제안하지 않는다.
8. **새 의존성 추가는 사전에 사용자에게 확인할 것.**
9. **git 작업(브랜치·커밋·푸시·PR) 전에 `../docs/GIT.md` 를 먼저 읽을 것.** 커밋 메시지는 gitmoji + Conventional Commits 형식, `main` 직접 푸시 금지, 커밋→푸시→draft PR 까지만 하고 merge 는 사용자가 한다.
10. **코드베이스를 탐색하기 전에 지식 그래프를 먼저 조회할 것** (`../docs/GRAPHIFY.md`). "X 는 어디서 쓰이나", "흐름 추적" 같은 질문은 `python -m graphify query` 가 먼저다. Grep·Read 로 뒤지는 건 그래프가 답을 못 줄 때만. **문서를 고친 작업 끝에는 `/graphify . --update` 를 실행**한다 (코드는 커밋 hook 이 자동 갱신).
11. **Supabase 작업(스키마·RLS·Storage·Auth) 전에 `../docs/SUPABASE.md` 를 먼저 읽을 것** (금지 규칙 요약은 §10.1). 스키마 변경은 반드시 저장소 루트 `supabase/migrations/*.sql` 파일로 남기고, 프로젝트 URL·키·ref 는 문서와 코드에 쓰지 않는다. **클라우드 쓰기는 매번 사용자가 직접 승인한 뒤에만** 한다.
12. **화면 문구는 한글을 코드에 쓰지 않고 `lib/l10n/app_ko.arb` 에만 둔다 (§7.2). 에러 상태는 `String` 이 아니라 `Failure?` 로 담는다 (§7.2). 파일을 새로 만들 때는 §3.2 폴더 규칙을 따른다.** 어기면 `test/l10n/` · `test/core/theme/` 의 지킴 시험이 실패한다 (§8 표).

---

## 2. 프로젝트 개요

| 항목 | 결정 |
| --- | --- |
| 앱 이름 | CampusMate |
| 패키지명 | `io.github.juunn.campusmate` |
| 플랫폼 | Android + iOS (웹 버전은 계획 단계 — 아래 "웹 버전") |
| 프레임워크 | Flutter (Dart) |
| 상태 관리 | Riverpod (`Notifier`) |
| 라우팅 | `go_router` |
| 백엔드 | **FastAPI**(비즈니스 로직) + **Supabase**(Auth·DB·RLS·Storage) — 설계 문서 §1·§7 |
| 벡터 검색 | PostgreSQL + pgvector |
| 임베딩 | OpenAI `text-embedding-3-small` (512차원) |
| 인증 | 카카오·구글 소셜 로그인(애플은 iOS 만) + 학교 메일 6자리 인증코드 1회(가입 때 한 번, 별도 임시 연결로). **학생증 · 졸업증명서 사진 인증과 실명 입력은 없다.** 예외로 **졸업생 길**: 학교 메일이 없는 졸업생은 졸업증명서 사진 + 관리자 검수(문서확인번호를 발급 기관 사이트에서 조회)로 학교 메일 사람과 같은 상태가 된다. 서버 스위치 `GRADUATE_VERIFICATION_ENABLED`(코드 기본 꺼짐, 운영은 켜져 있다)가 켜져야 앱에 인증 방법 고르기가 나온다 (`../docs/decisions/2026-10-19-graduate-verification-decision.md`, 화면 DESIGN.md §9 02-0 ~ 02-g-4) |
| 가입 자격 | **연 나이 기준 만 19세 이상**(만 19세가 되는 해 1월 1일부터, 청소년보호법 방식, Asia/Seoul 기준 — ERD.md §11-1), 재학생·졸업생 모두 가능. 앱 등급 19+ (설계 문서 §13 미결1). 계산은 올해 − 출생연도 ≥ 19이고, 화면 · 서버에 보이는 문구는 "만 19세 이상" 이 아니라 **"{올해−19}년생부터 가입할 수 있어요"**(해가 바뀌면 저절로 바뀐다 — ARB `errorBirthYear` · `backend/app/profile_onboarding/schemas.py`) |
| 핵심 형태 | **가변 주기 큐레이션 카드(남녀 중 적은 쪽 활성 인원 5단계 사다리: 50 미만 주 1회 → 50+ 주 2회 → 500+ 주 3회 → 1,000+ 주 4회 → 2,000+ 매일, `backend/app/cards/ladder.py`) + 상호 수락 + 매칭 후 신뢰 확인 게이트.** 무료 카드는 점수 상위 20~90% 구간 무작위, 상위 20% 는 유료 전용. 유료 카드는 주기마다 상위 20% 사전 선정(`backend/app/matching/band.py` · `backend/app/cards/paid_offer.py`, 설계 문서 §6.8). 카드 결정 버튼은 "대화 신청하기", 대화 탭은 "받은 신청". 뽑을 수 있는 후보가 1명뿐이면 유료 제안을 접고 그 사람을 무료 카드로 준다 (설계 §6.8 · §13 미결45, `../backend/DEPLOY.md` §4-21, DESIGN.md §13-154) |
| 핵심 차별점 | **지인 리뷰** — 추천 코드로 연결된 지인이 남긴 평가를 카드에 노출 (설계 문서 §2.8) |
| 출시 방식 | **학교별 코호트 순차 오픈** — 14일 모집 후 예고한 날짜에 카드 지급 시작 (설계 문서 §2.9). 학교별 오픈 날짜는 운영 DB 값이 기준이다 (`../backend/DEPLOY.md` §4-17) |
| 수익 모델 | 가입비 없음(남녀 동일 무료). **하트 1개 = 60원**(DESIGN.md §13-114), 추가 카드 50하트(**구매 시점은 자유, 지급 주기당 1장**), 아바타 재생성 20하트(최초 1회 무료. 서버 `AVATAR_REGEN_HEARTS`, 앱은 서버 `avatar_regen_cost` 를 그대로 보인다. 온보딩 5회 실패 보상 10하트는 별개), 첫 구매 보너스 +50(100하트 이상 · 한 번) (설계 문서 §2.4). 하트는 **안드로이드는 구글 플레이 인앱결제, iOS 는 App Store 인앱결제(StoreKit 2)** 로 산다. 가격은 둘이 같고 화면은 스토어 가격을 우선한다. 구매 영역은 웹 · 데스크톱에서만 숨긴다. DB 는 같은 `purchases` 표(`store = app_store` 로 구분). DESIGN.md §8.10 · ERD.md §6 · 서버 계약 `../backend/DEPLOY.md` §4-10 |
| 채팅 | 카톡식 안 읽음 '1'. 목록 · 안 읽은 수 · '1' 을 사용자 채널 `user:<profile_id>`(Supabase Realtime Broadcast, 서버가 쏜다)로 실시간 반영하고, 채널이 안 붙으면 폴링(목록 3초 · 읽음 2초)으로 돈다 (`../backend/DEPLOY.md` §4-8 · ERD.md §4). **채팅 상한 없음** — 매칭 후 24h/48h 신뢰 확인 게이트가 방치된 대화를 정리한다 (설계 문서 §2.5). **채팅은 텍스트만, 이미지 전송 불가** |
| 기기 · 등급 | 아이폰 전용(iPad 는 호환 모드), 안드로이드 세로 고정 없음(접이식은 시험 안 함). 연령 등급 앱스토어 한국 19+ · 구글 18+ |

실제 DB 적용 상태는 `../docs/ERD.md` 상태줄, 서버 리비전 · 배포 절차는 `../backend/DEPLOY.md` §5, 디자인은 `docs/DESIGN.md` 를 기준으로 한다. DESIGN.md §13 에 열린 채 남은 행에 걸리는 구현은 먼저 사용자에게 묻는다. 앱 버전 · 스토어 제출 · 심사 상태는 금방 낡으므로 이 문서에 적지 않는다 (`../docs/decisions/2026-11-04-v102-decisions.md`).

### 2.1 의존성과 쓰는 법

새 의존성은 사용자 승인 없이 넣지 않는다 (승인 원문은 `../docs/decisions/` — Firebase 3종은 `2026-10-20-launch-day-decisions.md`, 나머지는 `2026-11-04-v102-decisions.md` §6).

| 의존성 | 용도와 규칙 |
| --- | --- |
| `flutter_local_notifications ^22.3.2` | 앱이 앞에 있을 때 받은 푸시를 안드로이드 헤드업 알림으로 띄운다. 이 패키지 때문에 안드로이드 **core library desugaring**(`coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`, `android/app/build.gradle.kts`)이 켜져 있다 — gradle 라이브러리가 "새 의존성" 규칙에 걸리는지는 사용자 사후 확인 대상 |
| `in_app_purchase ^3.3.1` | 하트 구매(구글 플레이 · App Store). iOS 는 이 패키지가 끌고 오는 `in_app_purchase_storekit`(transitive, 최소 iOS 15.5 = StoreKit 2)을 쓴다 — `Transaction.unfinished` 를 직접 부르려면 직접 의존성으로 올려야 하므로 쓰지 않는다 |
| 서버 `cryptography>=50` | `backend/pyproject.toml`. App Store 서명(JWS) 인증서 체인 검증 · App Store Server API 토큰(ES256) · 탈퇴 때 애플 토큰 철회 |
| `package_info_plus ^10.2.2` | 설치된 앱의 버전 이름을 읽어 서버 최소 버전(`GET /app/version`, env `MIN_APP_VERSION`)과 견주는 강제 업데이트(`lib/core/app_update/`, 화면 pen `zSzOG` 01-2). **`MIN_APP_VERSION` 은 두 스토어에 고친 빌드가 모두 공개된 뒤에만 올린다** (`../backend/DEPLOY.md` §2 · §4-20) |
| `lottie ^3.8.2` | 움직이는 그림(Lottie JSON). Flutter 3.47 이상을 요구한다. 쓰는 법은 §7.1 |
| `flutter_localizations`(sdk) · `intl ^0.20.3` | 화면 문구 ARB. 쓰는 법은 §7.2 |
| `firebase_analytics ^12.0.1` · `firebase_crashlytics ^5.0.1` · `firebase_performance ^0.11.6` | 사용 통계 · 앱이 죽은 기록(오류 수집) · 성능 측정. 최신 performance 0.12 는 `firebase_core ^5` 를 요구해 현재 `firebase_core ^4` 에 맞는 0.11 대를 쓴다. 규칙은 아래 "수집 · 분석" |

**수집 · 분석 규칙** (Firebase Analytics · Crashlytics · Performance)

- **약관 동의(02-c) 전에는 수집하지 않는다.** `AndroidManifest.xml` `firebase_analytics_collection_enabled` · `firebase_crashlytics_collection_enabled` · `firebase_performance_collection_enabled` = false, `Info.plist` `FIREBASE_ANALYTICS_COLLECTION_ENABLED` · `FirebaseCrashlyticsCollectionEnabled` · `firebase_performance_collection_enabled`(이 키만 소문자) = false 로 꺼 두고, 동의를 마친 로그인 사용자일 때만 앱이 켠다 (`lib/core/analytics/collection_consent.dart`, `main.dart` `_syncCollection`).
- **성능 측정은 자동 수집(앱 시작 시간 · 화면 렌더링)만 쓴다.** 사용자 지정 추적(`HttpMetric` · `Trace`)은 만들지 않는다 (서버 요청 주소에 계정 번호가 섞일 수 있다).
- **광고 식별자 · 광고 맞춤은 쓰지 않는다.** 안드로이드 `google_analytics_adid_collection_enabled` · `google_analytics_default_allow_ad_personalization_signals` = false 와 `AD_ID` 권한 제거, iOS `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS` = false. Flutter 3.47 이 Firebase 를 SPM 으로 가져와 Podfile 의 `$FirebaseAnalyticsWithoutAdIdSupport` 줄은 iOS 에서 듣지 않는다 — 광고 식별자 부품(`GoogleAppMeasurementIdentitySupport` · `GoogleAdsOnDeviceConversion`)을 빼는 것은 워크플로 잡 env `FIREBASE_ANALYTICS_WITHOUT_ADID=true`(`ios-testflight.yml` · `ios-build.yml`)가 맡는다. **맥에서 직접 `flutter build ios` / `flutter build ipa` 할 때도 이 환경변수를 줘야 한다.**
- **개인정보는 보내지 않는다.** 사용자 id · 속성 · 오류 사용자 키를 설정하지 않고, 이벤트 매개변수는 정해진 종류값(`lib/core/analytics/analytics_values.dart`) · 작은 정수 · 상품 ID 뿐이다. 앱이 버틴 API 오류(5xx · 연결 실패 · 시간 초과)의 비치명 Crashlytics 기록은 종류 · 상태 코드 · 경로 패턴만 보낸다.
- **이벤트 이름 · 값 목록 · 보내는 자리는 `docs/ANALYTICS_EVENTS.md` 표가 기준이다 — 이벤트를 더하거나 고치면 이 표도 함께 고친다.**
- 안드로이드는 Gradle 플러그인 `com.google.firebase.crashlytics 3.0.8` · `com.google.firebase.firebase-perf 2.0.2`(`android/settings.gradle.kts` · `android/app/build.gradle.kts`)가 필요하다. iOS `PrivacyInfo.xcprivacy` 에 제품 상호작용 · 기기 ID · 성능 데이터(분석)와 충돌 데이터(앱 기능)를 연결 안 됨 · 추적 안 함으로 선언했다.
- 개인정보 처리방침(노션)의 수집 항목 갱신은 이 저장소 밖 일이다. **방침을 고치면 홈페이지 사본 `../site/privacy/index.html` 도 같이 고친다** (`../docs/decisions/2026-10-20-launch-day-decisions.md` §3).

### 2.2 빌드 · 운영 규칙

- **안드로이드 릴리스 빌드 전에 같은 셸에서 `export KAKAO_NATIVE_APP_KEY=...` 를 한다.** `android/app/build.gradle.kts` 가 환경변수 → `android/local.properties` → 빈 문자열 순으로 읽어 매니페스트 `kakao<키>` 스킴을 채우고, 이 값은 `--dart-define` 과 **별개**다. 환경변수가 비면 릴리스 빌드(`assembleRelease` · `bundleRelease`)가 `KAKAO_NATIVE_APP_KEY 가 비었습니다` 로 실패한다 (디버그 빌드는 그대로). 빌드 뒤 AAB 매니페스트에서 스킴이 채워졌는지 확인한다. versionCode 는 `--build-number` 로 업로드마다 +1 하고, 빌드 뒤 매니페스트 `versionName` 도 확인한다. 절차는 `run.md` "AAB 빌드".
- **앱 버전 이름은 pubspec 이 아니라 `--build-name` 으로 정한다** — 빼면 1.0.0 으로 기록돼 나중에 서버 `MIN_APP_VERSION` 에 갇힌다.
- iOS TestFlight 워크플로(`ios-testflight.yml`)는 `build_name` 입력으로 버전 이름을 받고, 업로드가 끝나면 Crashlytics 에 dSYM 도 올린다 (실패해도 잡은 성공 + 노란 경고만, `run.md` "iOS TestFlight").
- **구글 심사 대응으로 운영 DB 에 시험 데이터**(가상 계정 20 · 카드 1 · 채팅방 3, 심사원 로그인 계정 포함)가 들어 있다. 제거 전에는 e2e 하네스의 전체 cleanup 을 돌리지 않는다. 하네스는 `E2E_ENV` 가 운영이 아니면 `require_cloud` 가 gcloud 를 부르는 길을 막는다(로컬 안전장치). 제거는 심사 통과를 확인한 뒤 사용자에게 먼저 묻고, 심사원 비밀번호를 무작위로 바꿔 막은 다음에 한다 (`../backend/DEPLOY.md` §4-16. 되돌리기 스크립트는 저장소 밖 바탕화면 `E2E_결과\심사용_시험계정_10-27\`).
- **웹 버전은 계획이다(구현 전).** 앱은 그대로 운영하면서 웹을 더한다 — 방식 A(`frontend/` 코드를 같이 쓰고 웹에서 안 되는 부분만 웹용 파일로 나눈다). **앱 쪽 기존 파일은 지우거나 바꾸지 않고 옆에 더한다**, 별도 브랜치, 합치기 전 `flutter.yml` · `ios-build.yml` 통과, **패키지 추가는 하나씩 사용자 승인**. 근거 · 막힐 곳: `../docs/decisions/2026-10-27-web-version-decision.md`.

### 2.3 기능 규칙 모음

- **구글 심사원 로그인(안드로이드 전용).** 시작 화면(01) 로고 자리를 5초 안에 7번 누르면 영어 "Reviewer sign-in" 시트가 열리고 이메일 · 비밀번호로 Supabase `signInWithPassword` 로 들어간다. 가입 없음 · 분석 `login` 이벤트 없음 · 낭독기 제외 · 이미 로그인된 상태면 입구 없음. iOS · 웹에는 입구가 없다 — 코드는 모든 빌드에 실려 있지만 `start_view.dart` 의 `_isAndroid()` 가 iOS 에서 걸러낸다 (애플 가이드라인 2.3.1 숨은 기능 규칙). 서버 · DB 코드는 따로 없고 기존 심사용 계정(id 앞 8자 `acdbb0fc`)에 운영 Auth 관리자 API 로 비밀번호를 붙여 쓴다 (값은 저장소에 적지 않는다, `../backend/DEPLOY.md` §4-16). `LabeledField` 의 `obscureText`(기본 false) · ARB 키 `authSocialReviewer*` 5개(영어 그대로) · 오류 문구는 `errorText` 그대로(한국어). **심사 통과 뒤 비밀번호를 무작위로 바꿔 막는다.** 심사원이 탈퇴하면 되돌릴 수 없어 심사 안내문에 금지로 적었다. 입구와 소셜 버튼이 겹치지 않는지는 `start_view_test.dart` 가 지킨다. DESIGN.md §9 01-3 · §13-158.
- **카드 지급 한계(알려진 것).** 지급일이 아닌 날 카드 0장 + 후보 1명이면 유료 제안으로 보이다가 다음 지급일 배치에서 무료로 나간다. 구매와 접기가 같은 순간에 겹치면 같은 상대를 유료 · 무료로 둘 다 받을 수 있다 (`../backend/DEPLOY.md` §4-21). 첫 방문 0장이면 화면 11 은 "다음 카드를 준비하고 있어요" 를 보인다.
- **출시 후로 미룬 것(지금 하지 않는다):** 스크린샷 방지 · 졸업생 D8 자기 취소 · 하트 스토어 대기 목록 · 안드로이드 큰 알림 아이콘 · 카드 신고 버튼(반려 시) · 환불 정책 B · 카카오 연결 해제 웹훅 · 아이패드 전용 화면 · DESIGN.md §13-155 의 "칸에도 넣을까요?" 안내.
- **계획으로만 있는 정리:** 색 / 크기 / 간격 토큰 정리 · 공통 컴포넌트 · SonarQube(저장소는 공개지만 라이선스가 없어 5만 줄 무료 한도 기준) · 시작은 사용자가 정한다.

### 2.4 문서 지도

| 파일 | 역할 |
| --- | --- |
| `../docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` | 제품·아키텍처·매칭·보안 전체 설계. **모든 결정의 기준**. FastAPI 백엔드도 참조하므로 `frontend/` 밖, 저장소 루트 `docs/` 에 둔다 |
| `../docs/superpowers/plans/2026-09-05-foundation-setup.md` | 조각 0 실행 계획 (작업 단위) |
| `../docs/ERD.md` | **DB 기준 — 테이블·컬럼·RLS·권한(grant) 표.** 스키마·RLS 작업 전 필독. 상태줄이 조각별 적용 상태의 기준 |
| `../docs/ERD_DECISIONS.md` | ERD 결정 기록(§11)·끝난 검토(§12 해결 행)·조각 0 적용 범위(§10) |
| `../docs/decisions/` | 기술 결정 기록 — 한 결정에 한 파일(`날짜-주제-decision.md`) 또는 하루 묶음. 졸업생 인증(10-19) · 출시 당일(10-20) · 웹 버전(10-27) · 앱 1.0.2 결정(11-04, 11-08 ~ 09 추가분 포함) |
| `../docs/history/` | 지나간 운영 기록(배포 리비전 · DB 적용 날짜 · 운영 쓰기 기록). 지금 규칙이 아니라 이력 |
| `../docs/GIT.md` | **Git 규칙 — gitmoji 커밋 형식, 브랜치 전략, 푸시 규칙.** git 작업 전 필독 |
| `../docs/GRAPHIFY.md` | **코드베이스 탐색 규칙 — 지식 그래프 조회·갱신.** Grep 전에 그래프 먼저 |
| `../docs/SUPABASE.md` | **Supabase 작업 규칙 — 키·식별자, 마이그레이션 파일, 클라우드 적용 절차, RLS·grant 체크리스트.** Supabase 작업 전 필독 (요약은 §10.1) |
| `../docs/SETUP.md` | 새 PC 준비 — 스킬·Pencil·폰트·SDK·graphify·IDE (§12) |
| `../backend/DEPLOY.md` | 서버 배포 · 운영 절차 · 서버 계약 · 현재 리비전(§5) |
| `docs/DESIGN.md` | 디자인 시스템 전문. 색·타이포·컴포넌트·미결 항목 |
| `docs/ANALYTICS_EVENTS.md` | 사용 통계 이벤트 · 앱이 버틴 오류(Crashlytics 비치명)의 단일 기준표. 이벤트를 더하거나 고치면 이 표도 같이 고친다 |
| `run.md` | 실행 · AAB 빌드 · TestFlight · 아이콘 절차 |
| `assets/images/` | DESIGN.md 기준 확정 채택된 UI용 PNG 자산 |
| *(별도 저장소)* `datingApp.pen` · `preview/*.png` | Pencil 시안 원본과 화면 미리보기. OneDrive `datingApp` 저장소에 있음 (이 저장소에는 없음) |

---

## 3. 아키텍처

### 3.1 계층

| 계층 | 위치 | 역할 |
| --- | --- | --- |
| **View** | `<기능>/view/` | 화면과 위젯. 표시와 이벤트 전달만 담당 |
| **ViewModel** | `<기능>/viewmodel/` | 흐름 제어. UiState 생성, View 이벤트 처리 |
| **Model** | `<기능>/model/{repository,data}/` (auth · profile · billing 은 `<기능>/<세부 기능>/model/{repository,data}/`) | 비즈니스 로직, 엔티티, Repository (`repository/` 는 서버 · SDK 를 부르는 코드, `data/` 는 데이터 모양과 순수 규칙) |

- **의존성 방향은 항상 안쪽(Model)을 향한다.** Model 은 View 를 모른다.
- **ViewModel 은 Flutter 위젯 타입을 참조하지 않는다** (`BuildContext`, `Widget` import 금지). Riverpod `Notifier` 는 순수 Dart 클래스로 쓴다.
- 핵심 로직은 위젯 없이 테스트 가능해야 한다.

### 3.2 패키지 구조

```
lib/
├── <기능>/                    아래 14개 기능이 이 모양이다
│   ├── model/
│   │   ├── repository/        서버 · SDK · 기기 저장을 부르는 코드
│   │   └── data/              데이터 모양과 순수 규칙
│   ├── view/                  화면과 위젯
│   └── viewmodel/             UiState · ViewModel
├── auth/<세부 기능>/          조각 1 — 가입 인증: social · school_email · school_info · gate · media
├── profile/<세부 기능>/       조각 2 — 프로필 입력: onboarding · basic · appearance · traits · ideal · bio · avatar
├── billing/<세부 기능>/       조각 7 — 결제: store · task
│                              (위 세 줄의 `<세부 기능>/` 안은 `<기능>/` 과 같은 모양이다: model/{repository,data} · view · viewmodel)
├── l10n/                      app_ko.arb (문구 파일, 한국어만) — 생성 파일(app_localizations*.dart)은 커밋하지 않는다
├── main.dart
├── common/                    값 타입(Failure · Result), 공용 위젯 — 기능 폴더가 아니다
└── core/                      기능 폴더가 아니다
    ├── draft/             온보딩 입력 임시 저장(DraftStore · DraftScreen)
    ├── supabase/          클라이언트 초기화, 테이블 상수
    ├── router/            go_router 라우팅
    ├── push/              FCM 초기화·토큰 관리
    ├── analytics/         사용 통계 · 오류 수집 · 성능 측정 — 약관 동의 뒤에만 켠다
    ├── app_update/        강제 업데이트(서버 최소 버전과 비교)
    ├── l10n/              context.l10n 확장(l10n_context.dart) · 에러 문구(error_text.dart)
    ├── auth · http · offline · lifecycle · haptics · back_exit · env.dart   세션 · API 클라이언트 · 오프라인 화면 · 앱 복귀 새로고침 · 햅틱 · 뒤로가기 종료
    └── theme/             디자인 토큰 (DESIGN.md §12 매핑)
```

`<기능>` 14개: tour · faq · account · community · notifications · referral · me · consent · friend_review · graduate · home · chat · safety · matching. **큰 기능 3개 — auth · profile · billing — 는 `<기능>/<세부 기능>/` 한 층을 더 둔다.**

| 폴더 | 넣는 것 | 넣지 않는 것 |
| --- | --- | --- |
| `model/repository/` | abstract Repository · Gateway · Store · Client(약속), `Http…` · `Supabase…` · SDK 구현, Riverpod provider 파일(`…_provider.dart`), 기기 저장 | 엔티티 · enum · 상수 · 순수 함수 |
| `model/data/` | 엔티티, enum, 값 객체, 상수(링크 · 한도), `…Submission` · `…Request` 같은 요청 값, sealed 결과 타입, 서버 · SDK 를 안 부르는 순수 규칙 함수 | 서버 · SDK 호출, provider |
| `view/` | 화면 · 위젯 | 상태 만들기, 서버 호출 |
| `viewmodel/` | UiState · ViewModel (`BuildContext` · `Widget` 금지) | 위젯 |

- **한 파일에 data 와 repository 를 섞지 않는다.** 섞이면 data 를 `model/data/` 의 새 파일로 뺀다.
- **의존은 안쪽으로만**: `view → viewmodel → model/repository → model/data`. `data/` 는 `repository/` 를 import 하지 않는다.
- 새 파일을 만들 때 "서버 · SDK 를 부르는가?" 한 가지만 묻는다 — 예 → `repository/`, 아니오 → `data/`. provider 파일은 예.
- 가짜(Fake)는 `test/` 의 같은 자리 `…/model/repository/fake_*.dart`. 시험 경로는 lib 경로를 그대로 미러링한다(`test/<기능>[/<세부 기능>]/model/{repository,data}/…`).
- `core/` · `common/` 은 이 규칙 밖이다.

**세부 기능 규칙** (auth · profile · billing)

- 세부 기능마다 `<기능>/` 과 같은 모양(`model/{repository,data}` · `view` · `viewmodel`)이다. 화면이 없는 세부 기능(`auth/gate` · `auth/media`)은 `model/` 만 둔다.
- 파일이 많고 화면 묶음이 뚜렷한 기능만 세부 기능으로 나눈다. 서버 호출 하나(Repository 한 개)가 여러 묶음에 걸쳐 있으면 나누지 않는다(matching · chat 은 나누지 않았다).
- **세부 기능끼리 import 는 한 방향만**(순환 금지). 지금 방향: `profile/{basic,appearance,traits,ideal,bio,avatar}` → `profile/onboarding`, `profile/ideal` → `profile/{appearance,traits}`, `billing/store` → `billing/task`, `billing/task` → `profile/avatar`, `auth/school_email` → `profile/onboarding`, `profile/avatar` · `billing/task` → `auth/media`. 새 import 가 이 방향을 거스르면(순환이 생기면) 둘이 같이 쓰는 조각을 더 안쪽 세부 기능으로 옮긴다.
- 여러 세부 기능이 같이 쓰는 값 · 위젯은 가장 안쪽에 둔다 — `profile/onboarding`(단계 흐름 · `profile_enums` · `hint_line` · `writing_example`), `auth/media`(얼굴 검사 · 사진 압축).

새 화면을 추가할 때 이 3단 구조를 그대로 따른다. 벗어난 코드가 있으면 리팩터링해서 맞춘다.

### 3.3 데이터 흐름

```
View --이벤트--> ViewModel --호출--> Model(Repository)
View <--UiState-- ViewModel
```

- 상태는 `UiState` 클래스 **하나로 모아** 노출한다 (필드별 상태 남발 금지)
- 일회성 이벤트(스낵바, 화면 이동)는 상태가 아니라 별도 이벤트로 처리한다
- 위젯은 상태를 직접 만들지 않고 받는다 (stateless 우선, hoisting)

### 3.4 UseCase 사용 기준

**항상 만들지 않는다.** 아래일 때만 도입한다.

- 로직이 ViewModel 에 두기엔 복잡하거나 여러 화면에서 재사용될 때
- 여러 도메인 객체를 조합해야 할 때

단순한 흐름이면 ViewModel 이 Repository 를 직접 호출한다.

---

## 4. 객체지향 생활 체조 (Dart 이식)

> **적용 범위**: `model/`(Domain) 계층에는 **전부 엄격 적용**한다.
> `UiState` 클래스와 위젯 파라미터는 **원칙 7(변수 2개 이하)·9(프로퍼티 노출 금지)의 예외**다. 나머지는 모든 계층에 적용한다.

| 원칙 | Dart 에서의 형태 |
| --- | --- |
| 1. 한 메서드에 한 단계 들여쓰기 | early return, 컬렉션 함수, `switch` 표현식으로 중첩 제거 |
| 2. `else` 금지 | early return / guard clause / `switch` 표현식 |
| 3. 원시값 포장 | `extension type` 또는 불변 클래스 (`UniversityEmail`, `Nickname`, `Age`) |
| 4. 한 줄에 점 하나 | 컬렉션 체이닝과 **위젯 빌더 체이닝은 예외** |
| 5. 축약 금지 | 완전한 단어 (`id`, `url`, `ui`, `dp` 등 통용 약어는 예외) |
| 6. 엔티티를 작게 | **메서드 10줄 이하**, 한 가지 일만. 위젯도 길어지면 하위 위젯으로 분리 |
| 7. 인스턴스 변수 2개 이하 | Model 계층에 엄격 적용. `UiState` 는 예외 |
| 8. 일급 컬렉션 | 컬렉션 하나만 필드로 갖는 클래스 (`InterestTags`, `SurveyAnswers`) |
| 9. getter/프로퍼티 노출 금지 | 필드는 `_private`, **행위 메서드**만 공개. Tell, Don't Ask. `UiState` 는 예외 |

```dart
// 나쁜 예 — 값을 꺼내 외부에서 판단
if (tags.values.length > maxCount) { ... }

// 좋은 예 — 객체에게 묻는다
if (tags.exceeds(maxCount)) { ... }
```

---

## 5. 명시적 표현 (애매함 금지)

- 동작이 한눈에 명확하지 않거나 의도·예외 처리가 헷갈릴 수 있는 부분은 **한국어 주석 또는 명시적 코드**로 의도를 드러낸다
- 매직 넘버, 암시적 null 처리, 분기의 의미는 이름이나 주석으로 분명히 한다
- 문자열과 색상은 **상수/토큰을 통해서만** 참조한다 (화면 문구는 ARB, §7.2)

```dart
// 나쁜 예 — 0이 무슨 의미인지 불명확
if (status == 0) { ... }

// 좋은 예
const int statusPending = 0;
if (status == statusPending) { ... }   // 대기 상태일 때만 처리
```

---

## 6. 객체지향 5원칙 (SOLID)

- **SRP** 하나의 클래스는 하나의 변화 축만 담당한다
- **OCP** 확장에는 열려 있고 변경에는 닫혀 있다
- **LSP** 서브 타입은 기반 타입과 언제나 교체 가능하다
- **ISP** 쓰지 않는 인터페이스를 구현하지 않는다
- **DIP** 상위 모듈이 하위 모듈의 구현이 아니라 추상에 의존한다

---

## 7. UI 작업 규칙

### 7.1 디자인 · 토큰 · 움직임

- **DESIGN.md 먼저.** 해당 화면의 컴포넌트 스펙(§8)과 화면 목록(§9)을 읽고 시작한다. 시안에 없는 화면·상태를 만들어야 하면 **먼저 질문한다**
- **토큰만 사용한다.** `lib/core/theme/` 에 아래 파일을 두고, 위젯은 여기서만 값을 가져온다 (DESIGN.md §12)

  | 파일 | 클래스 | 근거 |
  | --- | --- | --- |
  | `app_colors.dart` | `AppColors` | DESIGN.md §2 |
  | `app_typography.dart` | `AppTypography` | §3.2 |
  | `app_spacing.dart` | `AppSpacing` | §4.1 |
  | `app_radius.dart` | `AppRadius` | §5.1 |
  | `app_motion.dart` | `AppMotion` | §7 |
  | `app_elevation.dart` | `AppElevation` | §6 |
  | `app_lottie.dart` | `AppLottie` | §7 Lottie 장면 표 |
  | `app_icons.dart` | `AppIcons` | §5.3 Lucide 이름 매핑 |
  | `app_theme.dart` | `AppTheme` | 위를 조립한 `ThemeData light()` |

- **아이콘은 Lucide (`lucide_icons_flutter`)** 로 통일한다. 위젯에서 `LucideIcons.*` 를 직접 부르지 않고 `AppIcons` 상수를 거친다 (DESIGN.md §5.3)
  - **예외: 하트 재화 글리프.** 잔액·번들·리워드·CTA·아바타 코스트·설정 보유하트 등 "재화" 의미의 하트는 Lucide 가 아니라 이미지 자산 `assets/images/heart-flat-vector-v3.png` 를 쓴다 (DESIGN.md §5.4·§8.10). 바텀 내비 오늘 탭·호감 하트·매칭 기록 등 비(非)재화 하트는 계속 Lucide `heart`. 재화 글리프는 다크 배경에서도 읽히는 렌더 + `@2x`/`@3x` 자산 + `Semantics(label: '하트')` 를 갖춘다
- **버튼은 공용 `AppButton`(`common/widgets/app_button.dart`, pen Button `HE8FZ`)을 그대로 쓰고 라벨 크기를 화면에서 바꾸지 않는다.** 라벨은 16/700(`AppTypography.button`) — 채움 버튼은 높이 52 · 모서리 14, text 변형은 높이 48 · 16/600, 탈퇴 시트 `neutral` 만 18/700 이다(DESIGN.md §8.3). 10b · 받은 신청 프로필 보기의 아이콘 결정 버튼은 `AppTypography.label` 18/700 이다. `{colors.primary}` (#FF385C) 위 흰 글씨는 대비 3.52:1 이라 큰 글씨 예외(18.66px 이상 굵은 글씨)에 의존해야 하는데 16/700 은 그 예외에 들지 않는다 — 미결이다(DESIGN.md §2.1 · §8.3 · §13-151)
- **`{colors.primary}` 는 채움 전용.** 흰 배경 위 텍스트에는 `{colors.primary-text}` (#C4224B) 를 쓴다
- **사용자는 전 화면에서 닉네임으로만 표시한다. 실명(`real_name`)은 서버 응답에 담지 않는다** (DESIGN.md §8.7 · 설계 문서 §7.3, ERD.md §11-2). 실명은 받지도 보이지도 않는다 — 학생증 인증 제거(2026-10-17) 뒤 서버 `GET /account` 도 싣지 않고 앱도 읽지 않는다(옛 계정의 암호문이 `profile_private.real_name_enc` 에 남아 있어도 읽지 않는다). `김○○` 같은 마스킹 표시는 쓰지 않는다
- **`MediaQuery.disableAnimations` 를 존중한다.** 켜져 있으면 모든 모션 시간을 0으로 만들고 최종 상태를 즉시 그린다
- **글자 크기는 `AppTypography` 토큰으로만 정한다.** 기준은 48 · 32 · 24 · 20 · 18 · 16 · 14 · 12 · 10(모두 짝수)이고, 화면에 `fontSize: 숫자` 를 쓰지 않는다 — 토큰을 쓰고 굵기 · 줄 높이만 `copyWith` 로 바꾼다. `test/core/theme/font_size_tokens_test.dart` 가 `lib/core/theme` 밖의 `fontSize:` 를 잡는다(예외는 `auth/social/view/social_login_button.dart` 카카오 · 구글 공식 버튼 한 파일). DESIGN.md §3.2
- **움직이는 그림(Lottie)은 `AppLottieView`(`lib/common/widgets/app_lottie_view.dart`) 한 곳으로만 부른다.** `package:lottie` 를 다른 파일에서 부르면 `test/common/widgets/app_lottie_view_test.dart` 가 실패한다. 장면은 `AppLottie` 표(`core/theme/app_lottie.dart`)에 한 줄 더하고 화면은 경로 글자를 직접 쓰지 않는다. 에셋은 `assets/lottie/<이름>.json` + 그림 `assets/lottie/images/<이름>/`(json 의 그림 폴더 `assets[].u` 가 `images/<이름>/` — 폴더 항목은 하위 폴더를 담지 않아 pubspec 에 그림 폴더를 따로 적는다). 크기 예산은 json 100KB · 장면 하나(그림 포함) 400KB. 색은 그림 속 색 그대로 둔다(앱 토큰으로 바꾸지 않는다). "동작 줄이기" 면 장면마다 정한 멈춤 프레임에 선다. 지킴 시험 `test/core/theme/app_lottie_test.dart`. DESIGN.md §7
- **눌림 효과(잉크)는 움직이는 쪽 안에 가둔다** — `InkWell` 등을 스크롤 · 페이지 · 애니메이션 안에 둘 때는 `Material(type: MaterialType.transparency)` 로 감싼다. 새 화면을 만들 때와 리뷰할 때마다 본다

### 7.2 화면 문구 · 에러 문구 (ARB)

- **화면 문구는 문구 파일 한 곳에서만 정한다.** `lib/l10n/app_ko.arb`(한국어만, `l10n.yaml` 이 `AppLocalizations` 를 만든다)에 키를 더하고 `context.l10n.<키>`(`lib/core/l10n/l10n_context.dart`)로 읽는다. 키 이름은 `<기능><화면/요소><뜻>`(예 `faqSearchHint`), 뜻과 글자가 모두 같은 공용 문구는 `common<뜻>`.
- **`lib/` 전체에 한글 문자열 리터럴이 없다**(생성 폴더 `lib/l10n/` 제외). 서버와 글자까지 같아야 하는 값(프로필 태그 · 투표 기본 선택지 · 서버 문구 비교 상수)은 옮기지 않고 `// l10n-ignore(wire|server-text): 이유` 마커를 단다. 로그(`debugPrint`) · `assert` · `throw` · `RegExp` 안의 글자는 면제다. 서버가 문구를 비교하는 상수(`l10n-ignore(server-text)` 자리)는 앱 글자만 바꾸면 비교가 깨지므로 서버와 같이 바꾼다 (전체 목록은 `grep -rn "l10n-ignore" lib`). 지킴 시험 `test/l10n/no_hangul_literal_test.dart`. ARB 형식(정렬 · 중복 · 자리표시자 · 안 쓰는 키)은 `test/l10n/arb_test.dart` 가 지킨다.
- **문구의 보조 용언은 띄어 쓴다** — "골라 주세요 · 알려 드릴게요" (붙인 "골라주세요" 는 `test/l10n/ko_spacing_test.dart` 가 잡는다, §8 표). 서버가 같은 글자로 비교하는 `l10n-ignore(server-text)` 문구는 서버와 같이 바꾼다.
- **ARB 를 고치면 `flutter pub get` 을 먼저 한다.** 생성 파일(`lib/l10n/app_localizations*.dart`)은 커밋하지 않고(`.gitignore`) `flutter pub get` · `flutter run` · `flutter build` 가 만든다. `flutter test` · `flutter analyze` 만으로는 만들지 않아, 없으면 "Undefined name AppLocalizations" 가 난다 (CI 는 `flutter pub get` 으로 시작해 영향 없음).
- **에러 문구는 키가 `error` 로 시작하고, 글자로 바꾸는 곳은 `lib/core/l10n/error_text.dart` 한 파일뿐이다.** 뷰모델은 문자열을 만들지 않고 `Failure`(`common/failure.dart` 의 sealed 종류)만 상태에 담고, view 가 `context.errorText(failure)` 로 읽는다. **에러 자리(뷰모델 · UiState 에서 이름에 error · failure · rejection 이 든 칸)는 `Failure?` · `AppError?` 만** — `String` 이면 `test/l10n/error_slot_type_test.dart` 가 잡는다(view 위젯의 글자 인자 `LabeledField.errorText` · `AppToast.label` 은 대상 아님). 에러가 아닌 곳에서 `error*` 키를 쓰거나 `error_text.dart` 가 일반 키를 쓰면 `test/l10n/error_key_scope_test.dart` 가 잡는다. 서버가 준 문구를 그대로 보이는 가지(거절 종류)만 ARB 를 쓰지 않는다 (서버 `detail` 이 기준)
- **`context.l10n` 에는 한국어 대체가 없다.** `l10n.yaml` 의 `nullable-getter: false` 라 위임자(`AppLocalizations.localizationsDelegates`)가 없는 곳에서 읽으면 바로 실패한다. lib 은 `AppLocalizationsKo()` 를 직접 만들지 않는다(`test/l10n/no_direct_korean_l10n_test.dart`).
- **시험의 `MaterialApp` · `MaterialApp.router` 는 앱(`lib/main.dart`)과 같은 위임자를 단다**: 도우미 없이 `localizationsDelegates: AppLocalizations.localizationsDelegates` · `supportedLocales: AppLocalizations.supportedLocales` 두 줄. 빠뜨리면 문구를 읽는 위젯이 바로 실패하고, 문구를 안 읽는 위젯(머티리얼 영어 기본 글자 'Back' 등으로 조용히 도는 곳)은 `test/l10n/test_app_delegates_test.dart` 가 잡는다(위임자를 일부러 빼는 시험은 그 파일의 예외 목록에만 둔다). 앱은 머티리얼 · 쿠퍼티노 한국어 위임자를 켜므로 기본 글자(뒤로 가기 툴팁 · 새로고침 · 붙여넣기 등)도 한국어다.
- **시험에서 `tester.pageBack()` 은 쓰지 않는다** — SDK 가 영어 'Back' 툴팁을 박아 두었다(`flutter_test` `widget_tester.dart`). 대신 `tester.tap(find.byTooltip('뒤로'))`

---

## 8. 테스트

**모든 비(non-)private 클래스는 테스트를 갖는다.**

| 대상 | 위치 | 방식 |
| --- | --- | --- |
| 값 객체 · Model | `test/` | `package:test` 단위 테스트 |
| Repository | `test/` | 인터페이스 뒤 **Fake 구현**으로 검증 |
| ViewModel | `test/` | Riverpod 컨테이너 + Fake repository |
| 화면 · 위젯 | `test/` | `testWidgets` 위젯 테스트 |
| **RLS 정책** | `../supabase/tests/` | **다른 사용자로 조회 시 0행인지 SQL 로 검증** |

마지막 항목을 별도로 두는 이유: **RLS 는 틀려도 앱이 정상 동작한다.** 테스트가 없으면 유출을 출시 후에야 알게 된다.

- 이름 규칙: `SignUpViewModel` → `sign_up_view_model_test.dart`
- 경로는 프로덕션 코드를 그대로 미러링한다 (`test/auth/school_email/viewmodel/`, `test/chat/model/repository/`)
- 쪼갠 data 조각의 시험은 당분간 원본 시험 파일 자리에 둔다(예: `contact_name_store_test` 가 `data/contact_label.dart` 도 본다)
- private 클래스·함수는 직접 테스트하지 않고 public 진입점을 통해 커버한다
- 목(mock)은 `mocktail` 을 쓰되, Repository 는 **Fake 구현을 우선**한다

**지킴 시험 (규칙을 어기면 실패한다)**

| 시험 | 지키는 규칙 |
| --- | --- |
| `test/l10n/no_hangul_literal_test.dart` | `lib/` 에 한글 문자열 리터럴 금지, `l10n-ignore` 마커 형식 |
| `test/l10n/arb_test.dart` | ARB 형식(정렬 · 중복 · 자리표시자 · 안 쓰는 키) |
| `test/l10n/error_key_scope_test.dart` | `error*` 키는 `error_text.dart` 에서만, `error_text.dart` 는 일반 키 금지 |
| `test/l10n/error_slot_type_test.dart` | 에러 자리는 `Failure?` · `AppError?` (`String` 금지) |
| `test/l10n/no_direct_korean_l10n_test.dart` | lib 에서 `AppLocalizationsKo` 직접 생성 금지 |
| `test/l10n/test_app_delegates_test.dart` | 시험의 `MaterialApp` 은 앱과 같은 문구 위임자를 단다 |
| `test/l10n/ko_spacing_test.dart` | ARB 문구에 붙여 쓴 보조 용언 "-아/어 주다 · 드리다"(골라주세요 · 알려드릴게요 · 그려준 · 골라줘 …)가 없다 — 띄운다(골라 주세요 · 알려 드릴게요). 사전 한 낱말(도와주다 · 내주다 · 돌려주다 · 넘겨주다 · 들어주다 · 알아주다 · 봐주다 · 보아주다 · 들려주다 · 빌려주다 · 물려주다 · "-다 주다" 꼴)과 명사+접미사 "-드리다"(감사 · 축하 · 인사 · 사과 · 안내 · 전화 · 부탁 · 연락)는 붙여 써도 통과한다. 새 예외는 시험 파일의 예외 목록에 더한다 |
| `test/core/theme/font_size_tokens_test.dart` | 화면에 `fontSize: 숫자` 금지 |
| `test/core/theme/app_lottie_test.dart` | Lottie 장면 표 · 에셋 · pubspec 그림 폴더 · 크기 예산 |
| `test/common/widgets/app_lottie_view_test.dart` | `package:lottie` 는 `AppLottieView` 한 곳에서만 |
| `test/auth/social/view/start_view_test.dart` | 심사원 로그인 입구와 소셜 버튼이 겹치지 않음 |

---

## 9. Git 전략

**규칙 전문은 `../docs/GIT.md` 에 있다. git 작업(브랜치·커밋·푸시·PR)을 시작하기 전에 그 문서를 읽는다.** 여기에는 어기면 되돌리기 어려운 것만 남긴다.

- 커밋 메시지는 **`<이모지> <타입>(<scope>): <한국어 요약>`**, 이모지는 유니코드로 한 커밋에 하나. **`main` 직접 커밋·푸시 금지** — 작업 브랜치 `<타입>/<주제>` 에서 **커밋 → 푸시 → draft PR 까지만** 하고 merge 는 사용자가 한다
- 스테이징은 **파일 이름으로** 한다(`git add -A` 금지). **`git push --force` · `--no-verify` 금지.** 커밋·PR 본문에 도구 표식(`Co-Authored-By: Claude …` 등)을 넣지 않는다
- merge 된 브랜치는 로컬·원격에서 바로 지우고, **`git pull` 은 사용자가 요청할 때만** 한다

---

## 10. 빌드 / 실행 명령

Windows PowerShell 기준, 프로젝트 루트에서:

```powershell
flutter pub get                  # 의존성 + 문구(ARB) 생성 — lib/l10n/app_ko.arb 를 고쳤으면 flutter test · analyze 전에 한 번 (생성 파일은 커밋하지 않는다)
flutter run                      # 디버그 실행
flutter test                     # 전체 테스트
flutter analyze                  # 정적 분석
flutter build apk --debug
```

`flutter analyze` 는 `analysis_options.yaml` 에서 lint 규칙을 켠 채 돈다 — 새로 쓰는 코드의 기준이다.

- 켜진 규칙 13개: `always_declare_return_types` · `always_use_package_imports` · `cancel_subscriptions` · `avoid_void_async` · `prefer_final_in_for_each` · `unawaited_futures` · `prefer_final_locals` · `prefer_single_quotes` · `prefer_const_constructors` · `prefer_const_declarations` · `close_sinks` · `only_throw_errors` · `avoid_dynamic_calls` (앞 5개는 앱 1.0.1, 뒤 8개는 B4 PR #684 에서 켰다)
- **`flutter analyze` 는 info 까지 0건이어야 한다.**
- 기다리지 않는 Future 는 `unawaited(...)` 로 감싼다(`unawaited_futures`). 문자열은 홑따옴표, 지역 변수는 `final`, 상수로 만들 수 있는 생성자·선언은 `const`.
- **`// ignore: <규칙>` 은 이유 한 줄과 같이 쓸 때만 허용한다.**

Supabase 마이그레이션(**저장소 루트**에서 실행 — `supabase/` 가 `frontend/` 밖에 있다):

```powershell
supabase db reset                # 빈 DB 에 마이그레이션 처음부터 적용
supabase test db                 # RLS 정책 SQL 테스트
```

### 10.1 Supabase 작업 규칙

**규칙 전문은 `../docs/SUPABASE.md` 에 있다. Supabase 작업(스키마·RLS·Storage·Auth)을 시작하기 전에 그 문서를 읽는다.**
(키·식별자 취급, 마이그레이션 파일과 클라우드 적용 절차, RLS·grant 체크리스트, pgvector. 마이그레이션 주석·ERD 가 인용하는 이 절의 세부 규칙도 그 문서에 있다)

여기에는 어기면 되돌리기 어려운 금지 규칙만 남긴다.

- 프로젝트 URL · project ref · anon/publishable 키 · `service_role` 키 · DB 비밀번호는 **문서·코드·커밋·PR 에 쓰지 않는다.** 필요하면 MCP 로 조회해 앱에는 `--dart-define` 으로 주입한다. `service_role` 키는 FastAPI 서버 전용이다
- **스키마 변경은 `supabase migration new <name>` 으로 만든 `../supabase/migrations/*.sql` 파일로만 한다.** 대시보드·`execute_sql` 로 DDL 을 실행하지 않는다
- **클라우드 쓰기(마이그레이션 적용·seed·`migration repair` 등)는 매번 사용자가 직접 승인한 뒤에만 한다**
- 프로덕션 DB 에서 `execute_sql` 은 **읽기 전용 조회**에만 쓴다

---

## 11. 저장소와 자산 주의사항

- **⚠️ 이 저장소는 공개(public)다.** `assets/images/` 의 `human1.PNG` · `human2.PNG` 와 그 파생본(`card-*` · `avatar-*` · `rail-*`)은 **실존 인물 사진**이라 **`.gitignore` 로 제외되어 있다. 이 제외 규칙을 절대 풀지 않는다.** 로컬에만 두고, 커밋·푸시하지 않는다. 한 번 올라가면 히스토리·캐시·크롤러에 남아 되돌릴 수 없다
- **mock 이미지가 필요하면 `animal-face-*`(8종) 와 `mascot-*`(5종) 일러스트를 쓴다.** 실존 인물이 아니고 DESIGN.md 화면 구성이 이미 이쪽으로 대체됐다. 인물 사진은 참조하지 않는다
- **`datingApp.pen` 은 이 저장소에 없다.** OneDrive `datingApp` 저장소에 있고, 암호화된 바이너리라 git 이 diff·merge 를 하지 못하므로 그쪽에서도 두 대에서 동시에 편집하지 않는다
- **Supabase 키·OpenAI 키를 저장소에 넣지 않는다.** `--dart-define` 또는 `.env`(gitignore 대상)로 주입한다

---

## 12. 다른 PC 에서 이어받을 때

1. **Claude Code 대화 기록은 저장소에 없다.** 새 세션은 맥락 0 에서 시작한다. `docs/DESIGN.md` §13 미결 항목과 `../docs/superpowers/specs` (저장소 루트)를 먼저 읽으면 현재 상태를 복원할 수 있다
2. **새 PC 준비는 `../docs/SETUP.md` 를 따른다** — 스킬 재설치, Pencil 앱, Pretendard 폰트, Flutter SDK · Supabase CLI · `gh`, graphify, IDE(`frontend/` 를 연다), 실존 인물 목업 이미지

---

## 13. 작업 진행 방식

- **한 번에 하나의 작업만 끝내고 멈춘다.** 여러 화면을 한꺼번에 만들지 않는다
- 작업 완료 시: 변경된 파일 목록 + 무엇을 왜 그렇게 했는지 + 확인이 필요한 지점을 요약해 보고한다
- 다음 중 하나라도 해당하면 진행 전에 사용자에게 질문한다
  - DESIGN.md 에 없는 화면/상태를 만들어야 할 때
  - DESIGN.md 와 설계 문서가 서로 모순될 때
  - 새 의존성을 추가해야 할 때
  - 기존 패키지 구조를 바꾸는 리팩터링이 필요할 때
  - DESIGN.md §13 의 미결 항목에 걸리는 결정을 해야 할 때

---

## 14. 요약 체크리스트

**아키텍처**

- [ ] View ↔ ViewModel ↔ Model 구조를 지켰는가?
- [ ] 기능별 패키지 아래 `model` / `view` / `viewmodel` 로 분리했는가? `model` 안은 `repository` / `data` 로 나눴는가? auth · profile · billing 은 세부 기능 폴더(`<기능>/<세부 기능>/…`)마다 같은 모양이고, 세부 기능끼리 import 가 한 방향(순환 없음)인가?
- [ ] ViewModel 이 `BuildContext` / `Widget` 을 참조하지 않는가?
- [ ] UseCase 는 정말 필요할 때만 도입했는가?

**객체지향 생활 체조** (Model 은 엄격, UiState 는 원칙 7·9 예외)

- [ ] 메서드 들여쓰기가 한 단계인가? `else` 없이 early return 으로 풀었는가?
- [ ] 원시값을 의미 있는 타입으로 포장했는가?
- [ ] 메서드가 10줄 이하이고 한 가지 일만 하는가?
- [ ] 컬렉션을 일급 컬렉션으로 감쌌는가?
- [ ] Model 에서 프로퍼티 노출 없이 객체에게 일을 시켰는가?
- [ ] SOLID 를 위반하지 않았는가?

**UI**

- [ ] DESIGN.md 의 해당 컴포넌트 스펙을 읽고 시작했는가?
- [ ] 색·타이포·간격·라운드를 `core/theme/` 토큰으로만 참조했는가?
- [ ] 글자 크기를 `AppTypography` 토큰으로만 정했는가? (`fontSize:` 숫자 금지 — 지킴 시험이 잡는다)
- [ ] 화면 문구를 ARB(`context.l10n`)에만 두고 한글 리터럴을 쓰지 않았는가? ARB 를 고친 뒤 `flutter pub get` 을 했는가?
- [ ] 에러를 `Failure?` 로 담고 view 에서 `context.errorText` 로 읽었는가? (`String` 에러 칸 금지)
- [ ] 새 위젯 시험의 `MaterialApp` 에 문구 위임자 두 줄을 달았는가?
- [ ] 움직이는 그림을 `AppLottieView` + `AppLottie` 표로만 썼는가?
- [ ] 아이콘을 `AppIcons` 를 통해 Lucide 로 썼는가?
- [ ] `primary` 위 텍스트가 `AppButton` 공용 값(16/700, 위 §7.1)을 따르는가? 화면에서 따로 키우거나 줄이지 않았는가?
- [ ] 사용자를 닉네임으로 표시하고, 실명이 서버 응답에 들어가지 않는가?
- [ ] 축소 모션 설정을 존중하는가?

**기타**

- [ ] 코드·네이밍은 영어, 주석·문서는 한국어인가?
- [ ] 애매한 부분을 주석/이름으로 명시했는가?
- [ ] 핵심 로직과 UI 로직이 분리되어 있는가?
- [ ] 모든 비-private 클래스에 테스트가 있는가?
- [ ] 새 의존성을 사용자에게 확인받았는가?
- [ ] 사용 통계 이벤트를 더하거나 고쳤다면 `docs/ANALYTICS_EVENTS.md` 표도 함께 고쳤는가? (매개변수에 개인 값 · 오류 메시지가 없는가?)
- [ ] 키·비밀값이 저장소에 들어가지 않았는가?
