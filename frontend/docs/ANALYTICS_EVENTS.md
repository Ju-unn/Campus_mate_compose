# 사용 통계 · 오류 수집 이벤트 표

앱이 Firebase Analytics 로 보내는 이벤트와 Crashlytics 로 보내는 "앱이 버틴 오류"의 **단일 기준표**다(2026-11-02, 앱 1.0.1).
이벤트를 더하거나 고치면 **이 표도 같이 고친다**(`frontend/CLAUDE.md`).

## 0. 원칙 (어기면 안 되는 것)

- **약관 동의(02-c) 뒤에만 수집한다.** 켜고 끄는 때는 `CollectionConsent`(`lib/core/analytics/collection_consent.dart`)가 정한다. 동의 전에는 Firebase 가 기기에 기억한 "꺼짐"(`AndroidManifest.xml` · `Info.plist`)이라 아무것도 나가지 않는다. 이벤트를 보내는 코드는 수집을 스스로 켜지 않는다.
- **개인을 가리키는 값은 매개변수에 없다.** 사용자 id · 닉네임 · 학교 · 상대 id · 카드 id · 채팅방 id · 제안 id · 금액 · 글 내용 · 오류 메시지 원문은 받는 자리가 없다. 매개변수는 **정해진 종류값(`lib/core/analytics/analytics_values.dart`)과 작은 정수(머문 초 · 단계 번호)와 상품 ID**뿐이다.
- `setUserId` · `setUserProperty` · `setCustomKey` · `setUserIdentifier` 는 쓰지 않는다.
- Firebase 이름 규칙: 이벤트 이름 40자 이하 snake_case, 매개변수 이름 40자 이하, 문자열 값 100자 이하. (`firebase_analytics_service_test.dart` 가 보낸 이벤트 전부를 이 규칙으로 검사한다.)
- 구조: `AnalyticsService`(인터페이스) → `FirebaseAnalyticsService`(진짜) / `NoAnalyticsService`(시험 · Firebase 없는 빌드). 오류는 `CrashReporter` → `FirebaseCrashReporter` / `NoCrashReporter`. 시험은 기록만 하는 `FakeAnalyticsService` · `FakeCrashReporter`(`test/core/analytics/`)를 쓴다.
- 자동 수집(활동 시간대 · 재방문 · 세션)은 Firebase 가 하므로 따로 보내지 않는다. **탭 전환(`tab_select`)도 따로 보내지 않는다** — 하단 내비 탭은 각자 경로 이름(`/home` · `/today` · `/community` · `/conversations` · `/me`)을 단 페이지라 `screen_view` 가 이미 잡는다(`test/core/router/app_router_test.dart` "탭끼리 옮겨 가도 화면 추적기가 새 탭을 잡는다"). 이 시험이 깨지면 `tab_select` 를 더해야 한다.

## 1. 사용 통계 이벤트

"파일" 은 이벤트를 보내는 자리다(`lib/` 아래). 모든 이벤트의 공통 통로는 `AnalyticsService` 메서드 → `FirebaseAnalyticsService` 다.

| 이벤트 | 언제 | 매개변수 (값 목록) | 어디서 보냄 (파일) | 무엇을 알기 위해 |
| --- | --- | --- | --- | --- |
| `login` | 소셜 로그인 성공. 약관 동의 전에 한 로그인은 동의 뒤 수집이 켜진 다음 한 번 보낸다 | `method`: `kakao` · `google` · `apple` | `auth/social/viewmodel/start_view_model.dart` | 로그인 수단 비율 |
| `onboarding_complete` | 가입(온보딩)을 방금 끝냄(서버 단계가 `complete` 로 바뀐 순간). 앱을 켰더니 이미 끝난 사람은 세지 않는다 | 없음 | `core/router/onboarding_step_listenable.dart` | 가입 완료 수 |
| `onboarding_step_complete` | 가입 단계 하나를 끝냄(서버 단계가 앞으로 나아간 순간) | `step`: `basic_info` · `kakao_id` · `photos` · `appearance_type` · `interests` · `my_traits` · `survey` · `ideal_conditions` · `ideal_traits` · `ideal_note` · `bio` · `avatar` (`OnboardingStep.wire`) / `seconds`: 0~3600 정수(그 단계가 처음 보인 때부터. 3600 에서 자름) | `core/router/onboarding_step_listenable.dart` (`_logProgress`) | 가입 단계별 이탈 · 오래 걸리는 단계 |
| `onboarding_step_back` | 가입 단계에서 뒤로가기(앞 단계로 돌아감) | `step`: 떠난(뒤로가기를 누른) 단계, 값은 위와 같음 | `core/router/onboarding_step_listenable.dart` (`goBack`) | 어느 화면에서 되돌아가는가 |
| `onboarding_blocked` | 가입 단계 저장이 서버 오류 · 거절로 막히거나, 고른 사진에서 얼굴을 한 장도 못 찾음 | `step`: 막힌 단계 / `reason`: `photo_document`(글자 많은 사진) · `photo_rejected`(그 밖의 서버 사진 거절) · `photo_no_face`(얼굴 없음) · `rejected`(서버가 입력 거절 4xx) · `network` · `server`(5xx) · `rate_limited`(429) · `session` | `core/router/onboarding_step_listenable.dart` (`blocked`), 각 가입 ViewModel 의 저장 실패(`profile/onboarding/viewmodel/onboarding_blocked.dart` 도우미: `kakao_id` · `appearance_type` · `basic_info` · `bio` · `ideal_conditions` · `ideal_note` · `survey` · `tag_picker` · `avatar_generation`), 사진은 `profile/avatar/viewmodel/photos_view_model.dart` | 가입이 왜 막히는가 |
| `chat_request_sent` | 서버가 대화 신청(수락)을 받아 줌 | 없음 | `matching/viewmodel/card_detail_view_model.dart` | 대화 신청 수 |
| `card_view` | 오늘 탭 카드 목록에서 카드 한 장이 처음 화면에 그려짐(앱을 켠 동안 같은 카드는 한 번) | `source`: `free` · `purchased` | `matching/view/today_cards_screen.dart` (`_CardList`) | 카드를 몇 장 보는가 |
| `card_detail_open` | 카드를 눌러 상세(10b)를 엶 | `source`: `free` · `purchased` | `matching/view/today_cards_screen.dart` (`_CardList` 의 `onTap`) | 카드 → 상세 전환 |
| `card_pass` | 상세에서 "넘기기"(거절)를 서버가 받아 줌. 오늘 목록에서 카드 출처를 못 찾으면 보내지 않는다 | `source`: `free` · `purchased` | `matching/viewmodel/card_detail_view_model.dart` (`_logPass`) | 넘기는 비율 |
| `paid_card_view` | 오늘 탭 유료 카드 칸이 보임. 칸 모양이 바뀌면(offered ↔ empty) 한 번 더 | `state`: `offered`(지금 열 사람이 있음) · `empty`(없음) | `matching/view/paid_card_slot.dart` (`_logView`) | 유료 카드 노출 |
| `paid_card_sheet_open` | 유료 카드 "N으로 열기"를 눌러 **열기 확인 시트**가 뜸. 하트가 모자라 부족 시트가 먼저 뜨거나 안내 시트(ⓘ)를 여는 것은 세지 않는다 | 없음 | `matching/view/paid_card_slot.dart` (`_open`) | 유료 카드 구매 의향 |
| `heart_store_open` | 하트 상점(18)에 들어옴 | `from`: `home`(홈 칩 "+") · `settings`(설정 보유 하트 블록 · 하트 충전 줄) · `paid_card`(유료 카드 부족 시트) · `avatar_regen`(아바타 다시 만들기 시트 "하트 충전하기") · `heart_short`(예약 — 아직 쓰는 진입점 없음) · `other`(나 탭 칩 · 앱 투어 6단계 · 길을 직접 연 경우) | `billing/store/view/heart_store_screen.dart`, 길 `core/router/app_router.dart` 의 `extra`, 각 진입점 `home/view/home_screen.dart` · `matching/view/settings_screen.dart` · `matching/view/paid_card_slot.dart` · `me/view/avatar_regen_pick_screen.dart` | 하트 상점에 어디서 들어오는가 |
| `heart_product_select` | 상점에서 상품 카드를 누름 | `product_id`: 스토어 상품 ID(`heart_50` · `heart_100` · `heart_200` · `heart_400` · `heart_800`). 목록에 없는 글자는 보내지 않는다 | `billing/store/viewmodel/heart_purchase_view_model.dart` (`select`) | 어떤 상품을 보는가 |
| `heart_purchase_result` | 사용자가 연 결제 창이 끝남. 느린 결제 확인(pending)과 앱 시작 때의 지난 결제 복구는 세지 않는다 | `result`: `success`(스토어 결제 완료) · `cancel` · `fail`(결제 창 실패 · 열지 못함) / `product_id`: 위와 같음(플러그인이 비워 보낸 취소 · 실패는 사용자가 고른 상품) | `billing/store/viewmodel/heart_purchase_view_model.dart` (`_logResult`) | 결제 중 어디서 그만두는가 |
| `heart_purchase` | 서버가 하트를 새로 지급함(이미 받은 결제는 세지 않는다) | `product_id`: 위와 같음 | `billing/store/viewmodel/heart_purchase_view_model.dart` | 실제 구매 수 |
| `push_open` | 푸시를 눌러 앱이 열리거나 화면이 옮겨짐(꺼진 앱 · 백그라운드 · 앱이 띄운 알림 모두). 앱이 켜진 채 받기만 한 알림은 세지 않는다 | `type`: `daily_card` · `acceptances` · `match` · `chat` · `friend_reviews` · `friend_review_write` · `heart_tasks` · `heart_task_retry` · `poll`(내 O/X 글의 새 댓글) · `other`(모르는 route) — 푸시 `data.route` 와 같은 글자 | `main.dart` (`_openRoute`), 종류 변환 `core/push/push_route.dart` (`typeOf`) | 어떤 알림이 앱을 여는가 |
| `tour_finish` | 앱 투어가 끝남 | `result`: `done`(마지막 "시작하기") · `skip`(건너뛰기 · 시스템 뒤로가기 · 대상이 사라져 강제로 끝남) / `step`: 끝난(건너뛴) 단계 번호, 단계 목록의 몇째(1부터. 대상을 못 찾아 건너뛴 단계가 있어도 같은 단계는 같은 번호) | `tour/viewmodel/app_tour_view_model.dart` (`finish` · `skip`), 호출 `tour/view/app_tour_host.dart` | 투어를 끝까지 보는가, 어디서 건너뛰는가 |
| `poll_vote` | 커뮤니티 투표를 서버가 받아 줌 | 없음 | `community/viewmodel/community_feed_view_model.dart` (`vote`) | 커뮤니티 참여 |
| `poll_create` | 커뮤니티 질문 올리기를 서버가 받아 줌 | 없음 | `community/view/poll_composer_screen.dart` | 커뮤니티 참여 |
| `screen_view` | 화면(경로 패턴)에 들어옴 — Firebase 기본 화면 조회 이벤트. 하단 내비 탭 전환도 포함 | `screen_name`: 경로 패턴(`/chat/:matchId` 꼴, 값이 채워진 경로가 아님). 이름 없는 길(바닥 시트 · 대화상자)은 보내지 않는다 | `core/analytics/screen_view_observer.dart` (go_router `observers`, `main.dart`) | 화면별 방문 · 탭 전환 |

### 알아둘 점

- 매개변수는 Firebase 콘솔에서 **맞춤 측정기준으로 등록해야** 보고서에 나온다(`source` · `step` · `reason` · `from` · `type` · `result` · `state` · `product_id` · `seconds`). 등록 개수에 한도가 있으니 필요한 것부터 등록한다.
- `seconds` 는 앱을 껐다 켜면 그 단계의 시계가 다시 시작한다. 자리를 비운 시간은 3600 에서 잘린다.
- `card_view` 는 앱을 다시 켜면 같은 날 카드가 한 번 더 센다. 사람 수가 필요하면 사용자 수 지표로 본다.
- 한 이벤트가 둘 이상의 의미를 가질 때는 매개변수 값을 늘리지 말고 이벤트를 나눈다(값 목록은 `analytics_values_test.dart` 가 못박는다).
- **심사원 로그인은 `login` 을 남기지 않는다**(앱 1.0.2, 안드로이드 전용 숨은 입구 — 시작 화면 로고 7번 탭, `auth/social/viewmodel/reviewer_login_view_model.dart`; `reviewer_login_view_model_test.dart` 가 못박는다). 구글 Play 심사원의 비밀번호 로그인이 `method` 별 로그인 수단 비율에 섞이지 않게 하려는 것이다. 위 표의 `login` 은 소셜 로그인(`kakao` · `google` · `apple`)만 센다.

## 2. 앱이 버틴 오류 (Crashlytics, 비치명)

앱이 죽지 않았지만 사용자가 겪은 API 오류를 `recordError(fatal: false)` 로 남긴다.

| 항목 | 내용 |
| --- | --- |
| 언제 | API 공통 계층(`core/http/http_send.dart` `sendHttpRequest`)에서 **서버 5xx · 연결 실패 · 조회 시간 초과(15초)** 가 났을 때. 4xx(사용자 입력 오류 · 401 · 429)와 성공은 보내지 않는다. 4xx 인데 몸통이 JSON 이 아니라 생긴 파싱 오류(`FormatException`)도 보내지 않는다 |
| 보내는 것 | `HandledApiError`(`core/analytics/handled_api_error.dart`)의 **세 값뿐**: `kind`(예외 타입 이름 `SocketException` · `TimeoutException` · `ClientException` 등, 5xx 는 `ServerError`) / `status`(5xx 상태 코드, 예외면 없음) / `route`(요청 경로 패턴) |
| 경로 패턴 | `ApiRoutePattern`(`core/analytics/api_route_pattern.dart`). **고정 낱말 목록**(`ApiRoutePattern.routeWords`, 앱이 실제로 부르는 길 조각)에 있는 조각만 남기고 나머지(UUID · 숫자 · 토큰 · 코드, 소문자로만 된 닉네임 · 영문 코드 포함)는 `:id`, 쿼리 문자열과 호스트는 버림. **새 API 경로를 더하면 이 목록에도 더한다**(서버를 부르는 소스를 읽는 지킴 시험이 빠진 낱말을 알려 준다. 2026-11-11 휴대폰 문자 인증이 `phone-verification` · `send` 를 더했다). 예: `/cards/3f2a…/decision?x=1` → `/cards/:id/decision` |
| 보내지 않는 것 | 예외 메시지 · 응답 본문 · 쿼리 문자열 · 요청 본문 · 값이 채워진 id · 사용자 정보. `CrashReporter.recordHandledError` 는 `HandledApiError` 만 받는다(다른 예외를 넘길 수 없다) |
| 폭주 방지 | `HandledErrorReporter`(`core/analytics/handled_error_reporter.dart`): 같은 오류(종류 × 상태 × 경로)는 **1분에 한 번**. 앱을 껐다 켜면 비워진다(shortcut 주석) |
| 연결 | `apiClientProvider`(`core/http/api_client_provider.dart`) → `ApiClient(onHandledError)` → `sendAuthorizedRequest` → `sendHttpRequest`. 보고기가 던져도 사용자 요청 결과는 바뀌지 않는다 |
| 무엇을 알기 위해 | 서버 · 네트워크 문제를 사용자가 어느 길에서 얼마나 겪는가 |

처리되지 않은 치명 오류(`recordFlutterFatalError` · `recordFatalError`)는 이전 그대로다(`core/analytics/crash_error_hooks.dart`).

## 3. 이벤트를 더하는 순서

1. 매개변수에 실을 값이 정해진 종류라면 `lib/core/analytics/analytics_values.dart` 에 enum(`wire` 글자)을 더하고 `analytics_values_test.dart` 에 글자를 적는다.
2. `AnalyticsService` 에 `logXxx` 를 더한다. 세 구현(`NoAnalyticsService` · `FirebaseAnalyticsService` · 시험의 `FakeAnalyticsService`)을 같이 고친다. 개인 값을 받을 수 있는 `String` 매개변수는 만들지 않는다.
3. 보내는 자리에 한 줄을 달고, 그 자리를 거치는 시험을 먼저 쓴다(가짜가 정해진 줄을 받는지 · 개인 값이 안 섞이는지).
4. **이 표에 한 줄 더한다.**
