# 가입 동의 나눠 받기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 가입할 때 한 줄로 받던 묵시 동의("계속하면 이용약관과 개인정보처리방침에 동의하게 돼요.")를 없앤다. 대신 로그인 직후 첫 관문인 "약관 동의" 화면(02-c)에서 항목별 체크박스로 받는다. 누가 · 언제 · 어느 판에 동의했는지 서버 시각으로 남긴다.

**Architecture:**
- 새 표 `user_consents`(FastAPI 전용)에 필수 4항목 × 판(version)을 쌓는다.
- 서버는 `GET /me/verification-status` 응답에 `consent`(none · outdated · current)를 더하고, `POST /me/consents` 로 기록한다. 동의가 없으면 `POST /student-verification` 과 `GET /profile-onboarding/next-step` 은 403 이다.
- 앱은 `VerificationGate` 맨 앞에 `needsConsent` · `needsConsentRenewal` 을 두고, `AuthRedirect` 가 정지 다음 · 3b 앞에서 02-c 로 보낸다.
- 마케팅(선택)은 새 칸 없이 기존 `notification_settings.marketing` 을 쓴다.

**Tech Stack:** Supabase Postgres(pgTAP) · FastAPI(pytest, httpx MockTransport) · Flutter + Riverpod 3 + go_router · url_launcher(이미 transitive 6.3.2).

**Spec:** 이 문서 §0(결정 기록) · pen 값표 `C:/Users/user/OneDrive/Desktop/조각6_검토/값표_약관동의.md` + PNG `…/약관동의/` · 설계 §7.7 · 미결21.

## Global Constraints

- 로컬 DB 명령(`supabase db reset` · `supabase test db`)은 **DB 차례를 받은 코더 · 리뷰어만** 돌린다. 도우미 요청문에는 "로컬 DB 명령 금지, 수치는 리뷰어 값 인용"을 적는다.
- git stash 금지. 되돌려 볼 일은 scratchpad 사본 → 복원 → md5.
- `dart format` 금지. pencil 직접 호출 금지. 막힌 동작은 재시도 · 우회 금지.
- 커밋 · PR 에 도구 표식(Co-Authored-By · Claude-Session · Generated with) 금지. 커밋 · PR 은 campus-git 이 한다.
- **운영 적용 순서: 마이그레이션(사용자 승인 관문) → 서버 배포 → 앱.** 서버가 먼저 나가면 `/me/verification-status` 가 없는 표를 읽어 500 이 나고 모두가 3b 에서 막힌다.
- 동의 판: `CONSENT_VERSION = "2026-09-29"`(서버 한 곳). 약관을 고치면 이 값만 올린다. 그러면 모든 계정이 02-c-4(재동의)로 간다.
- 필수 4항목의 전선(wire) 이름: `terms` · `privacy` · `sensitive_religion` · `overseas_transfer`. 마케팅은 이 목록에 넣지 않는다.
- 문구(pen 그대로):
  - 제목 "서비스 이용을 위해 동의해 주세요" / 재동의 "약관이 바뀌었어요"
  - 설명 "필수 항목에 모두 동의하면 시작할 수 있어요.\n마케팅 알림은 선택이에요." / 재동의 "바뀐 내용을 확인하고 다시 동의해 주세요."
  - 앱바 "약관 동의", 버튼 "동의하고 계속하기", "로그아웃", "전체 동의", "보기"
  - 줄: "이용약관" · "개인정보 수집·이용" · "민감정보(종교) 처리" · "개인정보 국외 이전\n(OpenAI 등)" · "마케팅 알림 받기"
- 노션 링크(대장 확인, 비로그인 공개): 기본 `https://app.notion.com/p/3e9d998f0dee8082be84e126630b02a7`. 실기기에서 로그인 요구가 뜨면 `https://golden-leech-197.notion.site/3e9d998f0dee8082be84e126630b02a7` 로 바꾼다(상수 한 줄).
  - 앵커 — 1 이용약관 `#792b6855eaa04bf8a24c19c86702d62f` · 2 · 3 `#efcc38385bef4185b6577d663ebd3bc8` · 4 `#dd3fc6260fa64d78ab12cfaa8a271120` · 5 마케팅은 "보기" 없음.
- url_launcher: `launchUrl(uri, mode: LaunchMode.externalApplication)` 만 쓴다. `canLaunchUrl` 을 쓰지 않으므로 AndroidManifest `<queries>` 는 바꾸지 않는다.

## Review Focus

1. **온보딩을 끝낸 계정이 판이 바뀐 뒤 재동의하면 홈으로 가야 한다(04-1 로 새면 안 된다).** 앱을 켤 때 `next-step` 이 403 이라 온보딩 단계 캐시가 기본값(04-1)에 머문다. 동의 뒤 **온보딩 단계를 먼저 await 로 다시 읽고, 그다음 게이트를 읽는다** → Task 4 VM 테스트 "재동의 뒤 온보딩 단계를 게이트보다 먼저 다시 읽는다".
2. **"동의하고 계속하기"를 빠르게 두 번 눌러도 POST 는 한 번이다.** 서버도 같은 판을 두 번 받아도 실패하지 않는다(`ignore-duplicates`) → Task 4 VM 테스트 · Task 2 pytest.
3. **글자 2배에서 줄이 넘치지 않는다.** 360×780 에서 국외 이전 줄이 3줄 이상으로 접히고, 본문은 스크롤되고, 아래 버튼은 제자리에 있다 → Task 4 화면 테스트.
4. **브라우저를 못 열면(false 또는 예외) 토스트를 띄우고 화면에 남는다** → Task 4 화면 테스트.
5. **재동의 때 마케팅을 켜지 않았다고 기존 수신 동의가 꺼지면 안 된다.** 서버는 `marketing: true` 일 때만 쓰고, false 면 `notification_settings` 를 건드리지 않는다(끄기는 16d) → Task 2 pytest.

---

## 0. 결정 기록 (2026-09-29)

| # | 결정 | 누가 |
| --- | --- | --- |
| Q1 | 받는 곳 = 인증 뒤 **새 사용자만** 보는 동의 화면. 약관이 바뀌면 기존 계정도 같은 관문에서 재동의 | 사용자 |
| Q2 | 종교는 설문 필수 답 그대로 → 민감정보(종교) **[필수]** | 사용자 (나) |
| Q3 | 국외 이전은 **별도 체크** | 대장 |
| Q4 | 마케팅은 **[선택]**으로 넣는다. 기존 `notification_settings` 칸을 쓴다 | 대장 |
| Q5 | "만 19세 이상" 체크는 **뺀다**. 가입 기준이 연 나이("2007년생부터")라 문구가 어긋나고, 04-1 이 이미 막는다 | 대장 |
| Q6 | "보기"는 노션 페이지를 **기기 브라우저**로 연다(웹뷰 아님). `url_launcher` 허락 | 사용자 "가" |
| 자리 | **정지 다음 · 3b 앞, 첫 관문.** `next-step` 은 3b(실명 · 학생증 → Vision OCR)를 지나야 닿아서 동의 전에 정보를 모으게 된다 | 대장 확인 |
| 저장 | 새 표 `user_consents`(S1). DB 차례 → ERD → 사용자 승인 관문 | 대장 |
| pen ① | 재동의는 같은 화면에서 제목 · 설명만 다르다(02-c-4) | 대장 |
| pen ② | 로그아웃 글자 버튼을 둔다(동의하지 않고 나갈 길) | 대장 |
| pen ③ | 가입 화면의 "계속하면 … 동의하게 돼요" 줄을 **지운다** | 대장 |
| 링크 | Global Constraints 의 노션 주소 · 앵커 | 사용자 제공 · 대장 |

**코드에서 확인한 사실(초안 조사)**
- OpenAI 로 얼굴 사진(`avatars.py` gpt-image-1)과 종교(`bio_draft.py` gpt-4o-mini)가 넘어간다. 국외 이전 동의가 필요한 까닭이다.
- 가입 화면은 로그인 화면과 같다. 메일을 보내기 전에는 새 사람인지 알 수 없다(그래서 T1 이 아니라 관문이다).
- `/me/verification-status` 는 `get_caller`(인증 전에도 닿음)다. `next-step` 은 `get_verified_caller` 다.
- 403 은 학생증 · 학과 관문도 쓴다. 정지 · 탈퇴만 `X-Account-Status` 헤더로 가른다. 새 403(동의 없음)은 헤더를 싣지 않아 정지로 오인되지 않는다.
- `url_launcher 6.3.2` 는 `supabase_flutter` · `share_plus` 가 이미 끌어온다. `pubspec.yaml` 1줄 + `pubspec.lock` 1줄만 바뀌고 새로 받는 코드는 없다.

## 1. 화면 대조표 (pen → 앱)

| 요소 | pen(값표 노드) | 앱 | 판정 방법 |
| --- | --- | --- | --- |
| 화면 | 360×780 #FFFFFF | Scaffold canvas | 화면 테스트 |
| 앱바 | KH1hX · 높이 56 · 뒤로 끔 · "약관 동의" 20/700 lh 1.5 | `AppBar(toolbarHeight 56, automaticallyImplyLeading false, navTitle ink)` — 3c 와 같은 모양 | 값 테스트 |
| 본문 | padding [8,16,0,16] · gap 24 | `SingleChildScrollView(padding fromLTRB(16,8,16,0))` + 간격 24 | 값 테스트(왼쪽 16 · 제목 위 8) |
| 제목 | 24/700 lh 1.35 ls -0.48 #222222 | `AppTypography.headline` ink | 값 테스트 |
| 설명 | 16/400 lh 1.6 #3F3F3F, 제목과 간격 8 | `AppTypography.body` body 색 | 값 테스트 |
| 전체 동의 | ConsentRow · 뱃지 · 보기 끔 · 17/600 lh 1.45 · 50 높이 | `ConsentRow(isAllAgree)` · `AppTypography.subtitle` | 값 테스트 |
| 구분선 | CqBWB #EBEBEB 1 | `Divider(height 1, thickness 1, color hairlineSoft)` | 값 테스트 |
| 항목 줄 | rmMvJ/jFMyA · gap 8 · 토글 영역 padding [12,0] gap 12 · 1줄 50 / 2줄 78 | `ConsentRow` | 값 테스트(높이 50 · 78) |
| 체크 칸 | 24 · r6 · 꺼짐 #FFFFFF + #767676 1.5 · 켜짐 #FF385C + check 16 #FFFFFF | `AppCheckbox`(contact_row `_CheckBox` 승격, 테두리 1.5) | 값 테스트 |
| 필수 뱃지 | Aioxz · #FFF0F2 / #C4224B · 11/700 · padding [2,6] · r9999 · 렌더 20 | `primaryWash` / `primaryText` · `badge` w700 height 16/11 | 값 테스트 |
| 선택 뱃지 | #F2F2F2 / #6A6A6A | `surfaceStrong` / `muted` | 값 테스트 |
| 줄 글 | 16/400 lh 1.6 ls -0.16 #222222 | `AppTypography.body` ink | 값 테스트 |
| 보기 › | 높이 48 · 왼쪽 8 · gap 2 · "보기" 14/400 lh 1.55 #6A6A6A · chevron 20 #6A6A6A | `bodySmall` muted · `AppIcons.chevronRight` 20 | 값 테스트 |
| 아래 묶음 | padding [0,16,16,16] · gap 4 | `Padding(fromLTRB(16,0,16,16))` · 간격 4 | 값 테스트 |
| 동의 버튼 | HE8FZ 56 · r16 · 꺼짐 #E5E5E5/#929292 | `AppButton(primary)` — 꺼짐 색은 AppButton 기본 | 값 테스트 |
| 로그아웃 | 48 · 14/600 #6A6A6A · 렌더 20 | `_LogoutButton`(InkWell · `labelSmall` muted height 20/14) | 값 테스트 |
| 가입 화면 | KGo76 · DjqJm(12 간격)를 지움 | `sign_up_screen.dart:101~105` 지움 | 화면 테스트 |

**편차(pen 에 없는 것 — 기존 패턴으로)**
1. 저장 중: `AppButton(isLoading: true)` 스피너.
2. 저장 실패 · 브라우저 못 엶: 버튼 위 12 에 `AppToast`(가입 화면 `_notice` 자리와 같은 규칙), 3초.
3. 로그아웃 확인: 16g 시트(`showSafetyConfirmSheet`, 같은 문구)를 그대로 쓴다.

## 2. 공유 파일 · 줄 단위 허락 요청

| 파일 | 바뀌는 줄 |
| --- | --- |
| `backend/app/main.py` | import 1 + `include_router(consents_router)` 1 |
| `backend/app/core/errors.py` | 상수 2(`CONSENT_REQUIRED` · `CONSENT_INCOMPLETE`) |
| `backend/app/student_verification/schemas.py` | `VerificationStatusResponse` 에 칸 1 |
| `backend/app/student_verification/router.py` | import 2 · 상태 응답 2 · 3b POST 관문 1 |
| `backend/app/profile_onboarding/router.py` | import 1 · next-step 관문 1 |
| `backend/tests/student_verification/test_router.py` · `tests/profile_onboarding/test_onboarding_router.py` | `_wire` 가짜에 `user_consents` 분기 2~3줄 + 새 테스트 |
| `frontend/pubspec.yaml` · `pubspec.lock` | 1줄 · 1줄 |
| `frontend/lib/auth/model/verification_gate.dart` | enum 값 2 |
| `frontend/lib/auth/model/http_verification_gate_repository.dart` | `consent` 읽기 4 |
| `frontend/lib/core/router/verification_gate_listenable.dart` | 기본값 1 + 주석 |
| `frontend/lib/core/router/auth_redirect.dart` | switch 2 · `_isBeforeHome` 1 |
| `frontend/lib/core/router/app_routes.dart` · `app_router.dart` | 경로 1 · GoRoute 1 + import 1 |
| `frontend/lib/safety/view/contact_row.dart` | `_CheckBox` 를 `AppCheckbox` 로(클래스 −24 · import 1 · 사용 1). 테두리 1 → 1.5(같은 pen 마스터 `zlg4q`) |
| `frontend/lib/matching/view/settings_screen.dart` | `_confirmSignOut` 를 `confirmSignOut` 으로 옮김(−14 · import 1 · 호출 1) |
| `frontend/lib/auth/view/sign_up_screen.dart` | 5줄 지움 |
| 각 테스트 파일 | 위 변경에 맞춘 기대값 · 새 테스트 |

**대장 허락(2026-09-29)**: 위 표 전부. ① AppCheckbox 승격(테두리 1.5) ② confirmSignOut 옮김도 허락. 연락처 화면 테스트 기대값이 바뀌면 PR 설명에 한 줄. app_routes · app_router 는 나 탭 3-2 · 채팅 20e 도 만진다 — 나중 merge 쪽이 rebase.

## 3. 구현 기록 (2026-09-29)

계획과 달라진 점:
- 서버 요청 모델 `ConsentRequest` 는 `consents/router.py` 안에 뒀다(`referral/router.py` 와 같은 모양). `schemas.py` 는 만들지 않았다.
- 관문 함수 `require_current_consent` 는 `consents/repository.py` 에 뒀다(`gate.py` 를 따로 두지 않았다).
- `profile_onboarding` 테스트 가짜는 고칠 필요가 없었다. next-step 테스트가 학생증 관문(get_verified_caller)에서 먼저 멈추기 때문이다. 3b 테스트(`student_verification/test_router.py`)만 고쳤다: 가짜에 `user_consents` 분기, 상태 응답 dict 기대 3곳에 `consent`.
- **`supabase/tests/rls_slice0_test.sql` 6번(모든 표 권한을 ERD §2 와 대조)** 이 새 표를 잡았다. 기대 목록에 `user_consents` service_role INSERT · SELECT 두 줄을 넣었다(§2 표에 없던 공유 파일).
- 국외 이전 두 줄 줄: pen 렌더 78, 앱 76(글꼴이 줄마다 26 으로 반올림, pen 은 두 줄일 때 27). 토큰(16/400 lh 1.6)은 같다 — 렌더러 반올림 차이라 편차로 치지 않는다.
- 안내 토스트에 주의 아이콘(alertTriangle 16)을 달았다. 가입 화면 안내와 같은 모양이다(편차 2 안).
- **운영 적용(2026-09-29, 대장 · 사용자 "적용해")**: `20260929010000_create_user_consents.sql`(md5 255d9355) → 운영 기록 20260929051356(51번째). **이 SQL 파일은 더 고치지 않는다** — 바꿀 게 생기면 새 마이그레이션.
- 대장 쪽 리뷰 권고 2개로 pgTAP 를 늘렸다(plan 9 → 11): service_role delete 권한 없음 단정, 프로필 삭제 뒤 동의 기록 is_empty(cascade — `fk_ok` 는 on delete 를 보지 않는다). DB 차례 안에서 이 워크트리로 db reset → `supabase test db` 17 files · 454 tests PASS. 변형(로컬만): service_role 에 delete grant → consents_test 8번 · rls_slice0 6번 실패 → revoke 뒤 권한 f · 454 PASS.

---

### Task 1: DB — `user_consents` (DB 차례 필요)

**Files:**
- Create: `supabase/migrations/20260929010000_create_user_consents.sql`
- Create: `supabase/tests/consents_test.sql`
- Modify: `docs/ERD.md` §3(표) · §8(열거형) · §2(접근 경로)

**Interfaces:**
- Produces: `public.consent_kind` enum(`terms` · `privacy` · `sensitive_religion` · `overseas_transfer`), `public.user_consents(profile_id uuid, kind consent_kind, version text, agreed_at timestamptz)`, PK `(profile_id, kind, version)`. service_role 만 select · insert.

- [x] **Step 1: pgTAP 먼저**

```sql
-- 가입 동의 기록 표 검증. 기대값 기준은 docs/superpowers/plans/2026-09-29-signup-consent.md Task 1.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- 준비: auth.users 를 넣으면 handle_new_user_profile 트리거가 profiles 행을 만든다(rls_slice6_test.sql 과 같은 방식).
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-00000000000c', '테스트대학교C', 'seoul');
insert into public.university_email_domains (domain, university_id)
values ('consent.ac.kr', '00000000-0000-0000-0000-00000000000c');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c7', 'c7@consent.ac.kr');

select has_table('public', 'user_consents', '동의 기록 표가 있다');
select enum_has_labels('public', 'consent_kind',
  array['terms', 'privacy', 'sensitive_religion', 'overseas_transfer'], '필수 4항목');
select col_is_pk('public', 'user_consents', array['profile_id', 'kind', 'version'], '같은 판을 두 번 쌓지 않는다');
select is((select relrowsecurity from pg_class where oid = 'public.user_consents'::regclass), true, 'RLS 켜짐');
select ok(not has_table_privilege('authenticated', 'public.user_consents', 'select'), '앱은 직접 못 읽는다');
select ok(not has_table_privilege('anon', 'public.user_consents', 'select'), '비로그인도 못 읽는다');
select ok(not has_table_privilege('service_role', 'public.user_consents', 'update'), '기록은 고치지 않는다');
select throws_ok(
  $$insert into public.user_consents (profile_id, kind, version)
    values ('00000000-0000-0000-0000-0000000000c7', 'terms', 'v1')$$,
  '23514', null, '판은 YYYY-MM-DD 모양만');
select fk_ok('public', 'user_consents', 'profile_id', 'public', 'profiles', 'id');

select * from finish();
rollback;
```

(학교 id ...000c · 사용자 ...00c7 · 도메인 consent.ac.kr 은 다른 pgTAP 파일에 없다 — 2026-09-29 grep 확인.)

- [x] **Step 2: RED 확인** — DB 차례를 받은 뒤 `supabase test db` 로 실패를 확인한다(표 없음).

- [x] **Step 3: 마이그레이션**

```sql
-- 가입 동의 기록(계획서 docs/superpowers/plans/2026-09-29-signup-consent.md, 사용자 결정 2026-09-29).
-- 필수 4항목만 쌓는다. 마케팅(선택)은 notification_settings.marketing · marketing_consented_at 을 쓴다.
-- 판(version)은 FastAPI 상수 CONSENT_VERSION 이다. 약관을 고치면 판이 올라가 모든 계정이 다시 동의한다.
create type public.consent_kind as enum ('terms', 'privacy', 'sensitive_religion', 'overseas_transfer');

create table public.user_consents (
  profile_id uuid not null references public.profiles (id) on delete cascade,
  kind public.consent_kind not null,
  version text not null check (version ~ '^\d{4}-\d{2}-\d{2}$'),
  agreed_at timestamptz not null default now(),
  primary key (profile_id, kind, version)
);

comment on table public.user_consents is
  '가입 동의 기록(화면 02-c). FastAPI 전용 — 동의 시각은 서버가 적는다. 탈퇴 계정 삭제 때 같이 지운다';

alter table public.user_consents enable row level security;
revoke all on table public.user_consents from anon, authenticated, service_role;
grant select, insert on table public.user_consents to service_role;
```

- [x] **Step 4: GREEN** — `supabase test db` 전체 통과. 수치를 적는다.
- [x] **Step 5: ERD.md** — §3 에 표 상자, §8 에 `consent_kind`, §2 에 "FastAPI 전용(referrals 와 같은 규칙)" 한 줄. ERD.pen 은 campus-pen 몫(대장 경유).

### Task 2: 서버 — 동의 판정 · 기록 · 관문

**Files:**
- Create: `backend/app/consents/__init__.py` · `policy.py` · `repository.py` · `gate.py` · `schemas.py` · `router.py`
- Create: `backend/tests/consents/test_policy.py` · `test_consents_router.py`
- Modify: §2 표의 backend 줄

**Interfaces:**
- Consumes: Task 1 표 · enum.
- Produces:
  - `CONSENT_VERSION: str`, `REQUIRED_KINDS: frozenset[str]`, `consent_state(rows: list[dict]) -> Literal["none", "outdated", "current"]`
  - `ConsentRepository.fetch_rows(profile_id) -> list[dict]` · `record(profile_id, kinds: Iterable[str], version: str) -> None`
  - `async def require_current_consent(settings, client, profile_id) -> None` — 403 `errors.CONSENT_REQUIRED`
  - `POST /me/consents` body `{"agreed": [...4개], "marketing": bool}` → `{"ok": true}`
  - `GET /me/verification-status` 응답에 `"consent": "none" | "outdated" | "current"`

- [x] **Step 1: 판정 테스트(`test_policy.py`)**

```python
from app.consents.policy import CONSENT_VERSION, consent_state

ALL = ["terms", "privacy", "sensitive_religion", "overseas_transfer"]


def test_no_rows_is_none():
    assert consent_state([]) == "none"


def test_all_four_of_current_version_is_current():
    assert consent_state([{"kind": k, "version": CONSENT_VERSION} for k in ALL]) == "current"


def test_old_version_only_is_outdated():
    assert consent_state([{"kind": k, "version": "2000-01-01"} for k in ALL]) == "outdated"


def test_missing_one_required_kind_is_not_current():
    rows = [{"kind": k, "version": CONSENT_VERSION} for k in ALL[:3]]
    assert consent_state(rows) == "outdated"
```

- [x] **Step 2: 라우터 테스트(`test_consents_router.py`)** — 가짜 트랜스포트는 `student_verification/test_router.py` 의 `_wire` 방식(나간 요청 목록을 돌려줌)을 따른다. 테스트:
  1. `POST /me/consents` 가 4항목을 `user_consents` 에 **한 번의 POST** 로, `version = CONSENT_VERSION`, `Prefer: resolution=ignore-duplicates` 로 보낸다(Review Focus 2).
  2. 필수가 하나 빠지면 400 `CONSENT_INCOMPLETE`, 모르는 항목이면 422. 두 경우 모두 DB 요청 0.
  3. `marketing: true` 면 `notification_settings` 에 `marketing: true` + 서버 시각 `marketing_consented_at` 을 upsert 한다(`get_now` 오버라이드로 시각 고정).
  4. **`marketing: false` 면 `notification_settings` 요청이 0이다**(Review Focus 5).
  5. `GET /me/verification-status` 가 `user_consents` 행에 따라 `consent` none / outdated / current 를 돌려준다.
  6. 동의가 없으면 `POST /student-verification` 이 403 `CONSENT_REQUIRED` 이고 Storage · Vision 요청 0이다. 응답에 `X-Account-Status` 헤더가 없다.
  7. 동의가 없으면 `GET /profile-onboarding/next-step` 이 403 `CONSENT_REQUIRED` 다.
  8. 탈퇴 계정은 `POST /me/consents` 가 401 이다(`get_caller` 그대로).

- [x] **Step 3: RED 확인** — `backend` 폴더에서 루트 `.venv` 파이썬으로 `-m pytest tests/consents -q`. import 실패를 확인한다.

- [x] **Step 4: 구현**

`policy.py`:
```python
from typing import Literal

# 약관(노션 "약관동의")을 고치면 이 값만 올린다 — 모든 계정이 02-c-4 에서 다시 동의한다.
CONSENT_VERSION = "2026-09-29"
REQUIRED_KINDS = frozenset({"terms", "privacy", "sensitive_religion", "overseas_transfer"})


def consent_state(rows: list[dict]) -> Literal["none", "outdated", "current"]:
    agreed_now = {row["kind"] for row in rows if row["version"] == CONSENT_VERSION}
    if REQUIRED_KINDS <= agreed_now:
        return "current"
    return "outdated" if rows else "none"
```

`repository.py`:
```python
class ConsentRepository(PostgrestRepository):
    async def fetch_rows(self, profile_id: UUID) -> list[dict]:
        response = await self._get("user_consents",
                                   params={"profile_id": f"eq.{profile_id}", "select": "kind,version"})
        raise_for_status(response)
        return response.json()

    async def record(self, profile_id: UUID, kinds: Iterable[str], version: str) -> None:
        # 두 번 눌러도 같은 판은 한 번만 남는다(PK). 시각은 DB 기본값(now()) — 앱 시각을 믿지 않는다.
        response = await self._post(
            "user_consents",
            json=[{"profile_id": str(profile_id), "kind": kind, "version": version} for kind in sorted(kinds)],
            prefer="resolution=ignore-duplicates",
        )
        raise_for_status(response)
```

`gate.py`:
```python
async def require_current_consent(settings: Settings, client: httpx.AsyncClient, profile_id: UUID) -> None:
    """동의 전에는 실명 · 학생증(3b)도, 온보딩도 받지 않는다(계획서 §0 "자리").
    X-Account-Status 를 싣지 않는다 — 앱이 정지로 오인하지 않게."""
    repo = ConsentRepository(settings.postgrest_url, settings.supabase_service_role_key, client)
    if consent_state(await repo.fetch_rows(profile_id)) != "current":
        raise HTTPException(status_code=403, detail=errors.CONSENT_REQUIRED)
```

`schemas.py`:
```python
class ConsentRequest(BaseModel):
    agreed: list[Literal["terms", "privacy", "sensitive_religion", "overseas_transfer"]]
    marketing: bool = False
```

`router.py`:
```python
@router.post("/me/consents")
async def submit_consents(body: ConsentRequest, caller: Caller = Depends(get_caller),
                          now: datetime = Depends(get_now)) -> dict[str, bool]:
    settings, client, profile_id = caller
    if set(body.agreed) != REQUIRED_KINDS:
        raise HTTPException(status_code=400, detail=errors.CONSENT_INCOMPLETE)
    key = settings.supabase_service_role_key
    await ConsentRepository(settings.postgrest_url, key, client).record(profile_id, body.agreed, CONSENT_VERSION)
    if body.marketing:
        # 켤 때만 쓴다 — 재동의에서 안 켰다고 이미 받은 수신 동의를 끄지 않는다(끄기는 16d).
        await CardRepository(settings.postgrest_url, key, client).update_notification_settings(
            profile_id, marketing=True, marketing_consented_at=now.astimezone(timezone.utc).isoformat())
    return {"ok": True}
```

`errors.py` 에 두 줄:
```python
# 가입 동의(02-c)
CONSENT_REQUIRED = "약관 동의를 먼저 해 주세요"
CONSENT_INCOMPLETE = "필수 항목에 모두 동의해 주세요"
```

`student_verification`:
- `VerificationStatusResponse` 에 `consent: Literal["none", "outdated", "current"]` 칸을 더한다.
- `fetch_verification_status` 는 `ConsentRepository.fetch_rows` → `consent_state` 로 채운다.
- `submit_student_verification` 은 caller 를 푼 직후 `await require_current_consent(settings, client, profile_id)` 를 부른다.

`profile_onboarding/router.py` 의 `get_next_step` 도 caller 를 푼 직후 같은 한 줄을 부른다.

`main.py` 에는 `include_router(consents_router)` 를 넣는다.

- [x] **Step 5: 기존 테스트 가짜 맞추기** — 두 `_wire` 에 분기 하나씩. 기본은 "지금 판 동의 완료"다. 기존 테스트의 뜻은 바꾸지 않는다.

```python
if "/rest/v1/user_consents" in url and request.method == "GET":
    return httpx.Response(200, json=[{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)])
```

- [x] **Step 6: GREEN** — `pytest -q` 전체. 기준 718 + 새 테스트. 실패가 있으면 이름째 적는다.
- [x] **Step 7: 변형 검사** — ① `gate.py` 의 raise 줄 삭제 ② `if body.marketing:` → `if True:` ③ `ignore-duplicates` 삭제. 셋 다 빨개지는지 보고 사본으로 복원 + md5.

### Task 3: 앱 — 게이트 · 이동 · 저장소

**Files:**
- Modify: `frontend/pubspec.yaml` · `pubspec.lock`(`flutter pub add url_launcher`)
- Modify: §2 표의 게이트 · 라우터 줄
- Create: `frontend/lib/consent/model/consent_item.dart` · `consent_links.dart` · `consent_repository.dart` · `http_consent_repository.dart` · `consent_repository_provider.dart` · `open_url.dart`
- Create: `frontend/test/consent/model/fake_consent_repository.dart` · `http_consent_repository_test.dart` · `consent_item_test.dart`
- Modify: `test/core/router/auth_redirect_test.dart` · `verification_gate_listenable_test.dart` · `test/auth/model/http_verification_gate_repository_test.dart`

**Interfaces:**
- Produces:
  - `enum VerificationGate { needsConsent, needsConsentRenewal, needsStudentVerification, needsSchoolInfo, complete }`
  - `AppRoutes.consent = '/consent'`
  - `enum ConsentItem { terms, privacy, sensitiveReligion, overseasTransfer, marketing }` — `label` · `isRequired` · `wireName`(마케팅은 null) · `link`(`Uri?`)
  - `abstract interface class ConsentRepository { Future<Result<void>> submit({required Set<ConsentItem> agreed}); }` — 몸통은 `{"agreed": [필수 wireName], "marketing": agreed.contains(marketing)}`
  - `final openUrlProvider = Provider<Future<bool> Function(Uri)>(...)`

- [x] **Step 1: 테스트 먼저**
  - gate 저장소: `consent: 'none'` → `needsConsent`, `'outdated'` → `needsConsentRenewal`. `'current'` 와 칸이 없을 때(옛 서버)는 지금 규칙 그대로(`verified` + 학교 정보 → `complete`).
  - redirect:
    - `needsConsent` · `needsConsentRenewal` → 어디서든 `/consent`, `/consent` 에서는 null.
    - 정지가 동의보다 먼저다.
    - 동의가 끝난 사용자(`complete` · `complete`)가 `/consent` 에 있으면 홈으로 간다.
  - listenable: 기본값과 `reset()` 이 `needsConsent`(비관적 기본값은 **첫 관문**이어야 한다).
  - `consent_item_test`: 필수 4 · 선택 1, 줄마다 링크 앵커(마케팅 null), 전선 이름 4개를 문자열로 고정한다(서버 `policy.py` `REQUIRED_KINDS` 와 같은 글자 — 언어가 달라 한 테스트로 못 묶으니 양쪽에 같은 목록을 적는다).
  - http 저장소: `POST /me/consents` 몸통이 위 모양이다.

- [x] **Step 2: RED 확인** — `flutter test` 해당 파일들. 컴파일 실패 · 기대값 실패를 확인한다.
- [x] **Step 3: 구현** — enum 2 · `_toGate` 에 `switch (fields['consent'])` 를 먼저 둔다. `_gateTarget` 에 두 값 → `AppRoutes.consent`, `_isBeforeHome` 에 `AppRoutes.consent`. GoRoute, 저장소 · provider(3b 저장소와 같은 모양).

`consent_links.dart`:
```dart
/// 노션 "약관동의" 한 페이지(1부 이용약관 · 2부 개인정보 처리방침). 비로그인 공개(대장 확인 2026-09-29).
/// 실기기에서 로그인 요구가 뜨면 notion.site 주소(https://golden-leech-197.notion.site/3e9d998f0dee8082be84e126630b02a7)로 바꾼다.
/// 약관 페이지를 통째로 다시 쓰면 블록 id 가 바뀔 수 있다 — 앵커 재확인.
const _page = 'https://app.notion.com/p/3e9d998f0dee8082be84e126630b02a7';

final Uri termsLink = Uri.parse('$_page#792b6855eaa04bf8a24c19c86702d62f'); // 1부 이용약관
final Uri privacyItemsLink = Uri.parse('$_page#efcc38385bef4185b6577d663ebd3bc8'); // 2부 2항(수집 · 이용 · 종교 문단)
final Uri overseasTransferLink = Uri.parse('$_page#dd3fc6260fa64d78ab12cfaa8a271120'); // 2부 7항
```

`open_url.dart`:
```dart
/// "보기"는 기기 브라우저로 연다(웹뷰 아님, 계획서 Q6). canLaunchUrl 을 쓰지 않아 AndroidManifest <queries> 가 필요 없다.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
```

- [x] **Step 4: GREEN** — 해당 파일 + `flutter analyze`.

### Task 4: 앱 — 02-c 화면

**Files:**
- Create: `frontend/lib/common/widgets/app_checkbox.dart`(contact_row `_CheckBox` 승격)
- Create: `frontend/lib/core/auth/confirm_sign_out.dart`(settings `_confirmSignOut` 옮김)
- Create: `frontend/lib/consent/viewmodel/consent_ui_state.dart` · `consent_view_model.dart`
- Create: `frontend/lib/consent/view/consent_screen.dart` · `consent_row.dart`
- Modify: `contact_row.dart` · `settings_screen.dart` · `sign_up_screen.dart`(§2 줄)
- Test: `test/consent/viewmodel/consent_view_model_test.dart` · `test/consent/view/consent_screen_test.dart` · `test/auth/view/sign_up_screen_test.dart`(있는 파일에 테스트 1개 추가)

**Interfaces:**
- Consumes: Task 3 전부.
- Produces:
  - `ConsentUiState { Set<ConsentItem> checked; bool isSubmitting; String? errorMessage }`
    - `allChecked`: 5개 다 켜짐
    - `canSubmit`: 필수 4개가 다 켜졌고 저장 중이 아님
  - `ConsentViewModel`: `toggle(ConsentItem)` · `toggleAll()` · `Future<void> submit()` · `clearError()`
    - `toggleAll` 은 다 켜져 있으면 다 끄고, 아니면 다 켠다.
  - `Future<void> confirmSignOut(BuildContext, WidgetRef)`
  - `AppCheckbox({required bool checked})`

- [x] **Step 1: VM 테스트**
  1. 처음에는 모두 꺼져 있고 `canSubmit` 은 false 다.
  2. 필수 4개를 켜면 true 다(마케팅은 꺼져 있어도 된다).
  3. `toggleAll` → 5개 켜짐, 다시 → 다 꺼짐.
  4. 필수 하나가 꺼져 있으면 전체 동의가 꺼져 있다(`allChecked` false).
  5. `submit` 은 저장소를 **한 번** 부른다. 두 번째 호출은 저장 중이라 무시한다(Review Focus 2).
  6. 성공하면 **온보딩 단계를 먼저 await 로 다시 읽고, 그다음 게이트를 다시 읽는다** — 가짜 두 개에 순서 기록(Review Focus 1).
  7. 실패하면 `errorMessage` 가 실패 문구이고, `isSubmitting` 은 false, 게이트 조회는 0이다.

- [x] **Step 2: 화면 테스트(360×780, dpr 1)**
  1. 문구가 Global Constraints 그대로다.
  2. 재동의(`needsConsentRenewal`)면 제목 · 설명만 바뀐다.
  3. 줄을 누르면 체크가 바뀐다. 전체 동의를 누르면 다 켜진다. 필수를 다 켜야 버튼이 켜진다.
  4. "보기"를 누르면 `openUrlProvider` 가 그 줄의 링크로 한 번 불린다. 마케팅 줄에는 "보기"가 없다.
  5. `openUrl` 이 false 거나 예외면 토스트가 뜨고 화면에 남는다(Review Focus 4).
  6. 저장 실패 토스트가 뜬다.
  7. 로그아웃 → 16g 시트 → 확인 → `signOutProvider` 가 한 번 불린다.
  8. 글자 2배: 넘침 예외 0, 버튼이 화면 아래 16 위에 있다(Review Focus 3).
  9. 시스템 뒤로가기: 관문이라 `PopScope(canPop: false)`.

- [x] **Step 3: pen 값 테스트 묶음 "pen 값(02-c woJzd · ConsentRow rmMvJ/jFMyA)"** — §1 표의 "값 테스트" 줄 하나당 단정 하나(친구 초대 16i 묶음과 같은 방식).
- [x] **Step 4: 가입 화면** — "동의하게 돼요" 글자가 없고, "인증 메일 받기" 아래 간격도 없어졌다(find).
- [x] **Step 5: RED 확인** — 모두 실패 · 컴파일 실패를 확인한다.
- [x] **Step 6: 구현** — 모양은 §1 표 그대로.
  - `ConsentRow`:
    - `Row(gap 8)` 안에 `Expanded(Semantics(checked, InkWell(Padding(v12, Row(gap 12: AppCheckbox, [뱃지], Expanded(글)))))` 와 `[보기 InkWell(높이 48, 왼쪽 8, Row(gap 2))]` 를 둔다.
    - 잉크는 가장 가까운 Material 에 그린다(COMMON §4-2). 목록을 투명 Material 로 감싼다.
  - `AppCheckbox`: 테두리 1.5(`zlg4q`). contact_row 는 import 해 쓴다.
  - `confirmSignOut`: settings 의 본문을 그대로 옮기고, settings 는 호출만 남긴다.
- [x] **Step 7: GREEN** — `flutter test` 전체 + `flutter analyze`. 기준 1554 + 새 테스트.
- [x] **Step 8: 변형 검사** —
  - ① VM 의 저장 중 guard 삭제
  - ② refresh 순서 뒤집기
  - ③ `PopScope` 삭제
  - ④ 마케팅 줄에 보기 켜기
  - 넷 다 빨개지는지 보고 복원 + md5.

### Task 5: 마무리

- [x] 리뷰어(campus-reviewer): 계획서 대조 · pen 값 대조 · RED 재현 · 로컬 DB 명령은 DB 차례 안에서만.
- [ ] campus-git: 의미 단위 커밋을 한다(DB · 서버 · 앱 게이트 · 앱 화면 · 가입 화면 · 계획서). 그다음 draft PR 을 **DB+서버 1개, 앱 1개로 나눌지** 대장에게 묻는다(운영 적용 순서가 달라서다).
- [ ] 대장: 마이그레이션 운영 적용(사용자 승인) → 서버 배포 → 앱. 배포 뒤 기존 계정이 모두 02-c(재동의가 아니라 처음 판)로 가는 것이 정상이다 — 첫 판이라 이전 기록이 없다.
  - **실기기 앱도 서버와 같이 갱신한다.** consent 를 모르는 옛 앱 + 새 서버면 온보딩을 끝낸 계정이 next-step 403 에 막혀 04-1 에 갇힌다(리뷰 사소 2, 스토어 배포 전이라 실피해 없음).

**리뷰(2026-09-29, campus-reviewer) PASS — 필수 0 · 권고 1 · 사소 3.** pytest 734 · test 1598 · analyze 0 재실행 일치, pgTAP 는 인용(차례 없음). Review Focus 1~5 전부 PASS, 1번 RED 재현(순서 뒤집기 → VM 테스트 실패, `AuthRedirect(complete, basicInfo)` 로 04-1 경로 실증).
- 권고 1(보류 · 대장 백로그 후보): 재동의 뒤 온보딩 조회가 **네트워크로** 실패하면 캐시가 basicInfo 인 채 게이트가 complete 로 바뀌어 04-1 로 샌다. 앱을 다시 켜면 풀린다. 리뷰 제안("온보딩 조회 실패면 게이트 조회를 건너뛴다")은 **새 사용자를 02-c 에 가둔다** — 새 사용자는 학생증 전이라 next-step 이 늘 403(실패)이다. 고치려면 403(관문)과 네트워크 실패를 가려야 한다. 판이 처음 올라가기 전(약관 개정 전)에는 재동의 계정이 없어 지금은 생기지 않는다.
- 사소 2: 위 줄로 반영. 사소 3(next-step 200 정상 경로 테스트 없음): 관문 호출은 변형 ①로 증명돼 넣지 않았다. 사소 4(ERD.md §2 검증 목록 service_role 문장): 예외 한 줄 반영.
