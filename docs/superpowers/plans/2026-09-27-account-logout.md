# 설정 구멍 두 개: 16g 로그아웃 · 16e 계정 화면 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **v2 (2026-09-27) — pen 값표(대장 `값표_15_16_나탭_프로필탭.md` B5 · B6 · B7) 반영, 대장 허락: 기술 결정 T1 · T2 · T3, 공유 파일 1~7(말한 줄 범위만).** PR 1(Task 1~3)은 값이 모두 채워졌다. PR 2(Task 4~7)의 화면 값은 아래 "화면 대조표" 에 있고, Task 6 코드의 `[pen]` 은 PR 2 시작 때 그 표로 바꾼다.

**Goal:** 앱에 로그아웃 버튼이 없어 사용자가 나갈 방법이 없다 — 설정(16)에 "로그아웃" 줄과 확인 시트(16g)를 붙인다. 이어서 설정 "계정" 줄에서 들어가는 계정 화면(16e)을 만든다.

**Architecture:** PR 두 개로 나눈다. **PR 1(앱만)** 은 이미 있는 `signOut()`(`core/auth/sign_out.dart`)을 설정 줄 → 확인 시트에 잇는다. 그리고 로그아웃하면 `ProviderScope` 를 통째로 새로 만들어 앞 사람의 화면 기억을 버린다. **PR 2(서버 + 앱)** 는 FastAPI `GET /account` 하나로 16e 값을 내려받고, 이메일만 기기의 로그인 세션에서 읽는다.

**Tech Stack:** Flutter 3 · Riverpod 3.4 · go_router · supabase_flutter(gotrue 2.27.2) · FastAPI · httpx · pytest.

**Spec:** `frontend/docs/DESIGN.md` §9(화면 16 · 16e · 16e-1 · 16g, 915~925줄) · §8.7 표(592줄 "설정 > 계정 정보, 본인만 실명 조회") · `frontend/CLAUDE.md` §7(실명 규칙) · `docs/ERD.md` §2(`profile_private` 컬럼 grant) · §11-2 · §11-20.

---

## 코드 조사 (2026-09-27, origin/main `ee66ddc` 기준)

| 본 것 | 결과 |
| --- | --- |
| `core/auth/sign_out.dart` | `signOut(registrar, auth)`: 푸시 토큰을 먼저 지운 뒤 `auth.signOut()`. 부르는 곳이 **0곳**이다(main.dart 주석과 테스트만 있다). |
| gotrue 2.27.2 `_signOut` | **기기 세션을 먼저 지우고** `signedOut` 을 알린 다음 서버에 알린다. 서버 호출이 네트워크 오류면 `AuthRetryableFetchException` 을 **다시 던진다**(401 · 403 · 404 만 삼킨다). 그래서 지금 코드로는 비행기 모드에서 로그아웃하면 로그아웃은 됐는데 예외가 화면까지 올라온다. |
| `PushRegistrar.stop()` | `deletePushToken` 이 `Result` 를 돌려주므로 오프라인이어도 던지지 않는다. |
| 로그아웃 뒤 이동 | `AuthSessionListenable` → 라우터 redirect 가 `/login` 으로 보낸다. `main.dart _refreshVerificationGate` 는 게이트 · 온보딩 단계만 비운다. |
| **남는 기억** | `lib/` 의 provider 중 `autoDispose` 는 채팅방 하나다. `myProfileProvider`(실사진 서명 URL 포함) · `homeSummaryProvider` · 오늘의 카드 · 대화 목록 · 알림 설정 · 온보딩 입력 ViewModel 전부 컨테이너에 남는다. **같은 폰에서 다른 계정으로 로그인하면 앞 사람의 "내 프로필" · 카드가 그대로 보인다.** 지금까지는 로그아웃 버튼이 없어 드러나지 않았다. |
| 설정 화면 | `matching/view/settings_screen.dart`(pen `lMDpY`). 지금 줄: 매칭 활성화 · 알림 · 차단 목록(`o0km6`, 8번). 줄마다 투명 Material 로 감싸는 자리가 한 곳이라 새 줄은 목록에 넣기만 하면 된다. `AppIcons.logOut` 은 이미 있다. |
| 로그아웃 줄 위치 | DESIGN §9 화면 16 "행별 라우팅 확정(13개 행)" 에 **"로그아웃 → `16g`"** 가 설정(16)의 줄로 적혀 있다. 계정(16e) 안이 아니다(pen 값표로 최종 확인). |
| 16e 데이터 출처 | `profiles`(출생연도 · 가입일 `created_at` · 학교)는 본인 행 select 가 열려 있다. `profile_private.real_name` 도 컬럼 grant 로 본인에게 열려 있다. **`kakao_id` 는 앱에 닫혀 있고 FastAPI 가 내려준다**(§11-20). #139 에 `GET /account/kakao-id` 가 이미 있다. 이메일은 `profiles` 에 없고 기기 세션(`auth.currentUser.email`)에 있다. |
| 학생 인증 상태 | 설정은 관문(학생증 · 학과)을 지난 사람만 닿는다 → 16e 에서는 늘 "인증 완료". `/me/profile` 도 같은 이유로 상태를 싣지 않았다. |
| 서버 계정 모듈 | `backend/app/account/`(#139, 안전담당): `POST /account/withdraw` · `GET /account/kakao-id` · `SupabaseAdmin`. `main.py` 에 이미 등록돼 있다. 여기에 엔드포인트를 더하면 **`main.py` 를 안 건드린다.** |
| 불러오기 · 실패 모양 | 화면 15 와 같다(가운데 로딩 / "잠시 뒤 다시 시도해 주세요" + "다시 시도", 사용자 결정 2026-09-27). |

## API 계약

**PR 1:** 없음(서버 변경 0).

**PR 2:** `GET /account` — `get_verified_caller`(학생증 · 학과 관문, 정지 403, 탈퇴 401).

```json
200
{
  "real_name": "홍길동",          // string | null — profile_private 행이 없으면 null
  "birth_year": 2003,             // int | null — 04-1 전이면 null
  "university": "서울대학교",
  "joined_at": "2026-09-01T10:00:00+00:00",   // profiles.created_at
  "kakao_id": "fox_rain"          // string | null
}
```

- 이메일은 싣지 않는다. 앱이 자기 세션에서 읽는다(서버가 auth admin 을 한 번 더 부를 이유가 없다).
- 학생 인증 상태는 싣지 않는다(위 조사 — 늘 인증 완료).
- **실명은 이 응답에만, 본인에게만 싣는다. 로그에 찍지 않는다**(pytest 로 `caplog` 에 없음을 박는다).
- `GET /account/kakao-id` 는 그대로 둔다(16e-1 이 쓴다).

## DB 변경

**없음.** 마이그레이션 · pgTAP · 클라우드 적용 없음. 필요한 칸(`birth_year` · `created_at` · `university_id` · `real_name` · `kakao_id`)이 전부 있다.

## 화면 대조표 (값표 B5 · B6 · B7, 2026-09-27)

| 화면 | pen 노드 | 값 | 코드 자리 |
| --- | --- | --- | --- |
| 16 설정 — 로그아웃 줄 | `lMDpY` › `ErFPL` | "지원" 카드 마지막 줄, log-out, 셰브런, 구분선 투명 → 16g | `settings_screen.dart` (PR 1) |
| 16 설정 — 계정 줄 | `lMDpY` › `eCrlw` | "계정·정보" 카드 첫 줄(y452), user-round, 셰브런 → 16e | `settings_screen.dart` (PR 2) |
| 16 설정 전체 모양 | `K4uiNp` 행 · 4섹션 카드 | **범위 밖**(대장) — 지금 ListTile 모양 유지 | — |
| 16g 로그아웃 확인 | `ZkOEb`(사본 `NRNqc`) | 제목 `Oc6gt` "로그아웃할까요?" 20/700 렌더 29 · 설명 `jyLej` "다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요." 16/400 #3F3F3F lh1.5 · 여백 4(`auevh`) · 확인 `D3eTj` 320x52 #FF385C r8 "로그아웃" 18/700 흰 · 취소 `VuRqd` #F2F2F2 "취소" · gap 16 · padding [12,20,28,20] · r[24,24,0,0] · 손잡이 36x4 #DDDDDD | `showSafetyConfirmSheet` 재사용 (PR 1) |
| 16e 앱바 | `dQNBh` | 56, 뒤로 48, "계정" 20/700 lh1.5 | `account_screen.dart` |
| 16e 목록 | `n8lZI` | vertical, gap 20, padding [12,16,24,16] | 〃 |
| 16e 섹션 머리 | `GsxGU` · `CwENo` · `w3rNYT` · `tbywV` | 14/700 #6A6A6A(렌더 20), 카드와 사이 8. 순서: 로그인 정보 / 본인 확인 정보 / 연락처 공개 정보 / 가입 정보 | 〃 |
| 16e 카드 | `DRNO6` · `WWHip` · `htOK0` · `CNJKy` | #F7F7F7, r12, 테두리 #DDDDDD 1, clip | 〃 |
| 16e 정보 줄 공통 | — | 높이 52(최소), padding [0,14], gap 12, 아래 선 #EBEBEB(마지막 줄 포함). 아이콘 20 #3F3F3F. 라벨 16/400 #222222(렌더 23). 값 14/400 #6A6A6A | 〃 |
| 16e 줄 | `O2NkV` · `CXXpN` · `z2KXC` · `EYBxA` · `zKvHu` · `nntyt` | 학교 이메일(mail) / 학생 인증(badge-check, 값 "인증 완료" 14/700 #C4224B) / 실명(user-round) / 출생연도(calendar) / 학교(graduation-cap) / 가입일(calendar-check, "2026.09.01") | 〃 |
| 16e 실명 라벨 | `AS3kP` | "실명" — "(비공개)" 안 붙임(대장 결정) | 〃 |
| 16e 안내문 | `o1G2A` / `FLwiN` | padding 14, #FFF0F2, r12. DESIGN 확정 문구 14/400 #3F3F3F lh1.5 | 〃 |
| 16e 카톡 줄 | `irepB`(사본 `hvZ7F`) › `B78nh` · `ow0m3` | message-circle, "카카오톡 아이디", 값, 셰브런 18 **#6A6A6A**(pen #929292 → 대장 결정, 대비). 이 줄만 셰브런 → 16e-1 `bWrnD` | 〃 |
| 16e-1 카톡 변경 | `bWrnD` | 안전담당 A6 몫 — 경로 `AppRoutes.kakaoIdSettings` 연결만 | — |
| pen 에 없는 상태 | — | 16e 불러오는 중 · 실패 → 화면 15 모양. 16g 진행 중 · 실패 → 없음(시트가 먼저 닫히고 로그아웃은 실패해도 기기에서 끝난다, Task 1) | — |

PR 2 에서 확인할 것: `AppIcons` 에 `calendarCheck` 가 없다(`app_icons.dart` 에 한 줄 — 공유 파일이라 PR 2 시작 때 대장에게 묻는다). 날짜는 `2026.09.01` — 한국 시각 기준(`joinedAt.toUtc().add(9h)`).

## 결정 대기

**대장(기술) — 사용자에게 묻지 않고 대장이 정해 주면 된다:**

- **T1. 로그아웃하면 앱 기억을 통째로 버린다 (추천)** — 새 위젯 `SessionScope` 가 `signedOut` 을 들으면 `ProviderScope` 에 새 key 를 줘 전부 새로 만든다. `main.dart` 의 `runApp` 한 줄이 바뀐다. 다른 길은 provider 를 하나씩 비우는 목록인데, 새 provider 가 생길 때마다 빠뜨리기 쉽다. 곁효과: 로그아웃 직후 스플래시가 2초 보인다(`SplashHold` 임시 장치, 로고 작업 때 같이 사라짐). 세션 만료로 튕길 때도 같이 비워진다.
- **T2. 16e 는 서버 `GET /account` 하나로 (추천)** — 다른 길은 앱이 `profiles` · `profile_private.real_name` 을 Supabase 에서 직접 읽고 카톡만 서버에서 받는 것이다. ERD 의 실명 컬럼 grant 가 원래 이 용도였다. 서버를 추천하는 이유: 앱의 저장소 20여 개가 전부 FastAPI 라 같은 틀로 테스트한다(MockClient). 요청이 셋에서 하나로 준다. 앞으로 16e 에 `profile_private` 칸(앱에 닫힌 칸)이 더 붙어도 같은 자리에서 받는다. 대가: 배포 1회. 그리고 ERD §2 표의 "16e 본인 실명 조회" 비고가 grant 대신 서버를 가리키게 된다 → 문서담당 몫으로 남긴다.
- **T3. 카톡 줄 이동 순서** — 16e 가 먼저 merge 되면 카톡 줄은 **셰브런 없이, 누를 수 없게** 둔다. 안전담당 A6 가 16e-1 route 를 만들 때 이 줄의 `onTap` 한 줄을 잇는다. A6 가 먼저면 Task 7 에서 내가 잇는다. 어느 쪽이든 16e-1 에서 저장하고 돌아오면 16e 가 다시 읽는다. **안전담당과 합의(2026-09-27):** 16e-1 경로 상수는 `AppRoutes.kakaoIdSettings = '/settings/account/kakao-id'` 이고 flat GoRoute 다(16e 안에 중첩하지 않는다). 먼저 들어가도 빈 화면은 만들지 않는다. 설정 줄은 모두 `for (final row in [...])` 안에 넣고, 충돌은 나중 PR 이 rebase 로 푼다. `signOutProvider` 는 안전담당의 정지 안내 화면 · 탈퇴 뒤 로그아웃에서도 쓴다.

**사용자(쉬운 말, 대장 경유, 하나씩) — pen 값표를 본 뒤 필요한 것만:**

- **U1 · U2 풀림(2026-09-27)** — 16g 문구는 pen `ZkOEb` 에 있고, 16e 가입일은 `2026.09.01` 형식이다(값표 B6 · B7). 사용자에게 물을 것 없음.

## 공유 파일 (손대기 전에 대장에게 한 줄씩 묻는다)

| 파일 | PR | 바뀌는 것 | 겹치는 사람 |
| --- | --- | --- | --- |
| `frontend/lib/main.dart` | 1 | `runApp(const ProviderScope(...))` → `runApp(SessionScope(...))` 한 줄 + import | 모두 |
| `frontend/lib/matching/view/settings_screen.dart` | 1 · 2 | PR 1 "로그아웃" 줄 + 시트 띄우기 / PR 2 "계정" 줄 | 안전담당 A4(탈퇴 줄) |
| `frontend/lib/core/auth/sign_out.dart` | 1 | 예외 삼키기 + `signOutProvider` | — (부르는 곳 0) |
| `frontend/lib/core/router/app_routes.dart` | 2 | `account = '/settings/account'` 한 줄 | 안전담당 A6(16e-1 경로) |
| `frontend/lib/core/router/app_router.dart` | 2 | `GoRoute(AppRoutes.account)` 한 줄 | 안전담당 A6 |
| `backend/app/account/router.py` · `repository.py` | 2 | `GET /account` + 조회 두 개 | 안전담당(#139 주인) |
| `backend/tests/account/account_world.py` | 2 | 가짜에 출생연도 · 가입일 · 실명 칸 | 안전담당 |

`main.py` · `errors.py` · `common/*` 는 건드리지 않는다.

## Global Constraints

- 색 · 글자 · 간격 · 모서리는 `lib/core/theme/` 토큰만. 아이콘은 `AppIcons`(Lucide). `Color(0xFF…)` 리터럴 금지.
- 사용자는 닉네임으로만 보인다. **실명은 16e 본인 조회에만** 쓰고, 서버 로그 · 앱 로그 · 예외 메시지에 싣지 않는다.
- 새 의존성 금지(`pubspec.yaml` · `requirements` 변경 0).
- 눌림 효과는 누르는 줄 안의 Material 에 그린다(COMMON §4-2). 설정 목록은 이미 한 곳에서 감싼다 — 새 줄을 그 목록 안에 넣는다.
- 높이는 `minHeight` 로만 건다. 글자 2.0 배에서도 넘침 0(DESIGN §11.2).
- 시트 딤은 `AppColors.scrim`(기본 0.8 아님).
- 문자열 · 경로는 `AppRoutes` 상수와 화면 파일 안 상수로만.
- 서버 pytest 는 루트 `.venv` 파이썬으로 돈다(bare python 3.14 는 pytest 가 없다).
- `dart format` 을 돌리지 않는다. 같은 폴더에서 `flutter test` 를 동시에 여럿 띄우지 않는다(`build/unit_test_assets` 가 깨진다).
- 커밋 · PR 에 도구 표식(Co-Authored-By · Generated with) 금지. 커밋은 git 담당이 의미 단위로 나눈다.

## Review Focus

1. **비행기 모드에서 로그아웃** — 기기 세션은 이미 지워졌는데 서버 알림이 `AuthRetryableFetchException` 으로 던진다. 사람은 에러 없이 로그인 화면으로 가야 한다. → Task 1 테스트.
2. **로그아웃 뒤 다른 계정으로 로그인** — 앞 사람의 내 프로필 · 카드 · 대화 목록이 남아 보이면 안 된다. → Task 2 테스트(`signedOut` 에 provider 가 새로 만들어진다, 토큰 갱신 · 로그인에는 그대로).
3. **확인 시트를 그냥 닫기** — 바깥 누르기 · 아래로 쓸기 · "취소" 는 로그아웃을 부르지 않는다. "로그아웃" 을 빠르게 두 번 눌러도 한 번만 부른다. → Task 3 테스트.
4. **16e 값이 빈 사람** — 실명 · 출생연도 · 카톡 아이디가 null 이어도 화면이 깨지지 않고 빈 값 모양을 그린다. 서버는 `profile_private` 행이 없어도 500 이 아니다. → Task 4 · Task 6 테스트.
5. **16e 를 못 불러올 때 · 글자를 키웠을 때** — 오프라인 · 502 는 "잠시 뒤 다시 시도해 주세요" + 다시 시도. 글자 2.0 배에서 줄이 잘리거나 넘치지 않는다. 실명이 서버 로그에 찍히지 않는다. → Task 4 · Task 6 테스트.

---

## PR 나누기

| PR | 브랜치 · 워크트리 | Task | 서버 | 배포 |
| --- | --- | --- | --- | --- |
| 1 로그아웃 | `feat/settings-logout` · `../campus_mate_compose-logout` | 1 · 2 · 3 | 없음 | 앱만 |
| 2 계정 화면 | `feat/account-screen` · `../campus_mate_compose-account` (origin/main 에서, PR 1 merge 뒤 또는 병렬 후 rebase) | 4 · 5 · 6 (· 7) | `GET /account` | Cloud Run 1회(대장) |

PR 1 과 PR 2 가 같은 `settings_screen.dart` 의 다른 줄을 고친다. 병렬로 가면 나중 PR 을 rebase 할 때 한 줄 충돌이 난다(git 담당이 푼다).

---

## PR 1 — 로그아웃

### Task 1: 로그아웃이 네트워크 오류로 던지지 않게 · 부를 자리 만들기

**Files:**
- Modify: `frontend/lib/core/auth/sign_out.dart`
- Test: `frontend/test/core/auth/sign_out_test.dart`

**Interfaces:**
- Consumes: `PushRegistrar.stop()`, `pushRegistrarProvider`(`core/push/push_provider.dart`), `GoTrueClient.signOut()`
- Produces: `final signOutProvider = Provider<Future<void> Function()>` — Task 3 의 시트 확인 버튼이 `ref.read(signOutProvider)()` 로 부른다. 테스트는 `signOutProvider.overrideWithValue(() async {...})` 로 덮는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `sign_out_test.dart` 의 `main()` 안, 기존 테스트 아래에 더한다.

```dart
  test('서버에 알리는 것이 네트워크 오류로 끝나도 던지지 않는다', () async {
    // gotrue 는 이 기기의 세션을 먼저 지우고 나서 서버에 알린다 — 그 알림이 실패해도 이미 로그아웃이다.
    // 던지면 시트를 닫은 뒤의 비동기 오류가 되어 화면이 아무것도 모른 채 로그만 남는다.
    final registrar = PushRegistrar(FakePushMessaging(token: 'tok-1'), FakeCardRepository());
    final auth = MockGoTrueClient();
    when(() => auth.signOut()).thenThrow(AuthRetryableFetchException(message: 'offline'));

    await expectLater(signOut(registrar, auth), completes);
  });
```

- [ ] **Step 2: 실패를 본다**

Run: `cd frontend && flutter test test/core/auth/sign_out_test.dart`
Expected: 새 테스트 FAIL — `AuthRetryableFetchException` 이 올라온다. 기존 테스트는 PASS.

- [ ] **Step 3: 최소 구현**

`sign_out.dart` 전체:

```dart
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/core/push/push_registrar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그아웃은 반드시 여기를 지난다.
///
/// `signOut()` 을 먼저 부르면 세션이 사라진 뒤에야 [PushRegistrar.stop] 이 불린다.
/// 그 안의 `DELETE /cards/push-tokens/{token}` 은 실어 보낼 토큰이 없어 401 로 끝나고,
/// 이 기기의 FCM 토큰은 서버에 그대로 남는다 — 다음으로 로그인한 사람이 덮어쓸 때까지
/// 죽은 토큰이 쌓인다. 그래서 지우고 나서 나간다.
///
/// `auth.signOut()` 은 이 기기의 세션을 먼저 지우고 나서 서버에 알린다(gotrue 2.27 `_signOut`).
/// 서버 알림이 네트워크 오류로 던져도 이 기기는 이미 로그아웃이고 토큰도 버렸다 — 화면까지 올리지 않는다.
Future<void> signOut(PushRegistrar registrar, GoTrueClient auth) async {
  await registrar.stop();
  try {
    await auth.signOut();
  } on AuthException {
    // 위 주석 — 남은 것은 서버 쪽 알림뿐이다.
  }
}

/// 설정 16g 가 부르는 로그아웃. 테스트는 덮어써 Supabase 를 켜지 않는다.
/// registrar 는 main.dart 가 [PushRegistrar.start] 한 그 인스턴스여야 등록한 토큰을 지운다 — 같은 provider 에서 읽는다.
final signOutProvider = Provider<Future<void> Function()>((ref) {
  final registrar = ref.read(pushRegistrarProvider);
  return () => signOut(registrar, Supabase.instance.client.auth);
});
```

- [ ] **Step 4: 통과를 본다**

Run: `cd frontend && flutter test test/core/auth/sign_out_test.dart`
Expected: 2 PASS.

### Task 2: 로그아웃하면 앱 기억을 통째로 버린다 (결정 T1)

**Files:**
- Create: `frontend/lib/core/auth/session_scope.dart`
- Modify: `frontend/lib/main.dart:31` (`runApp` 한 줄 + import 한 줄) — **대장 허락 뒤**
- Test: `frontend/test/core/auth/session_scope_test.dart`

**Interfaces:**
- Consumes: `Stream<AuthState>`(`GoTrueClient.onAuthStateChange` — gotrue 의 `ReplaySubject` 라 늦게 구독해도 지난 이벤트가 다시 온다)
- Produces: `class SessionScope extends StatefulWidget { SessionScope({required Stream<AuthState> authChanges, required Widget child}) }` — 안에서 `ProviderScope` 를 만든다. main.dart 만 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
import 'dart:async';

import 'package:campus_mate/core/auth/session_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late StreamController<AuthState> authChanges;
  late int builds;
  late Provider<int> probe;

  setUp(() {
    authChanges = StreamController<AuthState>();
    builds = 0;
    // 한 컨테이너 안에서는 한 번만 만들어진다 — 숫자가 오르면 컨테이너가 새것이다.
    probe = Provider<int>((ref) => ++builds);
  });
  tearDown(() => authChanges.close());

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(SessionScope(
      authChanges: authChanges.stream,
      child: Consumer(
        builder: (context, ref, _) => Text('${ref.watch(probe)}', textDirection: TextDirection.ltr),
      ),
    ));
  }

  testWidgets('로그아웃 뒤 다른 계정으로 들어오면 앞 사람 값이 아니라 새 사람 값이 보인다', (tester) async {
    // 회귀: provider 가 autoDispose 가 아니라 앞 사람의 내 프로필 · 카드가 그대로 보이던 자리다.
    var currentUser = 'A';
    final profile = FutureProvider<String>((ref) async => '$currentUser 의 프로필');
    await tester.pumpWidget(SessionScope(
      authChanges: authChanges.stream,
      child: Consumer(
        builder: (context, ref, _) =>
            Text(ref.watch(profile).value ?? '', textDirection: TextDirection.ltr),
      ),
    ));
    await tester.pump();
    expect(find.text('A 의 프로필'), findsOneWidget);

    authChanges.add(const AuthState(AuthChangeEvent.signedOut, null));
    currentUser = 'B';
    authChanges.add(const AuthState(AuthChangeEvent.signedIn, null));
    await tester.pump();
    await tester.pump();

    expect(find.text('A 의 프로필'), findsNothing);
    expect(find.text('B 의 프로필'), findsOneWidget);
  });

  testWidgets('로그아웃하면 provider 가 기억하던 값을 버리고 새로 만든다', (tester) async {
    await pump(tester);
    expect(find.text('1'), findsOneWidget);

    authChanges.add(const AuthState(AuthChangeEvent.signedOut, null));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('토큰 갱신 · 로그인에는 그대로 둔다', (tester) async {
    // 로그인 중(인증코드 확인)인 ViewModel 을 중간에 버리면 안 된다.
    await pump(tester);

    authChanges
      ..add(const AuthState(AuthChangeEvent.tokenRefreshed, null))
      ..add(const AuthState(AuthChangeEvent.signedIn, null));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('인증 스트림 오류에 넘어지지 않는다', (tester) async {
    // gotrue 는 세션 복구 실패 같은 것을 스트림 오류로도 보낸다 — onError 가 없으면 잡히지 않은 오류가 된다.
    await pump(tester);

    authChanges.addError(AuthException('refresh failed'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 실패를 본다**

Run: `cd frontend && flutter test test/core/auth/session_scope_test.dart`
Expected: 컴파일 실패 — `session_scope.dart` 없음.

- [ ] **Step 3: 최소 구현** — `session_scope.dart`

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그아웃하면 앱이 들고 있던 기억(provider 상태)을 통째로 버린다.
///
/// provider 는 채팅방 하나 빼고 autoDispose 가 아니라 화면을 떠나도 값이 남는다 — 같은 폰에서
/// 다른 계정으로 들어오면 앞 사람의 내 프로필 · 카드 · 대화 목록이 그대로 보인다.
/// 비울 provider 목록을 두면 새 provider 가 생길 때마다 빠뜨리기 쉬워 [ProviderScope] 를 새로 만든다.
/// 로그아웃 버튼(16g)뿐 아니라 세션 만료로 튕길 때도 같이 비워진다.
class SessionScope extends StatefulWidget {
  const SessionScope({required this.authChanges, required this.child, super.key});

  final Stream<AuthState> authChanges;
  final Widget child;

  @override
  State<SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends State<SessionScope> {
  late final StreamSubscription<AuthState> _subscription;

  /// 로그아웃할 때마다 하나 오른다. [ProviderScope] 의 key 라 바뀌면 아래가 전부 새로 만들어진다.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.authChanges.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          setState(() => _generation++);
        }
      },
      // 세션 복구 실패 같은 오류도 이 스트림으로 온다 — 이동 판단은 AuthSessionListenable 이 한다.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(key: ValueKey(_generation), child: widget.child);
  }
}
```

- [ ] **Step 4: 통과를 본다**

Run: `cd frontend && flutter test test/core/auth/session_scope_test.dart`
Expected: 4 PASS.

- [ ] **Step 5: main.dart 한 줄 (대장 허락 2026-09-27)**

```dart
// import 에 더한다
import 'package:campus_mate/core/auth/session_scope.dart';

// main() 안
  runApp(SessionScope(
    authChanges: Supabase.instance.client.auth.onAuthStateChange,
    child: const CampusMateApp(),
  ));
```

`ProviderScope` import(`flutter_riverpod`)는 `CampusMateApp` 이 계속 쓰므로 남긴다. `flutter analyze` 로 안 쓰는 import 경고가 없는지 본다.

- [ ] **Step 6: 전체 확인**

Run: `cd frontend && flutter analyze && flutter test`
Expected: analyze 문제 0. test 는 기준선 + 새 테스트 전부 PASS(기준선 숫자는 시작 전에 origin/main 에서 한 번 세어 적는다).

### Task 3: 설정 "로그아웃" 줄과 16g 확인 시트

**Files:**
- Modify: `frontend/lib/matching/view/settings_screen.dart` (대장 허락 2026-09-27 — 로그아웃 줄만)
- Test: `frontend/test/matching/view/settings_screen_test.dart`

**Interfaces:**
- Consumes: `signOutProvider`(Task 1). **16g 시트는 새로 만들지 않는다** — pen `ZkOEb` 값(제목 20/700 렌더 29 · 설명 16/400 #3F3F3F lh1.5 · 사이 36 · 52 버튼 r8 · 주색 확인 + #F2F2F2 취소 · 여백 [12,20,28,20] · 위 모서리 24)이 `SafetyConfirmSheet`(`safety/view/safety_sheet.dart`, pen `aCTy1`)와 같다. `showSafetyConfirmSheet(context, title:, description:, confirmLabel:) -> Future<bool>` 를 그대로 부른다(안전담당 파일, 고치지 않는다).
- Produces: 없음(설정 줄 하나).

pen 값(값표 B5 · B7):
- 줄: `ErFPL` — 16 "지원" 카드 마지막 줄, log-out 아이콘, 셰브런, 구분선 투명 → 16g. **16e 안이 아니다.**
- 시트: `ZkOEb`(사본 `NRNqc`) — 제목 `Oc6gt` "로그아웃할까요?", 설명 `jyLej` "다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.", 확인 `D3eTj` "로그아웃"(#FF385C, 위험색 아님), 취소 `VuRqd` "취소".
- 줄 모양: 설정 화면 전체(보유 하트 · 4섹션 · 카드 · 52 행 `K4uiNp`)를 맞추는 일은 **이번 범위 밖**(대장 2026-09-27). 한 목록 안에서 한 줄만 K4uiNp 로 바꾸면 모양이 섞이므로, 지금 줄들과 같은 `ListTile`(아이콘 muted · subtitle · 셰브런)로 넣는다.
- 자리: 지금 목록(매칭 활성화 · 알림 · 차단 목록) 끝, 오류 줄 `if` 앞. 안전담당 PR 6 이 차단 목록과 로그아웃 사이에 "연락처 차단", 로그아웃 뒤에 "탈퇴하기" 를 넣는다(합의 — 충돌은 나중 PR 이 rebase).

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `settings_screen_test.dart`.

`main()` 맨 위에 `var signOutCalls = 0;`, `pump` 첫 줄에 `signOutCalls = 0;`, `ProviderContainer(overrides: [...])` 에 `signOutProvider.overrideWithValue(() async => signOutCalls++),` 를 더한다. import 에 `package:campus_mate/core/auth/sign_out.dart` · `package:campus_mate/safety/view/safety_sheet.dart`.

```dart
  // 줄 제목과 시트 확인 버튼 글자가 둘 다 "로그아웃" 이다 — 시트 안으로 좁혀 찾는다.
  Finder inSheet(String text) =>
      find.descendant(of: find.byType(SafetyConfirmSheet), matching: find.text(text));

  Future<void> openLogoutSheet(WidgetTester tester) async {
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
  }

  testWidgets('"로그아웃" 줄은 차단 목록 아래, log-out 아이콘과 셰브런이다(pen lMDpY ErFPL)', (tester) async {
    await pump(tester);

    expect(tile('로그아웃'), findsOneWidget);
    expect(tester.getRect(tile('로그아웃')).top, tester.getRect(tile('차단 목록')).bottom);
    expect(find.descendant(of: tile('로그아웃'), matching: find.byIcon(AppIcons.logOut)), findsOneWidget);
    expect(find.descendant(of: tile('로그아웃'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"로그아웃" 을 누르면 16g 문구가 보인다(pen ZkOEb)', (tester) async {
    await pump(tester);
    await openLogoutSheet(tester);

    expect(inSheet('로그아웃할까요?'), findsOneWidget);
    expect(inSheet('다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.'), findsOneWidget);
    expect(inSheet('로그아웃'), findsOneWidget);
    expect(inSheet('취소'), findsOneWidget);
  });

  testWidgets('확인하면 시트가 닫히고 로그아웃을 한 번 부른다 — 빠르게 두 번 눌러도 한 번', (tester) async {
    await pump(tester);
    await openLogoutSheet(tester);

    await tester.tap(inSheet('로그아웃'));
    await tester.pump();
    // 닫히는 중인 시트를 한 번 더 누른다 — 두 번째 pop 이 설정 화면까지 닫으면 안 된다.
    await tester.tap(inSheet('로그아웃'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(signOutCalls, 1);
    expect(find.byType(SafetyConfirmSheet), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('취소 · 바깥 누르기는 로그아웃을 부르지 않는다', (tester) async {
    await pump(tester);

    await openLogoutSheet(tester);
    await tester.tap(inSheet('취소'));
    await tester.pumpAndSettle();
    await openLogoutSheet(tester);
    await tester.tapAt(const Offset(10, 10)); // 딤
    await tester.pumpAndSettle();

    expect(signOutCalls, 0);
    expect(find.byType(SafetyConfirmSheet), findsNothing);
  });
```

- [ ] **Step 2: 실패를 본다**

Run: `cd frontend && flutter test test/matching/view/settings_screen_test.dart`
Expected: 새 4개 FAIL("로그아웃" 줄 없음). 기존 4개 PASS.

- [ ] **Step 3: 줄을 단다** — `settings_screen.dart` 의 `for (final row in [...])` 목록, "차단 목록" `ListTile` 다음 · `if (state.errorMessage != null)` 앞:

```dart
              ListTile(
                leading: const Icon(AppIcons.logOut, color: AppColors.muted),
                title: Text('로그아웃', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => _confirmSignOut(context, ref),
              ),
```

클래스 안에 더한다:

```dart
  /// 16g(pen `ZkOEb`). 틀이 안전 확인 시트(`aCTy1`)와 같아 그대로 쓴다. 확인하면 시트가 먼저 닫히고,
  /// 로그아웃이 끝나면 라우터가 로그인 화면으로 보낸다 — 여기서 이동하지 않는다.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final signOut = ref.read(signOutProvider);
    final confirmed = await showSafetyConfirmSheet(
      context,
      title: '로그아웃할까요?',
      description: '다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.',
      confirmLabel: '로그아웃',
    );
    if (confirmed) {
      await signOut();
    }
  }
```

`signOut` 을 시트 전에 읽는 이유: 시트가 떠 있는 동안 화면이 사라져도(`ref` 무효) 확인 뒤에 부를 수 있게.

- [ ] **Step 4: 통과와 전체를 본다**

Run: `cd frontend && flutter test test/matching/view/settings_screen_test.dart && flutter analyze && flutter test`
Expected: 설정 테스트 8개 PASS(기존 잉크 테스트가 새 줄까지 훑는다). analyze 0, 전체 PASS.

두 번 누르기 테스트가 빨개지면(두 번째 pop 이 설정 화면을 닫음) systematic-debugging 으로 원인을 확인한 뒤 `_confirmSignOut` 이 아니라 시트 쪽 문제인지부터 가른다 — 시트는 안전담당 파일이라 고치기 전에 대장에게 묻는다.

- [ ] **Step 5: 검토 · PR** — fresh campus-reviewer(pen 값 B5 · B7 대조 포함) PASS → campus-git draft PR(`feat/settings-logout`). git 담당 요청문에 "ready 는 대장이 올린다, 되돌리지 마". 커밋: ① `sign_out` 예외 + `signOutProvider` ② `SessionScope` + main.dart ③ 설정 로그아웃 줄 — 테스트는 각 커밋에 같이. 계획서는 ①과 같이 또는 따로 `📝 docs(plan)`.

---

## PR 2 — 16e 계정 화면

### Task 4: 서버 `GET /account`

**Files:**
- Modify: `backend/app/account/router.py`, `backend/app/account/repository.py` — **대장 허락 뒤(안전담당 모듈)**
- Modify: `backend/tests/account/account_world.py` — **대장 허락 뒤**
- Test: `backend/tests/account/test_account_info.py`

**Interfaces:**
- Consumes: `get_verified_caller`(`app/core/deps.py`), `PostgrestRepository._get`, `raise_for_status`
- Produces: `GET /account` → `{"real_name", "birth_year", "university", "joined_at", "kakao_id"}`(위 API 계약). `AccountRepository.fetch_account(profile_id) -> dict`, `AccountRepository.fetch_private(profile_id) -> dict`.

- [ ] **Step 1: 가짜 세상에 칸을 더한다** — `account_world.py`

```python
# AccountWorld.__init__ 의 ME 행에 칸을 더한다
        self.profiles: dict[str, dict] = {
            ME: {"status": "active", "withdrawn_at": None, "student_verification": "verified", "department": "컴공",
                 "birth_year": 2003, "created_at": "2026-09-01T10:00:00+00:00", "university": "서울대학교"},
        }
        self.real_names: dict[str, str] = {}

# _profiles: 관문 분기 앞에 16e 분기를 둔다
        if "created_at" in params["select"]:
            return httpx.Response(200, json=[{"birth_year": row["birth_year"], "created_at": row["created_at"],
                                              "universities": {"name": row["university"]}}])

# _profile_private: 고른 칸만 돌려준다. 둘 다 없으면 행이 없는 것이다(기존 kakao 테스트와 같다)
    def _profile_private(self, method, params, body):
        owner = self._eq(params, "profile_id")
        row = {"kakao_id": self.kakao_ids.get(owner), "real_name": self.real_names.get(owner)}
        if not any(row.values()):
            return httpx.Response(200, json=[])
        return httpx.Response(200, json=[{column: row[column] for column in params["select"].split(",")}])
```

- [ ] **Step 2: 실패하는 테스트를 쓴다** — `test_account_info.py`

```python
"""`GET /account`(16e 계정 화면). 실명은 본인에게 가는 이 응답에만 있고 로그에는 없다."""
import logging

from account_world import AUTH, ME


def test_my_account_rows_come_back(client, world):
    world.real_names[ME] = "홍길동"
    world.kakao_ids[ME] = "fox_rain"

    response = client.get("/account", headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {
        "real_name": "홍길동", "birth_year": 2003, "university": "서울대학교",
        "joined_at": "2026-09-01T10:00:00+00:00", "kakao_id": "fox_rain",
    }


def test_missing_private_row_is_null_not_500(client, world):
    body = client.get("/account", headers=AUTH).json()

    assert body["real_name"] is None
    assert body["kakao_id"] is None


def test_unverified_caller_is_403(client, world):
    world.profiles[ME]["student_verification"] = "pending"

    assert client.get("/account", headers=AUTH).status_code == 403


def test_real_name_never_reaches_logs(client, world, caplog):
    world.real_names[ME] = "홍길동"

    with caplog.at_level(logging.DEBUG):
        client.get("/account", headers=AUTH)

    assert "홍길동" not in caplog.text
```

- [ ] **Step 3: 실패를 본다**

Run: `cd backend && ../.venv/Scripts/python -m pytest tests/account/test_account_info.py -v`
Expected: 앞 둘 · 로그 테스트 FAIL(404), 403 테스트는 404 라 FAIL.

- [ ] **Step 4: 최소 구현**

`repository.py` — 모듈 docstring 첫 줄을 "탈퇴 · 정리 배치 · 16e 계정 화면이 부르는 …" 로 고치고, `AccountRepository` 에 더한다:

```python
    # 16e 계정 화면 ------------------------------------------------------------
    async def fetch_account(self, profile_id: UUID | str) -> dict:
        response = await self._get("profiles", params={
            "id": f"eq.{profile_id}", "select": "birth_year,created_at,universities(name)",
        })
        raise_for_status(response)
        return response.json()[0]

    async def fetch_private(self, profile_id: UUID | str) -> dict:
        """실명 · 카톡 아이디. 관문을 지났으면 행이 늘 있지만(3b 에서 만든다), 없다고 500 을 내지 않는다."""
        response = await self._get("profile_private", params={
            "profile_id": f"eq.{profile_id}", "select": "real_name,kakao_id",
        })
        raise_for_status(response)
        rows = response.json()
        return rows[0] if rows else {}
```

`router.py` — 모듈 docstring 을 "계정: 탈퇴(B3) · 내 카카오톡 아이디(B5, 16e-1) · 계정 화면(16e)." 로 고치고 더한다:

```python
@router.get("/account")
async def get_my_account(caller: Caller = Depends(get_verified_caller)) -> dict:
    """16e 계정 화면. 실명은 본인에게 가는 이 응답에만 싣고 로그에 찍지 않는다(DESIGN §9 16e · ERD §11-2).
    이메일은 앱이 자기 세션에서 읽는다. 인증 상태는 싣지 않는다 — 관문을 지난 사람만 닿으니 늘 '인증 완료'다."""
    settings, client, profile_id = caller
    accounts = AccountRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    profile = await accounts.fetch_account(profile_id)
    private = await accounts.fetch_private(profile_id)
    return {
        "real_name": private.get("real_name"),
        "birth_year": profile["birth_year"],
        "university": profile["universities"]["name"],
        "joined_at": profile["created_at"],
        "kakao_id": private.get("kakao_id"),
    }
```

- [ ] **Step 5: 통과와 전체를 본다**

Run: `cd backend && ../.venv/Scripts/python -m pytest tests/account -v && ../.venv/Scripts/python -m pytest -q`
Expected: 새 4개 PASS, `test_kakao_id.py` 2개 그대로 PASS, 전체 기준선 + 4.

### Task 5: 앱 모델 · 저장소

**Files:**
- Create: `frontend/lib/account/model/account_info.dart`, `account_repository.dart`, `http_account_repository.dart`, `account_repository_provider.dart`
- Create: `frontend/lib/account/viewmodel/account_info_provider.dart`
- Test: `frontend/test/account/model/http_account_repository_test.dart`, `frontend/test/account/model/fake_account_repository.dart`

**Interfaces:**
- Consumes: `ApiClient.send`(`core/http/api_client.dart`), `apiClientProvider`, `GoTrueClient.currentUser`
- Produces:
  - `class AccountInfo { String email; String? realName; int? birthYear; String university; DateTime joinedAt; String? kakaoId; }` (const 생성자, 전부 required named)
  - `abstract interface class AccountRepository { Future<Result<AccountInfo>> fetchAccount(); }`
  - `final accountRepositoryProvider = Provider<AccountRepository>`
  - `final accountInfoProvider = FutureProvider.autoDispose<Result<AccountInfo>>` — autoDispose 라 화면을 떠나면 실명이 메모리에서 내려가고, 다시 들어오면 새로 읽는다.
  - 테스트용 `class FakeAccountRepository implements AccountRepository { FakeAccountRepository({Result<AccountInfo>? result}); int calls; }`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `http_account_repository_test.dart`(`test/me/model/http_me_repository_test.dart` 와 같은 틀)

```dart
import 'dart:convert';

import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/http_account_repository.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

void main() {
  late MockGoTrueClient auth;

  setUp(() {
    auth = MockGoTrueClient();
    final session = MockSession();
    final user = MockUser();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    when(() => user.email).thenReturn('hong@snu.ac.kr');
    when(() => auth.currentUser).thenReturn(user);
  });

  HttpAccountRepository build(http.Client client) =>
      HttpAccountRepository(ApiClient('https://api.test', client, auth), auth);

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  test('GET /account 값과 세션 이메일을 AccountInfo 로 읽는다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.test/account');
      return json({
        'real_name': '홍길동', 'birth_year': 2003, 'university': '서울대학교',
        'joined_at': '2026-09-01T10:00:00+00:00', 'kakao_id': 'fox_rain',
      });
    });

    final result = await build(client).fetchAccount();
    final info = result.when<AccountInfo?>(onSuccess: (i) => i, onFailure: (_) => null)!;

    expect(info.email, 'hong@snu.ac.kr');
    expect(info.realName, '홍길동');
    expect(info.birthYear, 2003);
    expect(info.university, '서울대학교');
    expect(info.joinedAt, DateTime.utc(2026, 9, 1, 10));
    expect(info.kakaoId, 'fox_rain');
  });

  test('빈 칸은 null 로 받는다', () async {
    final client = MockClient((_) async => json({
          'real_name': null, 'birth_year': null, 'university': '서울대학교',
          'joined_at': '2026-09-01T10:00:00+00:00', 'kakao_id': null,
        }));

    final info = (await build(client).fetchAccount()).when<AccountInfo?>(onSuccess: (i) => i, onFailure: (_) => null)!;

    expect(info.realName, isNull);
    expect(info.birthYear, isNull);
    expect(info.kakaoId, isNull);
  });

  test('502 는 Failure 로 돌려준다', () async {
    final client = MockClient((_) async => json({'detail': 'bad gateway'}, 502));

    final result = await build(client).fetchAccount();

    expect(result.when<Failure?>(onSuccess: (_) => null, onFailure: (f) => f), isA<ServerUnavailableFailure>());
  });
}
```

- [ ] **Step 2: 실패를 본다**

Run: `cd frontend && flutter test test/account/model/http_account_repository_test.dart`
Expected: 컴파일 실패 — `account/model/*` 없음.

- [ ] **Step 3: 최소 구현**

`account_info.dart`:

```dart
/// 16e 계정 화면이 그리는 값 한 벌. 이메일은 이 기기의 로그인 세션, 나머지는 서버 `GET /account`.
class AccountInfo {
  const AccountInfo({
    required this.email,
    required this.realName,
    required this.birthYear,
    required this.university,
    required this.joinedAt,
    required this.kakaoId,
  });

  final String email;

  /// 본인만 여기서 본다(CLAUDE.md §7). 학생증 제출 전이면 null.
  final String? realName;

  /// 04-1 전이면 null.
  final int? birthYear;
  final String university;
  final DateTime joinedAt;

  /// 04-1b 전이면 null.
  final String? kakaoId;
}
```

`account_repository.dart`:

```dart
import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/common/result.dart';

/// 16e 가 쓰는 서버 호출. 화면은 이 인터페이스만 보고 구현을 모른다.
abstract interface class AccountRepository {
  Future<Result<AccountInfo>> fetchAccount();
}
```

`http_account_repository.dart`:

```dart
import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AccountRepository] 를 FastAPI `GET /account` 로 구현한다. 이메일은 서버가 싣지 않아 세션에서 읽는다.
class HttpAccountRepository implements AccountRepository {
  const HttpAccountRepository(this._api, this._auth);

  final ApiClient _api;
  final GoTrueClient _auth;

  @override
  Future<Result<AccountInfo>> fetchAccount() => _api.send('GET', '/account', (body) {
        final json = body as Map<String, dynamic>;
        return AccountInfo(
          // 관문을 지난 세션이라 이메일은 늘 있다 — 없으면 빈 줄로 그린다.
          email: _auth.currentUser?.email ?? '',
          realName: json['real_name'] as String?,
          birthYear: json['birth_year'] as int?,
          university: json['university'] as String,
          joinedAt: DateTime.parse(json['joined_at'] as String),
          kakaoId: json['kakao_id'] as String?,
        );
      });
}
```

`account_repository_provider.dart`:

```dart
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/model/http_account_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 16e 가 쓰는 저장소. 테스트는 이 provider 를 가짜로 덮어쓴다.
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return HttpAccountRepository(ref.read(apiClientProvider), Supabase.instance.client.auth);
});
```

`account_info_provider.dart`:

```dart
import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16e 가 읽는 계정 정보. 실패도 [Result] 그대로 — 던지면 Riverpod 3 이 재시도 타이머를 건다(화면 15 와 같다).
/// autoDispose: 화면을 떠나면 실명이 메모리에서 내려가고, 16e-1 에서 돌아오면 새로 읽는다.
final accountInfoProvider = FutureProvider.autoDispose<Result<AccountInfo>>((ref) {
  return ref.watch(accountRepositoryProvider).fetchAccount();
});
```

`test/account/model/fake_account_repository.dart`:

```dart
import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/common/result.dart';

final sampleAccount = AccountInfo(
  email: 'hong@snu.ac.kr',
  realName: '홍길동',
  birthYear: 2003,
  university: '서울대학교',
  joinedAt: DateTime.utc(2026, 9, 1, 10),
  kakaoId: 'fox_rain',
);

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({Result<AccountInfo>? result}) : result = result ?? Success(sampleAccount);

  Result<AccountInfo> result;
  int calls = 0;

  @override
  Future<Result<AccountInfo>> fetchAccount() async {
    calls++;
    return result;
  }
}
```

- [ ] **Step 4: 통과를 본다**

Run: `cd frontend && flutter test test/account/model/http_account_repository_test.dart`
Expected: 3 PASS.

### Task 6: 16e 계정 화면 · 경로 · 설정 "계정" 줄

**Files:**
- Create: `frontend/lib/account/view/account_screen.dart`
- Modify: `frontend/lib/core/router/app_routes.dart`, `frontend/lib/core/router/app_router.dart`, `frontend/lib/matching/view/settings_screen.dart` — **각각 대장 허락 뒤**
- Test: `frontend/test/account/view/account_screen_test.dart`, `frontend/test/matching/view/settings_screen_test.dart`, `frontend/test/core/router/app_router_test.dart`

**Interfaces:**
- Consumes: `accountInfoProvider`, `FakeAccountRepository`(Task 5), 화면 15 의 로딩 · 실패 모양(`me/view/my_profile_screen.dart` `_LoadError` — private 이라 같은 모양을 이 화면에 둔다)
- Produces: `class AccountScreen extends ConsumerWidget`, `AppRoutes.account = '/settings/account'`

- [ ] **Step 1: 실패하는 테스트를 쓴다** — `account_screen_test.dart`

```dart
import 'package:campus_mate/account/model/account_repository_provider.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_account_repository.dart';

void main() {
  Future<FakeAccountRepository> pump(WidgetTester tester, {FakeAccountRepository? repository}) async {
    final fake = repository ?? FakeAccountRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [accountRepositoryProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: AccountScreen()),
    ));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('로그인 · 본인 확인 · 가입 · 연락처 값이 보인다', (tester) async {
    await pump(tester);

    expect(find.text('hong@snu.ac.kr'), findsOneWidget);
    expect(find.text('인증 완료'), findsOneWidget); // [pen] 인증 상태 글자
    expect(find.text('홍길동'), findsOneWidget);
    expect(find.text('2003'), findsOneWidget); // [pen] EYBxA 값 모양 — PR 2 시작 때 값표로 확인
    expect(find.text('서울대학교'), findsOneWidget);
    expect(find.text('2026.09.01'), findsOneWidget); // pen nntyt — 한국 시각 날짜
    expect(find.text('fox_rain'), findsOneWidget);
    expect(find.text(AccountScreen.privacyNote), findsOneWidget);
  });

  testWidgets('빈 값은 빈 모양으로 그린다', (tester) async {
    await pump(tester, repository: FakeAccountRepository(result: Success(AccountInfo(
      email: 'hong@snu.ac.kr', realName: null, birthYear: null, university: '서울대학교',
      joinedAt: DateTime.utc(2026, 9, 1, 10), kakaoId: null,
    ))));

    expect(tester.takeException(), isNull);
    expect(find.text(AccountScreen.emptyValue), findsNWidgets(3)); // [pen] 빈 값 글자
  });

  testWidgets('못 불러오면 다시 시도할 수 있다', (tester) async {
    final fake = await pump(tester, repository: FakeAccountRepository(result: const FailureResult(NetworkFailure())));
    expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);

    fake.result = Success(sampleAccount);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fake.calls, 2);
    expect(find.text('홍길동'), findsOneWidget);
  });

  testWidgets('글자 2배에서도 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('누를 수 있는 줄의 눌림 효과는 그 줄 안에서 그려진다', (tester) async {
    await pump(tester);

    for (final well in find.byType(InkWell).evaluate()) {
      final finder = find.byWidget(well.widget);
      final material = find.ancestor(of: finder, matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(finder));
    }
  });
}
```

(`import 'package:campus_mate/account/model/account_info.dart';` 를 더한다. 실패 결과 타입은 `FailureResult` 다.)

- [ ] **Step 2: 실패를 본다**

Run: `cd frontend && flutter test test/account/view/account_screen_test.dart`
Expected: 컴파일 실패 — `account_screen.dart` 없음.

- [ ] **Step 3: 화면 구현** — 틀만 여기 적는다. 구역 머리 · 줄 모양 · 간격 · 글자 토큰은 [pen] 값표 그대로. 줄은 전부 `minHeight`.

```dart
/// 16e 계정(pen [pen 노드 id]). 16 "계정" 에서 들어온다. 값은 보기만 하고, 카톡 줄만 16e-1 로 간다(T3).
/// 불러오는 중 · 실패는 pen 에 없어 화면 15 와 같은 모양을 쓴다(사용자 결정 2026-09-27).
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  /// DESIGN §9 16e 확정 문구.
  static const privacyNote = '실명과 출생연도는 학생증 대조와 운영 확인에만 쓰여요. 다른 사용자에게는 닉네임만 보여요.';
  static const emptyValue = '—'; // [pen]

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('계정', style: AppTypography.navTitle)),
      body: SafeArea(
        child: ref.watch(accountInfoProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _LoadError(onRetry: () => ref.invalidate(accountInfoProvider)),
              data: (result) => result.when(
                onSuccess: (info) => _AccountContent(info: info),
                onFailure: (_) => _LoadError(onRetry: () => ref.invalidate(accountInfoProvider)),
              ),
            ),
      ),
    );
  }
}
```

`_AccountContent` 는 `ListView` 안에 [pen] 구역 머리 4개 + 줄(라벨 · 값) + `privacyNote` 를 [pen] 자리에 둔다. 날짜는 `joinedAt.toUtc().add(const Duration(hours: 9))` 로 한국 날짜를 만든다(기기 시간대에 끌려가지 않게). 카톡 줄은 T3 대로 — 16e-1 route 가 아직 없으면 `onTap` 없이, 셰브런 없이. `_LoadError` 는 화면 15 의 것과 같은 모양(가운데 문구 + `AppButton.text` "다시 시도")을 private 으로 둔다.

- [ ] **Step 4: 통과를 본다**

Run: `cd frontend && flutter test test/account/view/account_screen_test.dart`
Expected: 5 PASS.

- [ ] **Step 5: 경로 · 설정 줄 테스트를 쓴다**

`settings_screen_test.dart` — `pump` 의 routes 에 `GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen())`, overrides 에 `accountRepositoryProvider.overrideWithValue(FakeAccountRepository())` 를 더한다.

```dart
  testWidgets('"계정" 줄은 [pen 위치], [pen 아이콘]이다(pen lMDpY [pen 노드 id])', (tester) async {
    await pump(tester);

    expect(tile('계정'), findsOneWidget);
    // [pen] 위아래 줄과 붙는지 · 아이콘 · 셰브런
  });

  testWidgets('"계정" 을 누르면 16e 가 열린다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('계정'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });
```

`app_router_test.dart` — 기존 경로 테스트 틀대로 `AppRoutes.account` 가 `AccountScreen` 을 여는지 한 줄.

- [ ] **Step 6: 실패를 본다**

Run: `cd frontend && flutter test test/matching/view/settings_screen_test.dart test/core/router/app_router_test.dart`
Expected: 새 테스트 FAIL — "계정" 줄 · 경로 없음.

- [ ] **Step 7: 경로 · 줄을 단다 (대장 허락 뒤)**

`app_routes.dart` — 조각 6 줄 아래:

```dart
  /// 16e 계정(설정 "계정" 줄에서 들어간다).
  static const String account = '/settings/account';
```

`app_router.dart` — `_slice4Routes` 의 `notificationSettings` 다음:

```dart
      GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen()),
```

`settings_screen.dart` — [pen] 자리:

```dart
              ListTile(
                leading: const Icon(AppIcons.userRound, color: AppColors.muted), // [pen] 아이콘
                title: Text('계정', style: AppTypography.subtitle.copyWith(color: AppColors.ink)),
                trailing: const Icon(AppIcons.chevronRight, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.account),
              ),
```

- [ ] **Step 8: 통과와 전체를 본다**

Run: `cd frontend && flutter analyze && flutter test`
Expected: analyze 0, 전체 PASS.

### Task 7: 카톡 줄 → 16e-1 (안전담당 A6 가 먼저 merge 됐을 때만)

**Files:**
- Modify: `frontend/lib/account/view/account_screen.dart`
- Test: `frontend/test/account/view/account_screen_test.dart`

- [x] **Step 1: 실패하는 테스트** — 카톡 줄을 누르면 A6 의 16e-1 화면이 열리고, 저장하고(`true`) 돌아오면 `FakeAccountRepository.accountFetches` 가 하나 오른다(다시 읽기). 저장하지 않고 돌아오면 오르지 않는다.
- [x] **Step 2: 실패를 본다.**
- [x] **Step 3: 구현** — 카톡 줄에 셰브런과 `onTap: () async { final saved = await context.push<bool>(AppRoutes.kakaoIdSettings); if (saved == true && context.mounted) ref.invalidate(accountInfoProvider); }`.
- [x] **Step 4: 통과를 본다.**

> **편차(2026-09-28, 대장 결정 — 검토 R2 권고 2):** 처음 적은 "돌아오면 늘 다시 읽기" 대신 **저장하고 돌아올 때만** 다시 읽는다. 16e-1 은 저장하면 `true` 를 들고 닫히고(`kakao_id_settings_screen.dart`), 채팅방 14f "변경" 도 같은 방식이다. 그냥 뒤로 와도 실명이 든 `GET /account` 를 다시 부르고, 그때 네트워크가 끊기면 멀쩡한 화면이 다시 시도 화면으로 바뀌던 것을 막는다. A6(#153)가 먼저 merge 돼 이 Task 는 PR 2 가 했다.

A6 가 나중이면 이 Task 는 A6 PR 이 한다(대장이 안전담당에게 이 절을 전한다).

- [ ] **PR 2 마무리** — fresh campus-reviewer(pen 값 대조 · 실명 로그 · 글자 2배 포함) PASS → campus-git draft PR(`feat/account-screen`). 커밋: ① 서버 `GET /account` + 테스트 ② 앱 모델 · 저장소 + 테스트 ③ 16e 화면 · 경로 · 설정 줄 + 테스트. 배포는 대장(서버가 먼저 나가야 16e 가 404 가 아니다 — PR 본문에 적는다).

---

## Self-review (v1)

- **요구 대조:** 로그아웃 확인(16g) → Task 3. 로그아웃 줄 위치 질문 → 조사 표(DESIGN 은 16 설정). 16e 로그인 정보 · 본인 확인 정보 · 가입 정보 · 카톡 줄 → Task 4 · 5 · 6. 카톡 helper 가 가리키는 화면 → `AppRoutes.account`. 16e-1 route 조율 → T3 · Task 7. 서버 GET(칸 최소 · 로그 금지) → Task 4 계약과 `caplog` 테스트. 범위 밖(16h · 21 · 하트 줄) → 손대지 않는다.
- **자리표시:** `[pen]` · `[pen 노드 id]` 는 대장 값표 대기다(맨 위 v1 표시). 값표를 받으면 v2 에서 모두 지운다. 그 밖의 TBD 는 없다.
- **이름 일관성:** `signOutProvider` · `SessionScope` · `showSafetyConfirmSheet`(재사용) · `AccountInfo` · `AccountRepository.fetchAccount` · `accountRepositoryProvider` · `accountInfoProvider` · `FakeAccountRepository(result:)` · `AppRoutes.account` — Task 사이에서 같다.
- **Review Focus:** 5개 모두 해당 Task 에 테스트가 있다.
