# CampusMate DB ERD

> 근거: 설계 문서 `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` (§2·§5·§6·§7·§13), `frontend/docs/DESIGN.md` (§5.2·§8·§9), 2026-09-13 ~ 09-14 사용자 결정(§11).

> **현재 상태 (2026-10-27 문서 정리).** 저장소 `supabase/migrations/` **97개 = 운영 97개, 모두 적용**이다(마지막 `20261027100000_admin_matching_requests`, 원격 버전 `20261027053822`, 대장이 이 세션에서 확인한 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 조각 0 ~ 7, 소셜 로그인 전환, 인앱결제, 관리자 웹, 졸업생 인증까지 표 · 열 · 함수가 모두 이 문서에 들어 있다. 학생증 · 실명 사진 인증은 2026-10-17 에 폐지했고 졸업생 길(졸업증명서 + 관리자 검수)이 2026-10-19 에 들어왔다. **10-19 이후 새 마이그레이션 4개는 표 · 열을 바꾸지 않는다**: `20261019220000_admin_billing_returned_accounts`(읽기 함수 `admin_billing_returned_accounts(p_limit)` — 관리자 결제 화면 "환불이 잦은 계정", §7) · `20261020100000_faq_support_email_change`(`faq` 답변의 문의 메일만 `replace`, 데이터) · `20261020110000_close_seoul_schools_until_cohort_open`(`universities.card_opens_at` 데이터 — 서울 학교 64곳을 2026-11-02(월) 07:00 KST 로, §3) · **`20261027100000_admin_matching_requests`**(2026-10-27, 읽기 함수 `admin_matching_requests(p_status, p_before_at, p_before_id, p_limit)` — 관리자 웹 매칭 현황 A9 맨 아래 "누가 누구에게 대화를 신청했나" 목록, 새 표 없음, `service_role` 만 실행, §7). **운영 DB 에는 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3, 2026-10-27 00:26 KST 적용)가 들어 있고 출시 전에 반드시 제거한다**(마이그레이션 파일이 아니라 일회성 스크립트로 넣었다 — `backend/DEPLOY.md` §4-16). 날짜별 갱신 줄(10-20 문서 정리 때의 현재 상태 포함)은 문서 맨 아래 "갱신 이력" 에 그대로 있다. 원격 버전은 적용 시각이라 파일 이름과 다른 경우가 있다(`docs/SUPABASE.md` §4 관례).

## 읽는 법

- 컬럼 주석 맨 앞의 **`조각N`** = 그 컬럼·테이블을 추가하는 조각. 조각을 시작할 때 추가한다(설계 §5.4)
- **`제안`** = 스펙에 없어서 이 ERD가 제안하는 것
- **`검토N`** = 아직 정해지지 않은 것. 번호는 §12 "남은 검토"
- **`민감`** = 남에게 가는 응답에 절대 담지 않는 값(설계 §7.1). 민감 값은 `profile_private` 에만 둔다
- 컬럼 없이 계산하는 값: 가입 나이 자격(Asia/Seoul 기준 올해 − `birth_year` ≥ 19, FastAPI 검사), 신뢰 확인 기한(`matches.created_at` + 48시간), 안 읽은 메시지 수(상대가 보낸 메시지 중 `created_at` > 내 `match_participants.last_read_at`), 아바타 교체 무료 여부(`profile_avatars` 성공 건수), 주기당 추가 카드 1장(`daily_cards.source` — **2026-10-10 개정: `paid_card_offers` 의 부분 유일 인덱스 `paid_card_offers_one_live_per_cycle` 가 DB 에서 막는다**, §4), 월간 추천 랭킹(`referrals` 집계, 탈퇴자 제외 §3. 계정 삭제 cascade 로 지난달 행이 줄 수 있어 월말에 순위를 확정해 지급한다 — 조각 7)

## 1. 조감도

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    auth_users ||--o| profiles : "id 공유 · 가입 도중 이탈하면 없음"
    universities ||--o{ university_email_domains : "메일 도메인"
    universities ||--o{ profiles : "소속"
    region_group_settings ||..o{ universities : "region_group"
    profiles ||--o| profile_private : "민감 정보"
    profiles ||--o| school_email_claims : "학교 메일 1개 · 인증 전이면 없음"
    universities ||--o{ school_email_claims : "학교 · restrict"
    profiles ||--o{ student_verification_attempts : "학생증 제출"
    profiles ||--o{ graduate_verification_requests : "졸업생 인증 신청"
    universities |o--o{ graduate_verification_requests : "승인 때 정한 학교"
    profiles ||--o{ profile_photos : "실사진"
    profiles ||--o{ profile_avatars : "아바타"
    profiles ||--o{ survey_answers : "설문 원본"
    profiles ||--o| profile_vectors : "벡터"
    profiles ||--o{ daily_cards : "받은 카드"
    daily_cards ||--o| card_decisions : "결정"
    card_decisions ||--o| acceptance_responses : "받은 수락함 응답"
    profiles ||--o{ matches : "당사자"
    matches ||--|{ match_participants : "당사자별 상태"
    matches ||--o{ messages : "대화"
    profiles ||--o{ push_tokens : "기기"
    profiles ||--o| notification_settings : "알림"
    profiles ||--o{ pending_pushes : "밤 알림 보류"
    profiles ||--o{ notifications : "알림함"
    profiles ||--o{ paid_card_offers : "유료 카드 제안 owner · target"
    daily_cards |o--o{ paid_card_offers : "산 카드 · 카드가 지워지면 칸만 비운다"
    profiles ||--o{ user_consents : "가입 동의"
    profiles ||--o{ blocks : "차단"
    profiles |o--o{ reports : "신고"
    profiles ||--o{ contact_blocks : "연락처 차단"
    profiles ||--o| entitlements : "하트 잔액"
    profiles ||--o{ heart_transactions : "하트 원장"
    profiles |o--o{ purchases : "결제"
    profiles ||--o{ heart_task_submissions : "무료 하트 인증"
    promo_codes ||--o{ promo_redemptions : "코드 사용"
    profiles ||--o{ referrals : "추천"
    profiles ||--o{ friend_reviews : "지인 리뷰"
    profiles ||--o{ polls : "커뮤니티 질문"
    polls ||--o{ poll_votes : "투표"
```

관계가 없는 독립 테이블: `signup_blocks`(탈퇴 후 재가입 제한), `faq`(자주 묻는 질문, 2026-09-29 적용), `unknown_email_domain_attempts`(화이트리스트에 없어 거절된 학교 메일 도메인과 횟수, 2026-10-17), `admin_users`(관리자 명단 — `auth.users` 를 가리키지만 `profiles` 와는 이어지지 않는다) · `admin_actions`(관리자 작업 기록 — FK 없음)(둘 다 2026-10-18, §7).

## 2. 접근 경로와 RLS

**원칙 (2026-09-13 사용자 결정, §11-8)**

- **쓰기는 전부 FastAPI** 가 검증한 뒤 `service_role` 로 한다. 클라이언트(`authenticated`)에는 INSERT·UPDATE·DELETE 정책을 하나도 두지 않는다. 사용자가 API를 직접 호출해 자기 `status`·`university_id`·인증 상태를 바꾸는 우회가 여기서 막힌다(설계 §7.3·§7.6)
- **클라이언트가 직접 읽는 건 본인 데이터뿐이다.** 정책은 `to authenticated using ((select auth.uid()) = <본인 컬럼>)` 꼴
- **남의 데이터는 FastAPI가 필요한 컬럼만 골라 준다** — 카드 속 상대, 받은 수락함, 매칭 상대의 사진·카카오톡 아이디, 투표 집계, 지인 리뷰. `security definer` 함수는 쓰지 않는다(frontend/CLAUDE.md §10.1)
- **RLS는 컬럼을 가리지 못한다.** 두 사람이 같은 행을 읽는 테이블에는 둘 다 알아도 되는 값만 둔다(`matches` ↔ `match_participants`). 본인 행 안에서도 내려보내지 않을 컬럼은 컬럼 단위 grant 로 뺀다
- **탈퇴 삭제 규칙(§11-11 · §11-15).** 탈퇴하면 FastAPI 가 계정을 `withdrawn` 으로 바꾸고 30일 뒤 `auth.users` 를 지운다. 아래 FK 규칙은 그 삭제 때 적용된다. `profiles` 를 가리키는 FK 와, 탈퇴로 지워지는 행을 가리키는 하위 FK(`card_decisions.card_id` · `acceptance_responses.card_id` · `match_participants.match_id` · `messages.match_id` · `poll_votes.poll_id`)는 `on delete cascade` 다. 하나라도 기본값(no action)으로 두면 `auth.users` 삭제가 23503 으로 실패해 탈퇴가 막힌다. 예외는 `reports.reporter_id`(set null, 신고 근거 보존), `profile_avatars.source_photo_id`(set null, §3), `purchases.profile_id`(set null, 결제 내역 5년 보관, §11-14)다. `profiles` 행은 `auth.users` 를 따라 cascade 로 지워진다
- **grant 도 이 표를 따르고, RLS 와 같은 마이그레이션에 둔다.** 새 테이블에 `anon`·`authenticated` 권한이 자동으로 붙는지는 프로젝트 설정에 따라 달라서 믿지 않는다(Supabase 문서 Securing your API). 테이블마다 `revoke all ... from anon, authenticated, service_role` 뒤에 필요한 것만 준다. `service_role` 까지 revoke 해야 자동 grant 유무(프로젝트 설정·적용 시점)와 상관없이 결과가 같다
  - `service_role`: 전 테이블 `select` · `insert` · `update` · `delete`
  - `authenticated`: 아래 표에서 읽기가 있는 테이블만 `select`
  - `anon`: `universities` · `university_email_domains` 만 `select`
  - `anon` · `authenticated` 에는 `insert` · `update` · `delete` 를 주지 않는다. 클라이언트 쓰기는 정책이 아니라 권한에서 막혀 오류(42501)로 끝난다

| 테이블 | 클라이언트 읽기 | 비고 |
| --- | --- | --- |
| `universities` · `university_email_domains` | `anon` · `authenticated` 전체 | 가입 화면의 학교·도메인 확인 |
| `region_group_settings` | `authenticated` 전체 | 다음 지급 시각 표시 |
| `profiles` | 본인 행 (`id`) | |
| `profile_private` | 본인 행 (`profile_id`) · 컬럼 grant `profile_id` · `real_name` 만 | 16e 본인 실명 조회. 번호 암호문·`phone_hmac`·카카오톡 아이디는 내려가지 않는다. 앱은 `select *` 대신 컬럼을 지정한다. 본인 `kakao_id`(16e · 14f · 16e-1)는 FastAPI 가 내려준다(§11-20). **2026-09-28 개정: 16e 는 실명도 서버 `GET /account` 로 받는다**(실명 · 출생연도 · 학교 · 가입일 · 카톡을 한 번에, 계획서 `2026-09-27-account-logout.md` T2). 컬럼 grant 는 남아 있지만 지금 앱은 이 표를 직접 읽지 않는다. **2026-10-12 추가: 새 암호문 열 `real_name_enc` · `kakao_id_enc` 는 grant 하지 않는다**(`20261011010000`) — 읽기는 서버가 `service_role` 로 `decrypt_profile_private` 를 불러서만 한다(§3). **2026-10-12 M2 개정(`20261012010000`, 운영 적용 · 파일은 PR #476 merge 대기)**: 평문 `real_name` 열이 지워져 그 컬럼 grant 도 사라졌다 — 지금 `authenticated` 의 컬럼 grant 는 `profile_id` 하나다(종전 "`profile_id` · `real_name` 만") |
| `student_verification_attempts` | 없음 | FastAPI 전용 — 본인 반려 사유는 FastAPI 응답으로 내려주고, 재시도 횟수는 행 수로 FastAPI 가 센다(§12-4) |
| `profile_photos` · `profile_avatars` · `survey_answers` | 본인 행 (`profile_id`) | |
| `profile_vectors` | 없음 | FastAPI 전용 |
| `daily_cards` · `card_decisions` · `acceptance_responses` | 없음 | FastAPI 전용 — 카드 화면에는 상대 정보가 섞인다 |
| `paid_card_offers` | 없음 | FastAPI 전용(2026-10-10 운영 적용). RLS 켬 · 정책 0 — 본인 행도 못 읽는다. `service_role` 만 네 권한. 제안은 서버가 `GET /cards/today` 의 `paid_card` 로 내려준다(§4) |
| `notifications` | 없음 | FastAPI 전용(2026-10-10 운영 적용). RLS 켬 · 정책 0, `service_role` 만 네 권한. 안 읽은 개수 · 목록은 서버가 내려준다(§4) |
| `matches` | 당사자 (`profile_a` · `profile_b`) | 둘 다 알아도 되는 값만 있다 |
| `match_participants` | 본인 행 (`profile_id`) | 이 테이블로는 상대 행을 못 읽는다. 상대의 수락·나가기는 `messages` 의 시스템 줄로 전해진다(§4). **2026-10-13 추가: 상대가 읽은 시각(읽음 '1')은 이 정책을 열지 않고 FastAPI 가 `service_role` 로 읽어 응답 키 `partner_last_read_at` 으로 준다**(§4) |
| `messages` | 참여 중인 매칭의 메시지 | `exists (select 1 from match_participants mp where mp.match_id = messages.match_id and mp.profile_id = (select auth.uid()) and mp.left_at is null)` |
| `push_tokens` | 없음 | FastAPI 전용 |
| `notification_settings` | 본인 행 | |
| `pending_pushes` | 없음 | FastAPI 전용. **`service_role` 도 `select` · `insert` · `delete` 만** — 보류한 알림은 보내고 지울 뿐 고치지 않는다(§4) |
| `user_consents` | 없음 | FastAPI 전용. **`service_role` 도 `select` · `insert` 만** — 동의 기록은 고치지 않는다(위 "전 테이블" 규칙의 예외). 동의 여부는 `/me/verification-status` 의 `consent` 가 내려준다 |
| `blocks` · `reports` | 없음 | FastAPI 전용 — 차단 목록(16f)은 상대 닉네임이 필요하다. 신고자에게도 신고 목록을 주지 않는다 |
| `contact_blocks` | 본인 행 (`owner_id`) · 컬럼 grant `id` · `owner_id` · `created_at` 만 | 16b 목록. `contact_hmac` 은 내려가지 않는다. **2026-09-27 구현 개정: 클라이언트 권한 0**(정책 없음, `authenticated` grant 없음). 16b 목록은 FastAPI `GET /contact-blocks` 가 준다 |
| `entitlements` · `heart_transactions` · `purchases` · `heart_task_submissions` | 본인 행 | 잔액·내역·인증 상태. `heart_task_submissions` 는 2026-09-28 적용 — 본인 행 `select` 정책 하나, 18a 상태는 서버가 DB 함수로 계산해 준다 |
| `referrals` · `friend_reviews` | 없음 | FastAPI 전용(둘 다 2026-09-28 적용, 정책 0 · `service_role` 만 네 권한) |
| `polls` · `poll_votes` | 없음 | FastAPI 전용 — `author_id` 를 열면 익명이 깨지고(DESIGN §8.11), `poll_votes` 는 본인 행만 열면 집계가 안 되고 다 열면 누가 뭘 골랐는지 보인다 |
| `faq` | `authenticated` 전체 | 2026-09-29 적용. 앱이 supabase-flutter 로 바로 읽는다(공개 참조 표 — ERD_DECISIONS 8 의 예외). `authenticated` = `select` 만, `anon` 없음, `service_role` = 네 권한(문구는 대시보드에서 고친다). 첫 문구 36행은 마이그레이션 안 insert(묶음별 7 · 5 · 6 · 4 · 6 · 8) |
| `signup_blocks` · `promo_codes` · `promo_redemptions` | 없음 | 서버 전용 |
| `graduate_verification_requests` | 없음 | FastAPI 전용(2026-10-19 운영 적용). RLS 켬 · 정책 0 — 본인 신청도 못 읽는다(상태는 `GET /me/verification-status` 의 `graduate` 칸으로 서버가 내려준다). `service_role` 만 네 권한 |
| `admin_users` | 없음 | FastAPI 전용(2026-10-18 운영 적용). **`service_role` 은 `select` 만** — 서버 버그가 나도 스스로를 관리자로 넣거나 명단을 지우지 못한다(`20261018035204`). 등록은 사용자 승인 뒤 대장이 SQL 한 줄로 한다 |
| `admin_actions` | 없음 | FastAPI 전용(2026-10-18 운영 적용). **`service_role` 도 `select` · `insert` 만** — 기록은 고치거나 지우지 못한다(위 "전 테이블" 규칙의 두 번째 예외). 보관 2년 |
| `unknown_email_domain_attempts` | 없음 | FastAPI 전용(2026-10-17 운영 적용). RLS 켬 · 정책 0, `service_role` 만 네 권한 |
| `school_email_claims` | 없음 | FastAPI 전용(2026-10-09 운영 적용). RLS 켬 · 정책 0 — 본인 행도 못 읽는다(`signup_blocks` 와 같다). `service_role` 만 네 권한. 인증 여부는 FastAPI 가 내려준다(§3) |
| `realtime.messages`(Supabase 내장 — 우리 테이블이 아니다) | `authenticated` 본인 토픽의 broadcast 만 | **2026-10-14 운영 적용(`20261013152736`, PR #512) — 채팅 실시간 사용자 채널 입장 권한.** 정책 하나 `user_channel_read_own`: `for select to authenticated using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'user:' \|\| (select auth.uid())::text)` — 앱은 비공개(private) 채널 `user:<내 profile_id>` 에만 들어온다(남의 토픽 · presence · `anon` 은 입장 때 거부). **보내기(insert) 정책은 두지 않는다** — 쏘는 쪽은 FastAPI 의 `service_role` REST Broadcast 뿐이라(RLS 를 거치지 않는다) 앱이 남의 채널로 가짜 이벤트를 쏠 수 없다. 테이블 조회가 없어 입장이 가볍다. 테이블 · publication · grant · `security definer` 변경 없음. 정책은 입장 때 한 번 계산돼 연결 동안 캐시되므로 나간 · 차단한 사람에게 안 쏘는 것은 서버 규칙(`left_at is null` 인 사람에게만)이 맡는다. 방 채널 `messages:<match_id>`(`postgres_changes`, public 채널)는 이 정책과 무관하다. 이벤트 계약은 `backend/DEPLOY.md` §4-8 |

사이클 B pgTAP 기대값의 기준:

- 읽기가 있는 테이블: 남의 행 0행. `match_participants` 는 같은 매칭 상대의 행도 0행, `messages` 는 비당사자와 `left_at` 이 찍힌 본인 모두 0행
- 읽기가 없는 테이블(FastAPI · 서버 전용): 본인 행이라도 `select` 가 42501
- 컬럼 grant 테이블: `profile_private` 에서 본인 `select real_name` 은 1행, `select *` 는 42501(조각 1). 본인 `select kakao_id` 도 42501(§11-20). **2026-10-12 M2 개정**: 평문 열이 없어져 본인 `select profile_id` 가 1행이고 `select *` 는 그대로 42501 이다(PR #476 의 `rls_slice1_test.sql` · `profile_private_drop_plaintext_test.sql`)
- 모든 테이블: `anon` · `authenticated` 의 INSERT · UPDATE · DELETE 가 42501
- `anon` 은 `universities` · `university_email_domains` 읽기만 된다
- `profiles` 제약: 온보딩 컬럼 없는 `pending` 행 insert 는 성공, 필수값 없이 `active` 로 바꾸면 check 위반, 대소문자만 다른 닉네임은 unique 위반(§3)
- `service_role` 은 테이블마다 `select` · `insert` · `update` · `delete` 가 모두 있다. 하나라도 빠지면 FastAPI 쓰기가 깨진다. 예외: `user_consents` 는 `select` · `insert` 만(동의 기록은 고치지 않는다, 위 표)
- `public` 시퀀스에는 `anon` · `authenticated` · `service_role` 권한이 하나도 없다(0행). identity 컬럼은 테이블 `insert` 권한만으로 번호를 받는다(조각 1 `student_verification_attempts_id_seq`)
- `profile-photos` · `student-id-temp` 버킷은 비공개이고 `storage.objects` 에는 정책이 없다(§9). 두 버킷 모두 10MB · `image/jpeg` · `image/png` 제한이 걸린다(조각 1)
- 계정 삭제 cascade(탈퇴 30일 뒤, §11-15): `auth.users` 행을 지우면 `profiles` · `profile_photos` · `profile_private` · `student_verification_attempts` 행이 함께 지워진다

## 3. 계정 · 프로필 (조각 0~3)

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    auth_users ||--o| profiles : "id 공유 · 가입 도중 이탈하면 없음"
    universities ||--o{ university_email_domains : "학교당 여러 개"
    universities ||--o{ profiles : "소속"
    region_group_settings ||..o{ universities : "region_group"
    profiles ||--o| profile_private : "민감 정보"
    profiles ||--o| school_email_claims : "학교 메일 인증 1회"
    universities ||--o{ school_email_claims : "on delete restrict"
    profiles ||--o{ student_verification_attempts : "학생증 제출 한 번에 한 행"
    profiles ||--o{ graduate_verification_requests : "졸업생 인증 신청 · 사람당 최대 3회 · 대기 1건"
    universities |o--o{ graduate_verification_requests : "승인 때 관리자가 정한 학교 · restrict"
    profiles ||--o{ user_consents : "항목 × 판마다 한 행"
    profiles ||--o{ profile_photos : "실사진 2~4장"
    profiles ||--o{ profile_avatars : "생성 이력"
    profile_photos |o--o{ profile_avatars : "원본 사진"
    profiles ||--o{ survey_answers : "9축"
    profiles ||--o| profile_vectors : "1행"

    universities {
        uuid id PK "조각0"
        text name UK "조각0"
        text region_group "조각0 · 첫 출시 seoul"
        timestamptz card_opens_at "코호트 2026-09-28 적용 · null=이미 열림 · 월요일 07:00 Asia/Seoul 만(check)"
        timestamptz created_at "조각0"
    }

    university_email_domains {
        text domain PK "조각0 · 학생인증 화이트리스트 · 소문자"
        uuid university_id FK "조각0"
    }

    region_group_settings {
        text region_group PK "조각4 · 가칭"
        smallint[] issue_weekdays "지급 요일 · 배치가 사다리로 덮는 결과값 · 기본 월(1) · 2026-10-03 5단계(ladder.py)"
        integer ladder_twice_per_week_min "남녀 중 적은 쪽 활성 인원 이 값 이상 주 2회(월목) · 기본 50 · 미만은 주 1회(월)"
        integer ladder_three_per_week_min "주 3회(월수금) · 기본 500"
        integer ladder_four_per_week_min "주 4회(월수금일) · 기본 1000"
        integer ladder_daily_min "매일 · 기본 2000 · 넷은 오름차순 check"
        time issue_time "07:00 · Asia/Seoul"
        timestamptz updated_at
    }

    profiles {
        uuid id PK, FK "조각0 · auth.users.id"
        uuid university_id FK "조각0 · 2026-10-09 null 허용 · 학교 메일 인증(complete_school_email_verification)이 정함 · null=인증 전"
        text nickname UK "조각0 · lower 유니크 · 한글영문 2~5자"
        gender gender "조각0 · 하드 필터"
        smallint birth_year "조각0 · 연 나이 19세 이상"
        smallint height_cm "조각0 · 필수 · 공개"
        smallint preferred_height_min "조각0 · null이면 상관없음"
        smallint preferred_height_max "조각0"
        text bio "조각0 · self_embedding 원본"
        text mbti "조각0 · null이면 모름"
        jsonb preferred_mbti_flags "조각0 · 8극 토글"
        text major "조각0 · 표시만 · 조각1b부터 department 로도 별칭 응답"
        major_field major_field "조각0 · 표시만"
        smallint admission_year "조각0 · 21 입력을 2021로 저장"
        text student_number "조각1b · 자기 입력 · 학생증 대조 없음"
        text[] interest_tags "조각0 · 45개 풀 3~5개"
        profile_status status "조각0 · 기본 pending · withdrawn 은 조각6(적용됨)"
        timestamptz last_active_at "조각0 · 활동성 계수"
        timestamptz created_at "조각0"
        verification_status student_verification "조각1 · 기본 none · FastAPI 만 바꿈"
        timestamptz nickname_changed_at "조각2 · 30일 1회"
        boolean is_smoker "조각2 · 감점 계수"
        religion religion "조각2 · 감점 계수"
        animal_type animal_type "조각2 · 본인 1개"
        impression_type impression_type "조각2 · 본인 1개"
        animal_type[] preferred_animal_types "조각2 · 1~3개 · 필수(2026-09-20 선택→필수)"
        impression_type[] preferred_impression_types "조각2 · 1~3개 · 필수(2026-09-20 선택→필수)"
        text[] my_traits "조각2 · 48개 풀 3~5개"
        text[] ideal_traits "조각2 · 45개 풀 3~5개"
        smallint preferred_age_min "조각2 · null이면 상관없음"
        smallint preferred_age_max "조각2"
        acquisition_channel acquisition_channel "조각2 · 20d 유입경로 · 선택"
        text acquisition_note "조각2 · 기타 한 줄"
        text ideal_note "조각2 · 이런 사람이 좋아요 자유 글 · 필수(2026-09-20 선택→필수) · 빈 문자열=미입력, 매칭 임베딩에서 없음 처리"
        text bio_draft "조각2 · AI 자기소개 초안 저장본 · bio-draft 재호출 시 재생성 대신 이 값 반환"
        timestamptz bio_draft_generated_at "조각2 · 초안 생성 시각 · 1회 제한(설계 §13-71)"
        boolean matching_paused "조각4 · 일시중지 토글"
        timestamptz withdrawn_at "조각6 적용 · 탈퇴 요청 시각 · 30일 뒤 계정 삭제 · status=withdrawn 과 짝(check)"
        timestamptz auto_hidden_at "조각6 적용 · 서로 다른 3명 신고로 자동 가림된 시각 · 카드 · 새 매칭 제외"
        text referral_code UK "추천 2026-09-28 적용 · 대문자 숫자 6자(0 O 1 I 제외) · DB 기본값으로 발급 · not null"
        timestamptz school_email_verified_at "2026-10-09 적용 · 학교 메일 인증 시각 · null=인증 전(14일 뒤 정리 배치) · auth.users.email_confirmed_at 과 다름 · 2026-10-19 졸업생 승인도 이 칸을 채운다"
        text verification_method "2026-10-19 적용 · school_email graduate_certificate(check) · null=아직 안 고름=학교 메일로 간주(옛 앱 호환) · PUT /me/verification-method 가 쓴다 · 인증 뒤 변경 금지"
        timestamptz graduate_verified_at "2026-10-19 적용 · 졸업생 인증으로 통과한 시각 · 내부 칸(다른 사람에게 안 보임) · check: 있으면 school_email_verified_at 도 있어야 함"
    }

    graduate_verification_requests {
        uuid id PK "2026-10-19 적용 · 졸업생 인증(졸업증명서)"
        uuid profile_id FK "not null · on delete cascade · 프로필당 대기(pending) 1건만(부분 unique)"
        text status "pending approved rejected cancelled(check) · 기본 pending"
        text reason "rejected: unreadable not_certificate unverifiable school_unsupported / cancelled: switched expired verified_otherwise account_withdrawn · 그 밖엔 null(상태쌍 check)"
        text photo_path "graduate-cert-temp 비공개 버킷 경로 · 대기 중 not null · 결정 즉시 서버가 파일 삭제 후 null(못 지우면 매시 배치)"
        text ocr_state "not null · read nothing_found failed(check) · 글자 인식 결과는 관리자 입력 미리 채우기 전용(자동 승인 안 씀)"
        text ocr_document_number "평문 · 대기 중에만 · 결정되면 DB check 가 거부"
        text ocr_school_text "평문 · 대기 중에만 · OCR 원문이 아니라 학교 이름 목록에 맞은 이름만"
        text previous_school_email "평문 · 선택 입력 · 대기 중에만(≤254자) · claims/blocks 에는 쓰지 않는다"
        bytea document_hmac "문서확인번호 HMAC(graduate-document 접두사) · 승인 때 관리자가 확인한 번호의 해시 · 승인된 행끼리 유일"
        bytea student_hmac "학번 HMAC(graduate-student 접두사 + 학교 id) · 승인 때 관리자가 입력했을 때만 · 승인된 행끼리 유일 · 탈퇴 재가입 제한에 사용"
        smallint key_version "not null · 기본 1 · identity_hmac_key 버전"
        uuid university_id FK "승인 때 관리자가 정한 학교 · on delete restrict"
        timestamptz consented_at "not null · 기본 now() · 신청 화면 동의 줄(D11)"
        uuid decided_by "관리자 auth id · FK 없음(admin_actions 와 같음)"
        timestamptz decided_at "승인 반려 취소 시각"
        timestamptz created_at "not null"
    }

    school_email_claims {
        bytea school_email_hmac PK "2026-10-09 적용 · 학교 메일 HMAC(FastAPI 계산) · 주소는 저장 안 함"
        uuid university_id FK "not null · on delete restrict · 인덱스"
        uuid profile_id FK, UK "not null · 계정당 1개 · on delete cascade"
        text provider "not null · kakao google apple email(check) · email=소셜 전 OTP 가입 기존 계정"
        smallint key_version "not null · 기본 1 · 같은 버전끼리만 대조"
        timestamptz verified_at "not null · 기본 now()"
    }

    profile_private {
        uuid profile_id PK, FK "조각1"
        bytea real_name_enc "2026-10-11 적용 · 민감 · 실명 pgcrypto 암호문(3b 입력 · 학생증 이름 대조 · 본인만 16e 조회) · 키 PHONE_ENCRYPTION_KEY · grant 없음 · 2026-10-12 M2 뒤 실명의 유일한 저장소"
        bytea phone_number "조각2 · 민감 · 04-1 · pgcrypto 암호문(2026-09-29 표기 정정, 종전 text)"
        bytea phone_hmac "조각6 적용 · 민감 · 지인 차단 · 추천 같은 번호 대조 · 유니크 안 검(검토5 해결)"
        smallint phone_hmac_key_version "조각6 적용 · 기본 1 · 같은 버전끼리만 대조"
        bytea kakao_id_enc "2026-10-11 적용 · 민감 · 카톡 아이디 pgcrypto 암호문(04-1b 필수 입력 · 신뢰 확인 통과 후 상대에게만 · 주인이 withdrawn 이면 주지 않음) · 키 PHONE_ENCRYPTION_KEY · grant 없음 · 2026-10-12 M2 뒤 유일한 저장소"
        timestamptz updated_at
    }

    student_verification_attempts {
        bigint id PK "조각1 · identity"
        uuid profile_id FK "조각1 · cascade"
        text file_path "조각1 · student-id-temp 객체 경로"
        verification_status result "조각1 · 기본 pending · none 불가"
        text reject_reason "조각1 · rejected 일 때 · 30일 기한 만료면 서버 고정 문구(2026-10-11)"
        timestamptz submitted_at "조각1"
        timestamptz reviewed_at "조각1 · 판정 전 null"
    }

    user_consents {
        uuid profile_id PK, FK "가입 동의 2026-09-29 · cascade"
        consent_kind kind PK "terms · privacy 만 받음(09-29)"
        text version PK "YYYY-MM-DD · FastAPI CONSENT_VERSION"
        timestamptz agreed_at "기본 now() · 서버 시각"
    }

    profile_photos {
        uuid id PK "조각0"
        uuid profile_id FK "조각0"
        text storage_path UK "조각0 · profile-photos 비공개 버킷"
        smallint position "조각0 · 0~3 · 최대 4장"
        boolean is_avatar_source "조각2 · 프로필당 1장"
        timestamptz created_at "조각0"
    }

    profile_avatars {
        uuid id PK "조각2 제안"
        uuid profile_id FK
        uuid source_photo_id FK "원본 사진 삭제되면 null"
        text storage_path "변환 결과 · 실패 이력은 null · ready 면 not null(check)"
        avatar_status status "pending ready failed"
        boolean is_fallback "5회 연속 실패 보상으로 넣은 기본 아바타 행이면 true(Part C, 미적용)"
        timestamptz created_at "최신 ready 가 현재 아바타"
    }

    survey_answers {
        uuid profile_id PK, FK "조각2"
        smallint axis PK "1~9 · 2가 낯가림"
        numeric value "5점 · -1 -0.5 0 0.5 1"
        timestamptz answered_at
    }

    profile_vectors {
        uuid profile_id PK, FK "조각3"
        vector(8) self_survey "낯가림 제외 8축 · 가중치 사전 곱셈 · L2"
        numeric shyness_score "낯가림 원값 · 5점"
        vector(512) self_embedding "나는 문장 임베딩 · 학과계열+MBTI+얼굴상인상+자기소개 · 코사인"
        vector(512) want_embedding "원해 문장 임베딩 · 선호얼굴상인상+이런사람이좋아요 · 코사인"
        timestamptz updated_at
    }
```

- `profiles` 폐기 컬럼 — 만들지 않는다: `hide_same_major`(설계 미결27), `ideal_description`(설계 미결33). `looking_for`는 조각0에 만들었다가 "찾는 성별" 폐지(반대 성별 자동 매칭, 2026-09-14 사용자 결정)로 조각2 마이그레이션에서 지웠다 — 조각0 마이그레이션 파일은 고치지 않았다(§12-36 완료)
- `profiles` 행은 FastAPI가 아니라 **`auth.users` INSERT 후 Postgres 트리거(`handle_new_user_profile`)**가 만든다(2026-09-18, FK 순서 문제로 정정 — §11-26). Before User Created 훅 시점엔 `auth.users` 행이 아직 커밋 전이라 거기서 `profiles` insert 를 하면 FK 위반이 난다. 3b의 `profile_private` 가 이 행을 FK로 가리키므로 먼저 있어야 한다. 클라이언트 INSERT는 없다(§2)
  - **2026-10-09 개정(`20261008010000` ⑤)**: 트리거는 **학교를 정하지 않는다.** `raw_app_meta_data.provider = 'email'` 인 계정(학교 메일 인증번호를 받으려고 앱이 잠깐 만드는 임시 계정)은 **프로필을 만들지 않고**, 그 밖의 계정(카카오 · 구글 · 애플, provider 없는 행 포함)은 `insert into profiles (id)` 로 **학교 없는 `pending` 프로필**만 만든다. 학교는 아래 `complete_school_email_verification` 한 길로만 정한다(학교 도메인 구글 계정에 여기서 학교를 채우면 `school_email_claims` 에 메일이 안 남아 "학교 메일 1개 = 계정 1개" 가 깨진다)
- **이 시점에 정해지는 `university_id`(메일 도메인으로) · `status`(`pending`)만 `not null` 이다.** **2026-10-09 개정: `university_id` 도 null 허용이다**(`20261008010000` ①) — 학교 메일 인증 전에는 비어 있고, 이 칸을 읽는 SQL(`match_candidates` · `card_issue_owners` · `region_active_counts` · `home_stats`)은 inner join · `=` 비교라 인증 전 사람은 후보 · 카드 · 사다리 인원 · 학교 목록에서 빠진다. 지금 트리거가 정하는 `not null` 값은 `status`(`pending`)뿐이다. 온보딩(DESIGN 04-1 이후)에서 받는 `nickname` · `gender` · `birth_year` · `height_cm` 는 null 허용이고, 아래 check 로 필수값 없는 `active` 전환을 막는다. 조각 0 계획서 초안처럼 온보딩 컬럼을 `not null` 로 두면 FastAPI insert가 실패한다. **`looking_for` 는 이 check 에서도 조각2 마이그레이션 때 함께 빠졌다**(§12-36)
  `check (status <> 'active' or (nickname is not null and gender is not null and birth_year is not null and height_cm is not null))`
- **`pending` → `active` 는 가입 맨 끝에서 서버가 한 번 바꾼다(2026-10-17, 서버 PR #574 — 2026-10-17 배포 · 리비전 `00083-pwx`. 스키마 변경 없음).** 온보딩 단계 순서에서 아바타 확인(`avatar`)이 자기소개(`bio`) **뒤**로 옮겨져(종전 설문 바로 뒤), 다 끝낸 사람의 확정이 두 곳에서 일어난다: ① 종전대로 `POST /profile-onboarding/bio` 저장 때 다음 단계가 complete 면(아바타가 이미 ready) ② **새로** `GET /profile-onboarding/next-step` 이 complete 를 계산했고 지금 상태가 `pending` 이면. 쓰기는 **조건부 PATCH `status=eq.pending` → `active`** 라 정지(`suspended`) · 탈퇴(`withdrawn`)를 되살리지 않고, 저장과 조회가 겹쳐도 한 번만 바뀐다(`profile_onboarding/repository.py` `activate_profile`). 06-3 저장과 리빌 "확인했어요" 사이의 사람은 `pending` 이라 카드 후보 · 홈 인원 · 코호트 수에 잡히지 않는다(몇 분 차이). 활성화에 붙은 트리거 · 푸시는 없다. 화면 흐름은 `frontend/docs/DESIGN.md` §9 5b · `backend/DEPLOY.md` §4-13
- 가입 나이의 "올해"는 Asia/Seoul 기준이다(UTC 12월 31일 15:00 경계). check 에 `now()` 를 넣지 않고 FastAPI가 검사한다. DB에는 `now()` 없는 정적 범위 check만 둔다
- `profiles` 정적 check(조각 0): `nickname` 한글·영문 2~5자, `birth_year` 1950~2020, `height_cm` 120~230, `preferred_height_min` · `max` 도 120~230 이고 min ≤ max, `admission_year` 1950~2100(두 자리 입력을 그대로 저장하는 실수 방지), `mbti` `^[EI][NS][TF][JP]$`, `preferred_mbti_flags` 는 JSON 객체(키 E I N S T F J P, 값 boolean · true 가 ok, 설계 §6.4 — 기본 `{}` 는 전부 ok 와 같은 결과), `interest_tags` 5개 이하(하한 3개는 FastAPI 온보딩 완료 검사)
- 선호 키·나이 슬라이더(DESIGN `range-slider` 프리셋)의 끝 표기 "150cm 이하" · "190cm 이상" · "35세 이상"은 그쪽 경계를 null 로 저장한다. 끝값 150 을 그대로 저장하면 145cm 상대가 빠진다
- `profiles.university_id` 는 `on delete restrict` — 프로필이 남아 있는 대학은 지울 수 없다. `university_email_domains` 는 대학을 따라 cascade 로 지워진다
- `universities.name` 은 unique 다(시드가 이름으로 도메인을 짝짓는다). `university_email_domains.domain` 은 소문자 도메인 형식 check `^[a-z0-9-]+(\.[a-z0-9-]+)+$`. 도메인 1개는 대학 1개에만 속하고, 서울 밖 캠퍼스도 따로 나누지 않는다(§11-10)
- 조각 4에서 `universities.region_group` 에 `region_group_settings` FK 를 걸 때는 같은 마이그레이션에서 `seoul` 행을 먼저 넣는다
- 민감 값(`real_name` · `phone_number` · `phone_hmac` · `kakao_id`)은 `profile_private` 로 분리했다. 서버 코드가 남의 프로필을 `select *` 로 읽어도 민감 값이 딸려 나오지 않는다. 접근 감사 로그는 테이블 없이 FastAPI 구조화 로그로 남긴다(§11-13). 운영자도 FastAPI 관리 기능으로만 조회하고 Supabase 대시보드·SQL 로 직접 보지 않는다(§11-18)
- **실명 · 카카오톡 아이디 암호화(2026-10-11, M1 `20261011010000` 운영 적용 · PR #464 · #467)** — 전화번호와 같은 `pgp_sym_encrypt` · 같은 키(`PHONE_ENCRYPTION_KEY`, FastAPI Secret Manager 전용)로 `real_name_enc` · `kakao_id_enc`(`bytea`)에 둔다. 함수 4개 `set_real_name` · `set_kakao_id` · `decrypt_profile_private` · `backfill_profile_private_encryption`(임시) — 전부 security invoker, `service_role` 만 실행, 키는 RPC JSON 바디로만(세부 `docs/SUPABASE.md` §8). 지금은 **이중 쓰기 기간**이라 서버가 평문 · 암호문 둘 다 쓰고, 값을 내려줄 때는 복호화 값을 먼저 쓰고 비면 평문으로 폴백한다(온보딩 진행 판단만 평문 먼저, `docs/SUPABASE.md` §8). 옛 행은 백필로 채웠다(2026-10-12, 2행 · 불일치 0). **M2(평문 `real_name` · `kakao_id` 열과 백필 함수 삭제)는 아직** — 하네스 · 서버의 평문 사용을 뺀 뒤 사용자 승인으로 적용한다(`backend/DEPLOY.md` §4-4)
- **M2 운영 적용(2026-10-12, `20261012010000` · 운영 기록 버전 `20261012070722` · 파일은 PR #476 merge 대기, ERD_DECISIONS §11-30)** — 위 줄의 "이중 쓰기 기간" · "M2 는 아직" 은 이날로 끝났다. 평문 열 `text real_name`(조각 1) · `text kakao_id`(조각 2)를 지워 위 그림에서도 뺐고, 그 설명(3b 입력 · 학생증 이름 대조 · 본인만 16e 조회 / 04-1b 필수 입력 · 신뢰 확인 통과 뒤 상대에게만 · 주인이 `withdrawn` 이면 주지 않음)은 암호문 열 줄로 옮겼다. 함수는 `set_real_name` · `set_kakao_id` · `decrypt_profile_private` 셋만 남았다. 서버(리비전 `00063`, PR #474)는 복호화로만 읽고 실패를 오류로 올린다(`docs/SUPABASE.md` §8). `authenticated` 의 `select (real_name)` 컬럼 grant 는 열과 함께 사라졌다. 되돌릴 수 없다 — 롤백 마이그레이션 · 사용자 백업 없음(`backend/DEPLOY.md` §4-4)
- `student_verification` 은 boolean이 아니라 상태값(`none` `pending` `verified` `rejected`, 2026-09-14 확정)이다. 3b의 "조금 더 확인이 필요해요" 대기 상태를 담아야 하기 때문이다
- `student_verification_attempts` 는 학생증 제출 한 번에 한 행이다(§12-4, 2026-09-14 사용자 결정). 재시도 횟수(설계 미결3)는 이 테이블의 행 수로 FastAPI 가 세고, 반려 사유(`reject_reason`)는 본인에게 FastAPI 응답으로 내려준다. `result` 는 제출 직후 `pending` 이고 `none` 일 수 없다(check). 클라이언트 권한은 없다(§2). **`verified` 확정 후 재제출은 FastAPI 가 막는다(409, 2026-09-20 결정)** — `rejected` 는 계속 재제출 가능. **검토 대기 상한 30일(2026-10-11 사용자 결정, PR #463)** — `submitted_at` 이 30일 지났는데 `result = pending` 인 행은 매시 `chat-gate` 배치가 `rejected` · `reject_reason` "검토 기한이 지나 사진을 삭제했어요. 학생증을 다시 올려 주세요" · `reviewed_at` 으로 닫고, 그 행이 그 사람의 최근 제출이면 `profiles.student_verification` 을 (`pending` 일 때만) `rejected` 로 바꾼다. 검토 결과 훅은 이 사유 문구로 "기한 만료" 알림을 고른다(`app/student_verification/retention.py` · `review_hook.py`). 스키마 변경은 없다. **2026-10-17 사용자 결정으로 학생증 · 졸업증명서 사진 인증 단계를 없앴다(서버 PR #582 · 앱 PR #583 — 위 문장들은 기록으로 남긴다): 이 표 · `profiles.student_verification` · `profile_private.real_name_enc`(더는 받지 않음) · 버킷 `student-id-temp` 는 데이터만 남기고 흐름만 껐으며 정리는 출시 후다(출시후_할일 1-1). `GET /me/verification-status` 의 `status` 는 옛 앱 호환으로 늘 `verified` 를 내려준다.** 같은 해 10-19 에 **졸업생 길만** 새 표 `graduate_verification_requests` 로 되살렸다(아래, 옛 표를 재사용하지 않았다)
- **`profiles.department` 컬럼은 만들지 않는다(2026-09-20 결정)** — 학과는 기존 `major` 컬럼을 재사용하고, FastAPI 응답에서만 `department` 로 별칭한다. 학번은 `student_number` 컬럼을 새로 추가했다(설계 §7.3, 마이그레이션 `20260919181319`)
- **`profiles.bio_draft` · `bio_draft_generated_at`**: AI 자기소개 초안은 최초 1회만 생성한다. `bio_draft_generated_at` 이 이미 있으면 재호출 시 재생성하지 않고 저장된 `bio_draft` 값을 그대로 반환한다(설계 §13-71)
- **`profiles.ideal_note`**: 빈 문자열이면 "미입력"으로 취급한다. 매칭 임베딩("원해" 문장, 설계 §6.3) 계산에서는 빈 문자열을 "없음"으로 처리한다
- **`graduate_verification_requests`(2026-10-19 운영 적용, `20261019200000` · `20261019200100`, PR #615, 결정 배경 `docs/decisions/2026-10-19-graduate-verification-decision.md`)** — 학교 메일이 없는 졸업생이 졸업증명서 사진으로 인증받는 길의 신청 기록이다. 승인되면 **학교 메일 인증과 같은 두 칸**(`profiles.university_id` · `school_email_verified_at`)을 채워 학과 입력 · 온보딩 · 매칭이 코드 변경 없이 두 길을 같게 다룬다(`graduate_verified_at` · `verification_method` 는 내부 칸). **사진과 평문(`ocr_document_number` · `ocr_school_text` · `previous_school_email`)은 결정(승인 · 반려 · 취소 · 만료)을 한 순간 지운다** — 남는 것은 학교 · 결정 · 시각 · 해시뿐이고 이름 · 생년월일 · 학번 평문은 어디에도 저장하지 않는다. 이를 DB 가 지킨다:
  - check `graduate_requests_state_pairs`(상태별로 있어야 할 것 · 없어야 할 것 — pending 은 `photo_path` 필수 · 결정 칸 비어 있음, approved 는 `university_id` · `document_hmac` · `decided_*` 필수, rejected 는 사유 4개 중 하나, cancelled 는 취소 이유 4개 중 하나 + `decided_by` 없음) · `graduate_requests_no_plaintext_after_decision`(**결정된 줄에 평문 세 칸이 있으면 거부**) · `graduate_requests_student_hmac_only_approved` · `ocr_state` 3값 · `previous_school_email` ≤ 254자
  - 유일 인덱스: 프로필당 대기 1건 `graduate_requests_one_pending_key` · **승인된 줄끼리 같은 `document_hmac`**(같은 증명서를 두 계정에) · **같은 `student_hmac`**(같은 사람이 두 계정에)을 막는다. 반려 · 취소된 줄은 해시가 겹쳐도 된다. 보조 인덱스 3개(대기 오래된 순 · 프로필별 최근 순 · `university_id`).
  - 해시는 `identity_hmac_key` 로 만들되 입력 앞에 이름공간 접두사(`graduate-document` · `graduate-student` + 학교 id)를 붙여 학교 메일 해시와 겹치지 않는다. 학번 해시는 탈퇴 때 `signup_blocks` 에 같은 자리로 넘어가 재가입 제한(2개월 · 정지 중 탈퇴는 무기한)에 쓰인다. 학번은 공간이 작아 키가 새면 역산될 수 있다(전화번호 해시와 같은 위험).
  - 함수 `admin_review_graduate_request(p_admin, p_request, p_status, p_reason, p_university, p_document_hmac, p_student_hmac, p_key_version, p_ip) → jsonb`: 관리자 확인 → 신청 줄 잠금 → 프로필 잠금 → (승인) 학번 해시 재가입 제한 확인 → 신청 줄 갱신(평문 비움) → 프로필 두 칸 + 졸업생 칸 → `admin_actions` 한 줄(해시 · 번호 없음)을 **한 트랜잭션**에. 오류: 22023 규칙 위반 · 42501 관리자 아님 · CM404 없음 · CM409(`already_reviewed` · `already_verified` · `account_withdrawn` · `document_reused` · `student_reused` · `rejoin_blocked`). `list_unverified_accounts` 도 교체해 **대기 신청이 있거나 14일 안에 결정된 신청이 있는 프로필을 14일 정리 후보에서 뺀다**(관리자 제외는 그대로). 모두 `security invoker` · `service_role` 만 실행.
  - 시도 횟수는 사람당 3회(서버 상수, 만료로 닫힌 것은 세지 않는다), 대기 상한 14일(서버 매시 배치가 `cancelled(expired)` 로 닫는다). 클라이언트는 이 표를 읽지 못한다(§2).
- **`admin_users` · `admin_actions` · `unknown_email_domain_attempts`(2026-10-17 ~ 18 운영 적용)** — 관리자 웹용 두 표와 가입 거절 도메인 표의 설명은 §7.
- `profile_photos` 장수 2~4장: 상한은 `position` 범위로, 하한은 FastAPI 온보딩 완료 검사로 막는다
- `profile_photos` 는 `unique (profile_id, position) deferrable initially deferred` — 순서를 맞바꿀 때 중간 충돌을 피한다. `storage_path` 는 unique — 두 행이 같은 파일을 가리키면 한 행을 지울 때 남은 행의 사진도 사라진다
- `profile_photos.is_avatar_source` 는 부분 유니크 인덱스 `(profile_id) where is_avatar_source` 로 1장만 허용
- **아바타 원본으로 고른 사진도 신뢰 확인을 통과하면 다른 실사진과 함께 공개한다**(§11-5). 어느 사진이 원본인지는 상대에게 드러내지 않는다
- `profile_avatars.storage_path` 는 null 허용이고 경로가 진짜로 필요한 행만 `check (status <> 'ready' or storage_path is not null)` 으로 묶는다(마이그레이션 `20260924163241`, 2026-09-25 사용자 결정 A). 생성 실패 행에는 저장할 경로가 없는데 not null 이라 실패 이력이 한 줄도 안 쌓였고, 그래서 "5회 연속 실패 → 기본 아바타 + 하트 10" 이 걸리지 않았다(운영 00018-pxb). 읽는 쪽은 예전부터 `status = ready` 행만 골라 쓰므로(카드·채팅의 아바타 URL) 경로가 null 인 행이 화면으로 새지 않는다
- `profile_avatars` 의 부분 유일 인덱스 둘(2026-10-20 정정 — 종전 "(미적용, Part C)" 서술은 낡았다): **`profile_avatars_one_pending`**(`(profile_id) where status = 'pending'`, 마이그레이션 `20260926005519_avatar_async_generation`)은 한 사람에게 `pending` 행을 한 줄만 허용해 중복 누름 · 워커 재시도가 겹쳐도 두 번째 insert 가 23505 로 튕긴다. `is_fallback` 칸(같은 마이그레이션)은 5회 연속 실패 보상 행을 정상 생성 결과와 구분해 결과 화면 안내를 고른다. **`profile_avatars_one_fallback`**(`(profile_id) where is_fallback`, `20261018100000`)은 기본 아바타 행을 한 사람에 한 줄로 막아 보상 하트 10 이 두 번 나가는 경쟁을 끊는다(§7). 두 인덱스 모두 운영에 적용돼 있다(운영 96개 = 저장소 96개)
- `profile_vectors` 는 벡터 2종(§6.3)을 한 행에 둔다(1:1)
- 벡터 확장(`vector`)은 조각 0 첫 마이그레이션에서 `extensions` 스키마에 켰다. 조각 3에서 벡터 컬럼을 만들 때는 타입을 `extensions.vector` 로 쓰거나 `search_path` 에 `extensions` 가 있는지 확인한다
- **탈퇴는 30일 뒤에 지운다(§11-15).** 탈퇴하면 FastAPI 가 `status = withdrawn` · `withdrawn_at` 을 쓰고, 세션을 끊고 다시 로그인하거나 토큰을 갱신하지 못하게 막는다(Supabase Auth ban 전제, 토큰 갱신까지 막히는지는 조각 6에서 확인). 이미 발급된 access token 은 만료(`jwt_expiry`)까지 살아 있어 그동안 RLS 로 본인 행은 읽힌다. 본인 데이터라 RLS 에 status 조건은 넣지 않는다. `withdrawn` 계정의 요청은 FastAPI 가 받지 않는다
  - 즉시 빠지는 곳: `active` 가 아니므로 카드 · 받은 수락함 · 매칭 생성 · 투표 글 · 투표 집계 · 지인 리뷰 노출에서 빠진다. `push_tokens` 는 탈퇴 즉시 지운다
  - 게이트: 상대가 `withdrawn` 이면 게이트를 통과시키지 않는다. 이미 통과한 매칭에서도 탈퇴자의 `kakao_id` 와 실사진 서명 URL 은 더 주지 않는다
  - 남은 상대: 게이트를 통과한 매칭은 30일 동안 채팅을 읽고 신고할 수 있고, 메시지는 보낼 수 없다. 통과하지 않은 매칭은 기존 규칙대로 48시간 기한에 게이트 실패로 채팅이 지워져, 그때까지만 읽기·신고가 된다
  - 추천: 탈퇴자의 `referral_code` 는 받지 않는다(없는 코드로 처리). 피추천인이 학생증을 통과해도 탈퇴한 추천인 몫 50하트는 주지 않고, 월간 추천 랭킹 보상에서도 뺀다
  - 알려진 한계: 30일 동안 탈퇴자의 닉네임(lower unique)과 `referral_code` 는 점유된 채로 남는다
  - 30일 뒤 FastAPI 가 Storage 파일을 지운 뒤 `auth.users` 를 지우고, 나머지 행은 §2 FK 규칙대로 지워진다. 학생증 사진(`student-id-temp`)만 30일을 기다리지 않고 탈퇴 즉시 지우고, `profile_private` 는 30일 보관한다(§11-19). 30일 뒤 삭제는 Auth 관리 API 의 하드 삭제여야 한다. 소프트 삭제(`shouldSoftDelete`)는 `auth.users` 행이 남아 cascade 가 돌지 않는다(조각 6에서 확인). 탈퇴는 되돌릴 수 없다(§11-21)
- 조각 6 마이그레이션: `alter type public.profile_status add value 'withdrawn'` 로 넣은 값은 그 트랜잭션이 커밋된 뒤에야 쓸 수 있다. `withdrawn` 을 쓰는 check(후보 `(status = 'withdrawn') = (withdrawn_at is not null)`)·인덱스는 다음 마이그레이션 파일로 나눈다
- 30일 뒤 `profiles` 가 `on delete cascade` 로 지워져도 Storage 파일은 지워지지 않는다. 사진(`profile-photos`)·아바타(`avatars`)·무료 하트 인증샷(`heart-task-proofs`) 파일 삭제는 FastAPI 몫. 검증이 끝나지 않은 학생증 사진(`student-id-temp`)은 탈퇴 즉시 FastAPI 가 지운다(§11-19)
- **`user_consents`(가입 동의, 2026-09-29 적용 — 운영 기록 `20260929051356`)**: 항목 × 판마다 한 행, PK `(profile_id, kind, version)`, `version` 은 `YYYY-MM-DD` check, `agreed_at` 은 서버 시각. FastAPI 전용이고 **`service_role` 도 `select` · `insert` 만** — 동의 기록은 고치지 않는다(§2 예외). 탈퇴 계정 삭제 때 cascade. **`kind` enum 의 `sensitive_religion` · `overseas_transfer` 값은 남겨 두지만 쓰지 않는다**(2026-09-29 4칸 결정: 필수 = `terms` · `privacy`, 선택 = 마케팅 — 마케팅은 이 표가 아니라 `notification_settings.marketing`). 운영에 적용된 enum 이라 값을 지울 수 없어 남긴다(§8). 종교는 개인정보 수집·이용 동의 안에, OpenAI 국외 이전은 처리방침 공개로 대신한다(설계 §7.8)
- **`universities.card_opens_at`(코호트, 2026-09-28 적용)**: null 이면 이미 열린 학교(지금 학교 전부). 값이 있으면 check `universities_card_opens_monday_0700` 가 **서울 월요일 07:00 · 유한 값**만 받는다. `match_candidates` · `card_issue_owners` · `region_active_counts` 가 "열림 = null 이거나 지남" 조건 한 줄씩을 더했다(시그니처 그대로 `create or replace`). `universities` 는 `anon` 까지 읽기라 여는 시각도 공개된다. **2026-10-20 데이터 입력**(`20261020110000_close_seoul_schools_until_cohort_open`, 사용자 결정): `region_group = 'seoul'` 이고 `card_opens_at is null` 인 학교 64곳에 `2026-11-02 07:00 KST` 를 넣었다(이미 날짜가 있으면 건드리지 않아 다시 돌려도 같다). 시험 학교(`region_group = 'e2e'`, 심사 계정 소속) 1곳은 일부러 비워 두어 열린 채다 — 심사원이 오픈 대기 화면이 아니라 전체 기능을 본다. 종전 제안 `recruit_starts_at` 은 **만들지 않는다**(학교 행을 넣는 순간이 모집 시작)
- **`profiles.referral_code`(2026-09-28 적용)**: `generate_referral_code()` 기본값 · unique · check `^[A-HJ-NP-Z2-9]{6}$`, 기존 행도 채웠다. 정지 · 탈퇴한 사람의 코드는 없는 코드로 처리한다
- **`profiles.school_email_verified_at`(소셜 로그인, 2026-10-09 운영 적용 — `20261008010000`)**: null = 학교 메일 인증 전. 소셜 가입 때 GoTrue 가 채우는 `auth.users.email_confirmed_at` 은 학교 메일 증거로 쓰지 않고 이 칸만 본다. check **`profiles_verified_requires_university`** `(school_email_verified_at is null or university_id is not null)` — "인증했는데 학교 없음" 반쪽 상태를 막는다. 부분 인덱스 **`idx_profiles_unverified_created_at`** `on profiles (created_at) where school_email_verified_at is null` — 정리 배치가 "인증 전 + 오래된 순" 으로 읽는다. 같은 파일이 기존 행(학교 있는 행)을 `school_email_verified_at = created_at` 으로 채웠다(상태줄 "데이터 이전")
- **`school_email_claims`(학교 메일 1개 = 계정 1개, 2026-10-09 운영 적용 — `20261008030000` ⑦)**: 지금 그 학교 메일을 쓰는 계정. PK `school_email_hmac`(FastAPI 가 계산한 HMAC 만 — DB 에서 계산하면 키가 Postgres 에 들어온다), `university_id` FK `on delete restrict` + 인덱스 `school_email_claims_university_id_index`, `profile_id` **unique** FK `on delete cascade`(인증 뒤 메일 변경 불가), `provider` check `kakao` `google` `apple` `email`(`email` = 소셜 로그인 전에 학교 메일 OTP 로 가입한 기존 계정, 백필 스크립트가 넣는다), `key_version` 기본 1(행마다 키 버전, 대조는 같은 버전끼리), `verified_at` 기본 `now()`. **RLS 켬 · 정책 없음**, `revoke all ... from anon, authenticated, service_role` 뒤 `service_role` 에만 `select` · `insert` · `update` · `delete`. 탈퇴 뒤 재가입 제한은 `signup_blocks` 가 따로 맡는다 — 탈퇴 30일 뒤 `auth.users` 가 지워지면 이 행도 cascade 로 지워져 그 메일을 다시 쓸 수 있다
- **트리거 `scrub_social_identity_names`(2026-10-09 운영 적용 — `20261008020000` ⑥)**: `auth.users`(`before insert or update of raw_user_meta_data`) · `auth.identities`(`before insert or update of identity_data`) 두 곳에 같은 이름으로 건다. 소셜 제공자가 넣는 이름 · 사진을 저장 전에 지운다 — 지울 키가 아니라 **남길 키 6개만** 적는다: `email` · `sub` · `provider_id` · `iss` · `email_verified` · `phone_verified`. 객체가 아닌 값은 건드리지 않는다. 함수는 security invoker, `anon` · `authenticated` 실행 권한 회수. auth 스키마 표에 거는 트리거라 Supabase 업그레이드 뒤 남아 있는지 다시 본다
- **DB 함수(2026-10-09 운영 적용 — `20261008030000`)** — 둘 다 security invoker, `public` · `anon` · `authenticated` 회수, `service_role` 만 실행
  - `list_unverified_accounts(p_older_than_days integer, p_limit integer default 100) returns table (id uuid)` — 학교 메일 인증 전(`school_email_verified_at is null`)이고 `p_older_than_days` 일이 지난 프로필 id 를 오래된 순 `p_limit` 개. 둘 중 하나라도 null 이거나 1 미만이면 22023 오류. 고르기만 하고 지우는 것은 FastAPI 가 auth 관리자 API 로 한다(정리 배치, 14일). email 방식 임시 계정은 프로필이 없어 여기 나오지 않는다
  - `complete_school_email_verification(p_profile uuid, p_email_hmac bytea, p_university uuid, p_provider text, p_key_version smallint default 1) returns text` — claims 기록과 프로필의 학교 · 인증 시각을 한 트랜잭션에 쓴다(프로필 행 `for update` 잠금, 같은 메일 동시 호출은 `on conflict do nothing`). 돌려주는 값: `ok` = 기록함(같은 계정 · 같은 메일로 다시 불러도 `ok`, 멱등) / `kakao` · `google` · `apple` · `email` = 그 메일을 다른 계정이 쓰고 있다, 그 계정의 가입 방식(아무것도 안 바꿈) / `already_verified` = 이 계정은 이미 인증함(인증 시각이 있거나 claims 행이 있음, 인증 뒤 변경 금지) / `no_profile` = 프로필 없음. 가입 방식이 넷 밖이면 23514

## 4. 카드 · 매칭 · 채팅 (조각 4~5)

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    profiles ||--o{ daily_cards : "owner_id"
    profiles ||--o{ daily_cards : "target_id"
    daily_cards ||--o| card_decisions : "결정 1회"
    card_decisions ||--o| acceptance_responses : "accept 일 때 상대 응답"
    profiles ||--o{ acceptance_responses : "responder_id"
    profiles ||--o{ matches : "profile_a"
    profiles ||--o{ matches : "profile_b"
    matches ||--|{ match_participants : "당사자 2행"
    profiles ||--o{ match_participants : "profile_id"
    matches ||--o{ messages : "대화"
    profiles ||--o{ messages : "sender_id"
    profiles ||--o{ push_tokens : "기기"
    profiles ||--o| notification_settings : "16d"
    profiles ||--o{ pending_pushes : "밤 알림 보류"
    profiles ||--o{ notifications : "알림함"
    profiles ||--o{ paid_card_offers : "owner_id"
    profiles ||--o{ paid_card_offers : "target_id"
    daily_cards |o--o{ paid_card_offers : "purchased_card_id"

    daily_cards {
        uuid id PK "조각4"
        uuid owner_id FK "받은 사람"
        uuid target_id FK "카드 속 상대"
        card_source source "daily purchased"
        timestamptz issued_at
        timestamptz expires_at "제안 · daily는 다음 지급 · purchased는 null"
    }

    card_decisions {
        uuid card_id PK, FK "조각4"
        card_decision decision "accept reject"
        timestamptz decided_at
    }

    acceptance_responses {
        uuid card_id PK, FK "조각4 제안 · A가 accept 한 카드"
        uuid responder_id FK "받은 수락함 주인 B"
        card_decision decision "B가 고른 값 · 거절 행도 신청자의 보낸 신청 목록에 쓰인다 2026-10-13"
        timestamptz decided_at
    }

    matches {
        uuid id PK "조각4"
        uuid profile_a FK "profile_a 가 profile_b 보다 작다"
        uuid profile_b FK
        timestamptz created_at "게이트 시계 시작 · 기한은 +48시간"
        timestamptz trust_passed_at "조각5 · 양쪽 수락 순간 · 둘 다 아는 사실"
        timestamptz chat_closed_at "조각5 · 기한 도달 시에만 · 한쪽이 나간 방은 안 닫는다"
    }

    match_participants {
        uuid match_id PK, FK "조각4"
        uuid profile_id PK, FK "조각4 · 본인 행만 조회"
        trust_response trust_response "조각5 · accept 또는 null · 거절은 left_at 으로 남는다"
        timestamptz responded_at "조각5"
        timestamptz left_at "조각5 · 채팅방 나가기(게이트 거절 포함) · 상대에게 시스템 줄로 보인다"
        timestamptz last_read_at "조각5 · 방 진입·이탈 · 보는 중 받은 줄 3초 묶음 · 상대 화면 읽음 1 의 기준(10-13 개정, 종전 상대에게 비공개)"
    }

    messages {
        uuid id PK "조각5"
        uuid match_id FK
        uuid sender_id FK
        text kind "text 말풍선 · left 나감 · trust_accept 수락 · 기본 text"
        text body "텍스트만"
        timestamptz created_at
    }

    push_tokens {
        text token PK "조각4 · FCM"
        uuid profile_id FK
        device_platform platform "android ios"
        timestamptz updated_at
    }

    notification_settings {
        uuid profile_id PK, FK "조각4 제안"
        boolean card_arrived
        boolean acceptance_received
        boolean match_made
        boolean new_message
        boolean trust_reminder
        boolean new_friend_review
        boolean marketing "기본 false"
        timestamptz marketing_consented_at "제안 · 수신 동의 시각"
        boolean quiet_hours "22시~8시 · 기본 false(2026-10-19 개정, 종전 true) · 새 가입자는 꺼진 채 시작 · 설정 행이 없던 기존 사용자는 마이그레이션이 true 행으로 채워 켜진 채 유지"
    }

    pending_pushes {
        uuid id PK "결정4 · 2026-10-03 제안"
        uuid profile_id FK "on delete cascade"
        text kind "acceptance_received match_made new_friend_review verification_result"
        text title "원래 알림 그대로"
        text body
        jsonb data "route 등"
        timestamptz created_at
    }

    paid_card_offers {
        uuid id PK "2026-10-10 운영 적용"
        uuid owner_id FK "on delete cascade · 살 사람"
        timestamptz cycle_started_at "이 제안이 속한 카드 주기의 시작 시각"
        uuid target_id FK "on delete cascade · 열릴 상대"
        jsonb reasons "맞는 이유 태그 최대 3개 · 기본 빈 배열"
        integer band_count "뽑을 때의 후보 폭 · check 1 이상"
        paid_card_offer_status status "offered purchased replaced expired · 기본 offered"
        uuid purchased_card_id FK "daily_cards · on delete set null · check status=purchased 일 때만"
        timestamptz created_at
    }

    notifications {
        uuid id PK "2026-10-10 운영 적용"
        uuid profile_id FK "on delete cascade"
        text kind "card_arrived chat_request match_made friend_review verification_result night_digest"
        text title
        text body
        jsonb data "푸시 data 와 같은 모양 · 기본 빈 객체"
        timestamptz created_at
        timestamptz read_at "null=안 읽음"
    }
```

- `matches` 는 `unique (profile_a, profile_b)` + `check (profile_a < profile_b)`
- **당사자별 값은 `match_participants` 에 둔다.** `matches` 행은 두 사람이 다 읽으므로, 사람마다 다른 값(응답 시각·읽음·나간 시각)을 거기 두면 상대 것까지 딸려 보인다
- **게이트 동작은 전부 상대에게 보인다(2026-09-22 사용자 결정 10·11).** 수락하면 `messages` 에 `kind='trust_accept'` 시스템 줄이, 나가면 `kind='left'` 시스템 줄이 남는다. 거절은 따로 저장하지 않는다 — **거절은 곧 채팅방 나가기**라서 `trust_response` 에는 `accept` 아니면 null 만 들어간다. 수락은 매칭 순간부터 할 수 있고 양쪽이 수락하면 48시간 전이라도 그 자리에서 공개된다
- 게이트 판정(설계 §2.5): 기한(`created_at` + 48시간) 전에 양쪽이 accept → FastAPI가 `trust_passed_at` 기록 + 카카오톡 아이디 공유 + 실사진 공개. 기한까지 `trust_passed_at` 이 없으면 그때 `chat_closed_at` 을 기록하고 채팅을 닫는다
- **`chat_closed_at` 은 기한이 됐을 때만 기록한다.** 단 **한쪽이라도 나간 매칭은 아예 닫지 않는다** — 닫을 사람이 없는데 닫으면 남은 사람의 지난 대화만 목록에서 사라진다. 닫는다는 것은 이 칸 하나를 찍는 것뿐이고 메시지는 지우지 않는다(조각 7 "잠긴 방"이 다시 쓴다)
- 채팅방의 "신뢰 확인 완료" 카드(`trust-reveal-bubble`)는 메시지 행이 아니라 `matches.trust_passed_at` 으로 그린다
- **읽음은 메시지가 아니라 `match_participants.last_read_at` 에 둔다.** `messages.read_at` 은 두 사람이 다 읽으므로, 상대가 조용히 나가면 내 메시지가 계속 안 읽힘으로 남아 나가기가 드러난다. 안 읽은 수는 상대가 보낸 메시지 중 `created_at` > 내 `last_read_at` 이고, 갱신은 메시지마다가 아니라 방에 들어올 때와 나갈 때 한 번씩이다(나갈 때도 갱신해야 방 안에서 받은 메시지가 안 읽음으로 남지 않는다). 상대에게 보이는 읽음 표시는 없다
  - **2026-10-13 사용자 결정으로 개정, 종전 "상대에게 보이는 읽음 표시는 없다" · "갱신은 방에 들어올 때와 나갈 때 한 번씩"(서버 PR #501 · 앱 PR #505 · 실시간 PR #508 · #510 — DB 변경 없음).** 카톡식 **안 읽음 '1'** 을 둔다 — 내가 보낸 사람 글 줄(`kind = 'text'`) 가운데 `created_at` > 상대 `last_read_at` 인 줄에 '1' 이 붙고 상대가 읽으면 사라진다(시스템 줄 · 상대 줄 · 상대가 나간 방에는 없다, 화면은 DESIGN §8.6). 읽음을 메시지가 아니라 `last_read_at` 에 두는 이유(위 문장)는 그대로다
  - **갱신 시점(`PATCH /chat/matches/{id}/read` → 서버 `touch_read`)**: 방에 들어올 때 · 나갈 때 + **방을 보는 동안 받은 상대 줄을 3초 묶음으로**(첫 줄은 바로 찍고, 3초 안에 더 온 줄은 끝에 한 번 더 — 앱 `markReadThrottle`). 앱이 뒤로 가거나 다른 화면이 방을 덮으면 찍지 않는다
  - **상대 값은 응답 키 `partner_last_read_at` 으로만 간다** — 방 머리말 `GET /chat/matches/{id}` 와 메시지 목록 `GET /chat/matches/{id}/messages`(`limit` 과 무관하게 늘 실린다, 상대가 한 번도 안 읽었으면 null). `match_participants` 는 여전히 본인 행만 읽는다(§2) — 상대 행을 여는 RLS · `security definer` 는 만들지 않았다. 읽음을 찍은 직후 서버가 상대 한 사람의 사용자 채널(`user:<상대 id>`, §2 `realtime.messages`)로 `read` 이벤트를 쏴 '1' 을 바로 지운다
  - **푸시 30초 규칙(`chat/router.py` `IN_ROOM_WINDOW` — 상대 `last_read_at` 이 30초 안이면 새 메시지 푸시를 건너뛴다)은 그대로다.** 다만 방을 보는 동안 받은 줄마다 읽음이 다시 찍혀 30초 창이 이어지므로, 대화가 오가는 동안에는 푸시가 가지 않는다(종전에는 방에 들어온 뒤 30초까지만). 말이 30초 넘게 끊긴 뒤 온 첫 줄은 푸시가 나가지만, 안드로이드 앱이 지금 그 방을 보고 있으면 앞 화면 알림을 건너뛴다(iOS 는 못 막는다, DESIGN §8.8 알림)
- **보낸 신청(2026-10-13, 서버 PR #483 `GET /cards/sent` — DB 변경 없음, 마이그레이션 0건)**: 신청자 A 가 자기 `card_decisions`(accept)와 B 의 `acceptance_responses` 를 읽어 상태를 만든다 — 매칭 행이 있으면 `matched` > B 의 응답이 reject 면 `rejected`(accept 면 `matched`) > 기한(`decided_at` + 7일)이 지났으면 `expired` > 아니면 `waiting`. **그래서 거절 행(`acceptance_responses.decision = reject`)은 하드 필터용 기록일 뿐 아니라 신청자에게 보이는 데이터다**(설계 문서 §2.2 개정). 끝난 뒤(거절 · 만료 · 성사) 7일이 지나면 목록에서만 빠지고 행을 지우는 규칙은 새로 두지 않았다(서버 조회 조건 `SENT_RETENTION_DAYS`). 상대가 차단 · 정지 · 탈퇴 · 가림이거나 매칭 뒤 어느 쪽이든 방을 나갔으면 이유를 가르지 않고 목록에서 뺀다
- 수락이 겹치는 경로 두 가지: A의 카드에서 A accept → B가 받은 수락함에서 응답(`acceptance_responses`), 또는 서로의 카드에서 둘 다 accept. 어느 쪽이든 양쪽 accept 가 되면 FastAPI가 `matches` 와 `match_participants` 2행을 만든다
- **하드 필터 "이미 카드로 받은 사람"의 정의(§11-4, 설계 §6.7)**: 내가 결정한 카드의 상대(`card_decisions`) + 받은 수락함에서 응답한 상대(`acceptance_responses`) + 매칭 이력이 있는 상대(`matches`, 게이트 실패 포함) + 아직 만료되지 않은 카드의 상대. **무응답으로 만료된 무상 카드의 상대는 다시 나올 수 있다.** **실제 동작(2026-09-21 사용자 확정, `20260928050000` `match_candidates`)은 영구 제외가 아니라 쉬는 기간이다**: 결정한 카드의 상대는 결정 후 90일, 무응답 만료 카드의 상대는 만료 후 14일, 내가 수락 응답을 한 상대도 90일 쉬고, **매칭된 상대만 영구 제외**다. 그래서 `daily_cards (owner_id, target_id)` 는 unique가 아니라 일반 인덱스다. **2026-10-10 개정(`20261010010000`, 운영 적용): 위 "쉬는 중" 사람은 이제 후보에서 빠지지 않고 `pickable = false` 로 함께 나온다**(결정 전 카드 — 구매 카드 포함 — 와 매칭된 상대도 같다). 순위는 쉬는 사람까지 포함한 전체 후보로 매기고 뽑을 때만 `pickable` 을 본다(서버 `backend/app/matching/band.py`). 하드 필터(이성 · 같은 지역그룹 · 열린 학교 · active · 접속 15일 · 일시중지 · 자동 가림 · 차단 · 지인 차단 · 벡터 있음)에 걸린 사람은 종전대로 행 자체가 없다. 함수 반환이 `table(...)` 에서 **jsonb 배열 한 덩어리**로 바뀌어(`drop` 뒤 `create`, 호출 주소는 그대로) PostgREST 가 행 집합을 1,000행에서 자르던 상한이 사라졌다 — 후보가 없으면 null 이 아니라 `[]` 다
- **`pending_pushes`(밤 알림 보류, 결정 4 · 2026-10-01 사용자 — 2026-10-03 제안, 운영 미적용)**: 조용한 시간(22~08시)에 걸린 받은 수락 · 매칭 · 지인 리뷰 · 학생증 검토 결과(A7) 알림을 버리지 않고 원래 제목 · 본문 · `data` 그대로 한 행씩 넣는다(`app/cards/push.py` `notify`). 매시 chat-gate 배치가 조용하지 않은 시각(08~21시)에 돌면 사람 × 가는 화면(`data.route`)으로 묶어 보내고 지운다 — 1건이면 원래 알림, 여러 건이면 "대화 신청이 왔어요 / 밤사이 2명이 대화를 신청했어요" 식 묶음(2026-10-10 개정, PR #440 — 종전 "밤사이 2명이 나를 수락했어요". 단건 알림도 "대화 신청이 왔어요"이고 `kind` 값 `acceptance_received` 는 그대로다). 친구 가입(리뷰 쓰기) · 학생증 검토 결과 알림은 묶지 않고 한 건씩 보낸다. **내가 방금 한 행동으로 생긴 내 쪽 알림은 보류하지 않고 버린다**(대장 10-03) — 밤에 내가 눌러 생긴 매칭의 내 쪽 "매칭됐어요!", 마지막에 누른 사람 쪽 "카카오톡 아이디를 주고받았어요"(둘 다 방금 화면에서 봤다, `notify(defer=False)`). 보낼 때 `notify` 를 다시 지나서 밤사이 끈 알림 · 정지 · 탈퇴는 걸린다. 채팅 · 카드 도착은 조용한 시간 예외라, 신뢰 확인 리마인드는 보낼 시각을 08시로 미뤄 둬서 이 표에 오지 않는다. `kind` 는 enum 이 아니라 4값 check 다
- **`paid_card_offers`(유료 카드 제안, 2026-10-10 운영 적용 — `20261010020000` · 주기당 한 장 인덱스 교체 `20261010050000`)**: 서버가 주기마다 상위 20% 구간에서 **미리** 한 명을 골라 적어 두는 표다. 컬럼은 위 그림. enum `paid_card_offer_status`(§8) 4값 — `offered`(제안 중) · `purchased`(산 것) · `replaced`(대상이 자격을 잃어 다시 고름) · `expired`(주기가 지나도록 안 삼). FK 삭제 규칙: `owner_id` · `target_id` 는 `on delete cascade`(탈퇴 정리를 막지 않는다), `purchased_card_id` 는 `on delete set null`(카드가 지워지면 칸만 비고 제안 행은 남는다 — 그래서 `purchased` 이면서 null 인 행도 정상). 제약: `check (band_count >= 1)`(뽑을 사람이 없으면 제안이 생기지 않는다), `check (purchased_card_id is null or status = 'purchased')`. **주기당 한 장은 부분 유일 인덱스 `paid_card_offers_one_live_per_cycle (owner_id, cycle_started_at) where status in ('offered','purchased')` 가 DB 에서 막는다** — `20261010050000`(PR #442, 2026-10-10 운영 적용 완료)이 종전 인덱스 `paid_card_offers_one_offered_per_cycle`(`offered` 만 막아 구매 뒤 같은 주기에 새 `offered` 가 들어갈 수 있었다)를 지우고 바꿨다. `replaced` · `expired` 는 몇 개든 쌓인다(재선정 · 만료 이력). 보조 인덱스: `(owner_id, created_at desc)` · `(target_id)` · `(purchased_card_id) where purchased_card_id is not null`(FK 칸 인덱스 관례). RLS 켬 · **정책 없음**, `service_role` 만 `select` · `insert` · `update` · `delete`
- **함수 `purchase_paid_card(p_owner uuid, p_offer uuid) → jsonb`(2026-10-10 운영 적용 — `20261010030000`)**: 제안 하나를 하트 **50개**(함수 안 상수 `c_price`, 바꾸려면 마이그레이션)로 사서 `daily_cards.source = 'purchased'`(`expires_at` null) 카드 한 장을 만든다. security invoker, `public` · `anon` · `authenticated` 회수, `service_role` 만 실행. 제안 행을 `for update` 로 잠근 채 끝까지 가서 같은 제안을 동시에 두 번 불러도 하트는 한 번만 빠진다. 돌려주는 `result` 4값: `ok`(`card_id` 포함) · `already_purchased`(`card_id` 포함, 하트 · 카드 그대로) · `not_enough_hearts`(아무것도 안 바뀐다) · `offer_gone`(제안이 없거나 · 남의 것이거나 · `offered` 가 아니거나 · 대상이 이제 고를 수 없다). **대상이 자격을 잃어서 `offer_gone` 을 돌려줄 때만** 그 제안을 `replaced` 로 바꿔 둔다(서버가 낡은 제안을 계속 보여 주는 것을 막는다). 자격은 `match_candidates` 의 `pickable` 을 그대로 써서 한 곳에서 정한다. 하트 차감은 `grant_hearts(…, 'extra_card', p_offer)` 로 카드를 만들기보다 먼저 하고, 부족하면 `entitlements_balance_non_negative` 제약 위반을 하트 부족으로 읽는다
- **`notifications`(알림함, 2026-10-10 운영 적용 — `20261010040000`)**: 푸시와 별개로 앱 안 목록에 쌓는 기록(푸시를 껐거나 못 받아도 다시 본다). `kind` 는 enum 이 아니라 **text + check 6값**(`card_arrived` · `chat_request` · `match_made` · `friend_review` · `verification_result` · `night_digest` — 새 종류는 check 를 바꾸는 마이그레이션으로 늘린다, `pending_pushes` 와 같다). 인덱스: 안 읽은 개수용 부분 인덱스 `notifications_unread_index (profile_id) where read_at is null` · 최근순 목록용 `(profile_id, created_at desc)`. `profile_id` 는 `on delete cascade`. RLS 켬 · 정책 0, `service_role` 만 네 권한. **90일 보관 정리는 서버 배치 몫이고 구현 중이다**(이 마이그레이션에는 없다)
- 알림 토글은 지금 7개다. DESIGN 16d의 "내 글의 새 댓글"은 이번 스코프에 커뮤니티 댓글이 없어서(DESIGN §8.11) 컬럼을 두지 않고, 댓글을 도입할 때 추가한다 — 검토11. DESIGN 16d는 지금 고치지 않는다

## 5. 안전 · 계정 상태 (조각 6)

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    profiles ||--o{ blocks : "blocker_id"
    profiles ||--o{ blocks : "blocked_id"
    profiles |o--o{ reports : "reporter_id"
    profiles ||--o{ contact_blocks : "owner_id"

    blocks {
        uuid blocker_id PK, FK "조각6"
        uuid blocked_id PK, FK "차단당한 쪽은 조회 불가"
        timestamptz created_at "16f 차단일"
    }

    reports {
        uuid id PK "조각6 적용"
        uuid reporter_id FK "계정 삭제(탈퇴 30일 뒤) 시 null"
        report_target target_type "profile message friend_review poll"
        uuid target_id "대상 행 id · FK 없음"
        uuid target_profile_id FK "대상의 주인 · set null · 자동 가림 셈"
        jsonb target_snapshot "신고 시점 내용 사본"
        report_reason reason "abuse sexual spam fake other(검토10 해결)"
        text reason_note "기타일 때 한 줄 · 1~200자"
        report_status status "open actioned dismissed"
        timestamptz created_at
        timestamptz resolved_at "조치·기각 시각 · open 이면 null(check) · 처리 뒤 1년에 삭제(§11-23)"
    }

    contact_blocks {
        uuid owner_id PK, FK "조각6 적용"
        bytea contact_hmac PK "E.164 정규화 후 HMAC · 원본 저장 안 함 · 클라이언트에 주지 않음"
        uuid id UK "기기에 저장한 이름과 짝짓는 키"
        smallint key_version "기본 1 · 같은 버전끼리만 대조(검토9 해결)"
        timestamptz created_at
    }

    signup_blocks {
        bytea email_hmac PK "조각1 · 탈퇴한 학교 이메일 HMAC · 조각6 부터 탈퇴가 채운다"
        timestamptz blocked_until "탈퇴 요청 시각 + 2개월 · 정지 중 탈퇴는 infinity(§11-22)"
        smallint key_version "조각6 적용 · 기본 1"
    }
```

- 지인 차단 대조: `contact_blocks.contact_hmac` = `profile_private.phone_hmac` (같은 서버 키, 설계 §7.6b). 나중에 가입한 지인도 가입 때 계산한 `phone_hmac` 로 소급 대조한다
- `phone_hmac` 을 미리 계산해 두는 이유: HMAC 키는 FastAPI 환경변수에만 있어서 DB 안 배치 작업(pg_cron)은 번호를 HMAC 으로 바꿀 수 없다
- **16b 목록의 이름·끝 4자리는 서버에 두지 않는다**(§11-9). 8d에서 고를 때 앱이 기기 안에만 저장하고, FastAPI가 등록 응답으로 돌려준 `contact_blocks.id` 를 키로 짝지어 보여준다. `contact_hmac` 을 키로 쓰지 않는 이유: HMAC 키를 교체하면(검토9) 값이 바뀌어 이름이 전부 끊기고, 클라이언트에 HMAC 값을 줄 필요도 없어진다. 앱을 재설치하거나 기기를 바꾸면 이름 없이 "이전에 차단한 연락처"로 보이지만 차단과 해제는 그대로 된다
- **매칭 중 차단은 `matches` 에 기록하지 않는다.** `chat_closed_at` 같은 공유 값으로 처리하면 상대가 차단을 추론한다. 차단한 사람의 `match_participants.left_at` 과 `blocks` 행으로만 처리한다(설계 §7.2 "차단당한 쪽은 알 수 없어야")
- `reports.target_snapshot` — 게이트 실패 채팅 삭제(설계 §2.5)나 탈퇴 30일 뒤 삭제(§11-15)로 신고된 원본이 사라져도 24시간 조치 근거(애플 심사 지침 1.2)가 남아야 한다. `reporter_id` 는 `on delete set null`. 처리가 끝나고(`resolved_at`) 1년 뒤 행째 지운다(§11-23). check 후보 `(status = 'open') = (resolved_at is null)`
- `signup_blocks` 는 탈퇴로 `profiles` 가 지워진 뒤에도 남아야 하므로 관계가 없다. 원본 이메일을 남기지 않으려고 HMAC 으로 제안. 종전: 가입 때 FastAPI HTTP Auth Hook 이 메일 도메인 화이트리스트와 함께 이 표를 검사한다(§11-12). **2026-10-09 소셜 로그인 전환으로 개정**: 소셜(카카오 · 구글 · 애플) 가입에는 이 검사가 없다 — Hook(`POST /hooks/before-user-created`)은 소셜을 검사 없이 허용하고, 학교 메일 인증용 임시 이메일 계정만 도메인 화이트리스트 → 이 표 순으로 본다(모르는 가입 수단은 거절). 인증을 끝내는 `POST /school-email/verify` 도 같은 두 검사를 한 번 더 한 뒤에 DB 함수 `complete_school_email_verification` 을 부른다(`backend/app/auth_hooks/router.py` · `backend/app/school_email/router.py`). 정지 중 탈퇴는 `blocked_until` 을 `infinity` 로 써서 기간 없이 막는다(§11-22). 기한(`blocked_until`)이 지난 행은 FastAPI 배치(신고 1년 삭제와 같은 배치)가 지운다. 남기면 재탈퇴 때 `email_hmac` PK 가 충돌한다
- **조각 6 적용 기록(2026-09-27, 마이그레이션 `20260927010000` ~ `20260927030100`, 운영 적용됨).** ① `reports`: enum `report_reason` 5값, `reason_note`(기타 한 줄, 1~200자), `target_profile_id`(대상의 주인, 자동 가림 셈), unique `reports_once_per_reporter (reporter_id, target_type, target_id)`, check `reports_status_pair`, 인덱스 `target_profile_id` · `created_at`. 하루 10건 상한은 FastAPI 가 센다. **1년 삭제는 `resolved_at` 기준이다** — 2026-09-29 PR #165 로 코드를 바로잡았다(그 전 배치는 `created_at` 기준이라 1년 넘게 열린 신고까지 지웠다). `resolved_at` 인덱스는 아직 없다(백로그). 적용된 마이그레이션 `20260927010200` 33줄 주석의 옛 기준 문장은 파일을 고치지 않는 규칙이라 그대로다 ② `blocks`: PK `(blocker_id, blocked_id)`, 자기 차단 check, `blocked_id` 인덱스. 신고하면 같은 요청 안에서 차단 행도 넣는다(지인 리뷰 신고만 예외) ③ `contact_blocks`: 위 모양 + `contact_hmac` 인덱스, **클라이언트 권한 0**(§2 개정) ④ `profile_private.phone_hmac` · `phone_hmac_key_version` 을 `set_phone_number`(5인자, `20260927030000`)가 번호와 같이 쓴다 — 옛 번호는 백필 스크립트로 한 번 채웠다 ⑤ `withdraw_account()`(`20260927030100`) — 상태 · `withdrawn_at` · `signup_blocks` 를 한 트랜잭션에(정지면 무기한, 아니면 2개월, 두 번 불러도 같다). **2026-10-09 개정(`20261008040000`, 운영 적용)**: `p_email_hmac` 이 null 이면(카카오처럼 메일이 없거나 학교 메일 인증 전에 나가는 계정) 상태 · `withdrawn_at` 만 바꾸고 `signup_blocks` 는 남기지 않는다. 서명 · security invoker · `service_role` 만 실행은 그대로 ⑥ `match_candidates` · `card_issue_owners` 가 차단(양방향) · 자동 가림 · 지인 차단(같은 키 버전) 을 뺀다(`20260927010500`)
- **`profile_private.phone_hmac` 유니크는 걸지 않는다**(2026-09-22 사용자 결정, 검토5 해결) — "한 번호 한 계정" 을 DB 로 강제하지 않는다. 학교 메일이 둘인 사람이 같은 번호로 계정 둘을 굴려 정지 · 재가입 제한을 우회할 수 있는 것은 알려진 한계다. 같은 번호 추천 보상 중복은 `redeem_referral` 이 막는다(§6)

## 6. 하트 · 추천 · 지인 리뷰 (조각 7 전후)

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    profiles ||--o| entitlements : "잔액"
    profiles ||--o{ heart_transactions : "원장"
    profiles |o--o{ purchases : "결제"
    profiles ||--o{ heart_task_submissions : "인증샷"
    profiles ||--o{ promo_redemptions : "사용자"
    promo_codes ||--o{ promo_redemptions : "코드"
    profiles ||--o| referrals : "referee_id 가입당 1회"
    profiles ||--o{ referrals : "referrer_id"
    profiles ||--o{ friend_reviews : "reviewer_id"
    profiles ||--o{ friend_reviews : "reviewee_id"

    entitlements {
        uuid profile_id PK, FK "조각7"
        integer heart_balance "0 이상 · 원장 합계"
        timestamptz updated_at
    }

    heart_transactions {
        uuid id PK "조각7 제안"
        uuid profile_id FK
        integer amount "적립은 양수 · 사용은 음수"
        heart_reason reason "값은 §8 열거형"
        uuid ref_id "원인 행 id · FK 없음"
        timestamptz created_at
    }

    purchases {
        uuid id PK "2026-10-13 운영 적용 · 20261013010100"
        uuid profile_id FK "계정 삭제(탈퇴 30일 뒤) 시 null · 5년 보관 · 인덱스"
        store_platform store "play_store app_store"
        text product_id "heart_50 heart_100 heart_200 heart_400 heart_800"
        text store_order_id "구글 주문 번호 GPA · 애플은 transactionId · 없을 수 있다"
        text token_hash "구매 토큰 sha256 16진 64자 · 원문은 두지 않는다 · (store, token_hash) unique"
        integer heart_amount "> 0"
        integer bonus_hearts "첫 구매 보너스 · 기본 0"
        integer price_krw "서버 상품표 판매가 > 0"
        purchase_status status "granted refunded · 기본 granted"
        boolean is_test "라이선스 테스터 결제 · 기본 false"
        integer clawed_back_hearts "환불 때 실제 회수한 하트"
        timestamptz purchased_at
        timestamptz granted_at "기본 now()"
        timestamptz refunded_at "status=refunded 일 때만(check)"
    }

    heart_task_submissions {
        uuid id PK "2026-09-28 적용 · 18b"
        uuid profile_id FK "cascade"
        heart_task task "everytime_post kakao_share"
        text[] storage_paths "2026-10-19 개정(종전 text storage_path 한 장) · heart-task-proofs 비공개 · 인증샷 1~3장(순서=보여 줄 순서, check 1~3) · 검수 중이면 필수 · 검수 60일 뒤 빈 배열 {}"
        submission_status status "submitted approved rejected · 승인 반려는 끝 상태"
        integer reward_hearts "제출 때 약속한 하트 · > 0"
        heart_task_reject_reason reject_reason "반려일 때만 · 반려면 필수"
        timestamptz created_at
        timestamptz reviewed_at "submitted 면 null(check)"
    }

    promo_codes {
        text code PK "조각 검토3 · 발급 규칙 미정"
        integer heart_amount
        integer max_redemptions
        timestamptz expires_at
    }

    promo_redemptions {
        text code PK, FK
        uuid profile_id PK, FK "1코드 1계정"
        timestamptz redeemed_at
    }

    referrals {
        uuid referee_id PK, FK "2026-09-28 적용 · 신규 가입자 · cascade"
        uuid referrer_id FK "코드 주인 · cascade · 인덱스"
        timestamptz created_at
        timestamptz rewarded_at "입력 즉시 양쪽 50하트(학생증 통과 뒤에만 닿는 화면) · 행이 있으면 연결"
    }

    friend_reviews {
        uuid id PK "2026-09-28 적용"
        uuid reviewer_id FK "추천으로 연결된 지인만(어느 방향이든) · cascade"
        uuid reviewee_id FK "받은 사람은 삭제 불가 · 작성자는 삭제 가능(09-29) · cascade"
        text[] tags "12종(서버 검사) · 1~3개(check, 검토7 해결)"
        text comment "선택 · 1~100자 · 앞뒤 공백 없음"
        content_status status "visible blinded · 가림은 운영자가 대시보드에서"
        timestamptz created_at
    }
```

- `entitlements.heart_balance` 는 `heart_transactions` 합계의 캐시다. 지급·차감은 FastAPI가 한 트랜잭션에서 둘 다 쓴다(설계 §7.6)
- `purchases` 는 탈퇴해도 지우지 않는다(§11-14). `profile_id` 는 `on delete set null` 이라 null 허용이고, 금액·상품·영수증 번호만 남는다. `store_transaction_id` unique 도 남아 재가입한 계정이 같은 영수증을 다시 쓰지 못한다. `purchased_at` 5년 뒤 FastAPI 가 지운다. 하트 원장(`heart_transactions`)은 탈퇴와 함께 지워진다. 법령에 따라 보존하는 정보는 다른 개인정보와 분리해 저장해야 하는데(개인정보보호법 제21조③), 별도 테이블에 `profile_id` 없이 남기므로 이를 충족한다고 본다
  - **2026-10-13 구현으로 개정(PR #498 · 서버 PR #499 · 앱 PR #506, 운영 적용 — 종전 위 그림의 제안 모양 `store_transaction_id` unique · `purchase_status` `verified` · 번들 50~400)**: 영수증 중복은 **구매 토큰 원문이 아니라 sha256 해시** `token_hash` 로 막는다 — unique `purchases_token_once (store, token_hash)`(원문은 서비스 계정과 함께면 조회 · 소비가 되는 값이라 두지 않는다). 위 "`store_transaction_id` unique 도 남아 재가입한 계정이 같은 영수증을 다시 쓰지 못한다" 는 이 unique 가 맡는다. 제약 `purchases_token_hash_shape`(`^[0-9a-f]{64}$`) · `purchases_amounts_valid` · `purchases_refund_consistent`(`refunded` ⇔ `refunded_at` 있음). 인덱스 `purchases_profile_id_index`. RLS 정책 하나 `purchases are readable by owner`(본인 행 select), `authenticated` = `select` 만, `service_role` = 네 권한. **대기(pending) 결제는 행을 만들지 않는다**(지급 전이라 기록할 것이 없다)
  - **함수 `grant_store_purchase(p_profile_id, p_store, p_product_id, p_token_hash, p_order_id, p_purchased_at, p_is_test) → jsonb`**: 구매 행 + 하트 + 첫 구매 판정 + 보너스 + 원장을 한 트랜잭션에. 상품표(하트 · 판매가)와 보너스(+50 · 100하트 이상)는 이 함수 안 상수 한 곳이다(바꾸려면 마이그레이션). `result` 4값 — `granted` · `already_granted`(같은 사람이 같은 영수증을 또 보냄, 하트 그대로) · `token_used`(다른 사람이 이미 쓴 영수증) · `unknown_product`. 사람마다 `pg_advisory_xact_lock` 으로 줄을 세워 두 기기에서 동시에 첫 구매를 해도 보너스는 한 번이다. **첫 구매 = 이 사람의 구매 행이 하나도 없음(환불된 것도 센다) + 100하트 이상 상품.** 원장은 두 줄로 나눠 적는다 — `purchase`(구매분) · `first_purchase_bonus`(보너스), 둘 다 `ref_id` = 구매 행 id
  - **함수 `refund_store_purchase(p_store, p_token_hash) → jsonb`**: 구매분 + 보너스를 `min(잔액, 합계)` 만 회수한다(잔액은 음수가 되지 않는다, 이미 쓴 하트는 회수하지 못한다). 원장은 `refund` 음수 한 줄(회수 0 이면 줄 없음), 행은 `refunded` · `refunded_at` · `clawed_back_hearts`. `result` 3값 — `refunded`(`clawed_back` · `shortfall` 포함, 계정이 지워진 구매는 모자람 0) · `already_refunded` · `unknown`(우리가 지급한 적 없는 영수증). 매시 환불(voided) 조회 배치가 부른다(`backend/DEPLOY.md` §4-9)
  - 두 함수 모두 security invoker · `search_path = ''` · `public` · `anon` · `authenticated` 실행 회수 · `service_role` 만 실행(`purchase_paid_card` 와 같다, `docs/SUPABASE.md` §5)
  - **2026-10-14 애플(App Store) 추가 — 스키마 변경 없음**(서버 PR #519 · #521, 앱 PR #520. 마이그레이션 파일 0개, `supabase/` 변경 없음): 아이폰 구매는 같은 표 · 두 함수를 **`store = 'app_store'`** 로 부른다. `store_order_id` = 애플 거래 번호 `transactionId`(숫자 문자열, 평문 — 우리 키 없이는 조회할 수 없는 값이라 문의 · 환불 번복 수동 처리 때 행을 찾으려고 둔다), `token_hash` = 같은 거래 번호의 sha256(구글과 같은 방식 — `(store, token_hash)` unique 가 스토어를 이미 가른다), `is_test` = 애플 샌드박스 거래. 결제 창에 싣는 계정 표시 `appAccountToken` 은 **profile_id 에서 결정적으로 만든 UUIDv5** 라 저장하지 않고 서버가 매번 다시 계산한다 — **새 컬럼이 없다.** 첫 구매 보너스 판정은 스토어를 가르지 않는다(안드로이드에서 산 계정은 아이폰에서 보너스가 없다). 환불은 애플 알림이 `refund_store_purchase('app_store', …)` 를 부른다(`backend/DEPLOY.md` §4-10). `price_krw` 는 함수 안 상수 판매가 그대로다 — 애플 가격대가 다르면 실제 청구액과 어긋날 수 있다(계획서의 선택 마이그레이션 `p_price_krw` 는 만들지 않았다)
- `friend_reviews` 는 `unique (reviewer_id, reviewee_id)`. 추천 관계 확인은 FastAPI가 `referrals` 로 한다 — **2026-10-13 개정(서버 PR #486, DB 변경 없음): 친구 코드 경로(`friend_code`)는 `referrals` 를 보지 않고 `profiles.referral_code` 로 받는 사람을 찾는다.** 같은 사람에게 한 번(`friend_reviews_once` → 409)은 두 경로 모두 같다(설계 문서 §2.8)
  - **2026-09-28 적용 기록**: 제약 이름 `friend_reviews_once`(두 번째는 서버 409) · `friend_reviews_not_self` · `friend_reviews_tags_count`(1~3) · `friend_reviews_comment_length`, 인덱스 `(reviewee_id, created_at desc)`, 두 FK 이름 `friend_reviews_reviewer_id_fkey` · `friend_reviews_reviewee_id_fkey`(서버 embed 가 쓴다). **2026-09-29 작성자 삭제**는 DB 변경 없이 서버가 하드 삭제한다 — 신고 기록은 `reports.target_snapshot` 에 남고 `target_id` 는 FK 가 없어 깨지지 않는다. 지우면 unique 가 풀려 다시 쓸 수 있다
- **`referrals`(2026-09-28 적용)**: RLS 켬 · 정책 0 · `service_role` 만. 두 FK `on delete cascade`, check `referrals_not_self`, 인덱스 `referrals_referrer_id_index`. DB 함수 `redeem_referral(referee, code)` 가 코드 검사 → 행 넣기 → 양쪽 `grant_hearts(50, 'referral', ref_id = referee_id)` 를 한 트랜잭션에 한다. 같은 번호 두 갈래(추천인과 같은 번호 · 이 번호로 이미 보상받음)와 자기 코드는 같은 422 로 막는다 — `phone_hmac` 이 빈 옛 계정은 비교하지 않는다. 정지 · 탈퇴 추천인 코드는 404
- **`heart_task_submissions`(2026-09-28 적용)**: 부분 unique `heart_task_submissions_one_reviewing (profile_id, task) where status = 'submitted'`(항목마다 검수 중 하나) · 인덱스 `(profile_id, created_at)`. 함수 `heart_task_monthly_limit`(1 · 3) · `heart_task_status`(18a 상태, 한국 시간 달력 월) · `submit_heart_task`(검수 중 `CM409` · 한도 `CM429`). 트리거 `heart_task_submissions_guard`(고정 칸 · 끝 상태 · `reviewed_at` 찍기 · 검수 뒤엔 `storage_path → null` 만) · `heart_task_submissions_grant`(검수 중 → 승인일 때만 `grant_hearts(reward_hearts, 'free_task', id)`). 운영자는 대시보드에서 `status` 를 바꾼다(`backend/DEPLOY.md` §4-5)
  - **2026-10-19 개정(인증샷 여러 장 · 단톡방 이어서 제출, 마이그레이션 `20261019100000`, PR #613, 운영 적용) — 바로 위 문장 중 아래를 고친다.** ① `storage_path text` 는 **`storage_paths text[] not null default '{}'`** 로 바뀌었다(check `heart_task_submissions_paths_max` 0~3개 · `heart_task_submissions_proof_while_reviewing`: 검수 중이면 1~3개). 옛 줄은 `array[storage_path]` 로 채웠고 옛 칸과 옛 check 는 지웠다. ② 부분 unique `heart_task_submissions_one_reviewing` 을 **지웠다** — 단톡방은 검수 중이어도 월 한도 안이면 이어서 낼 수 있다. ③ `submit_heart_task(p_id, p_profile, p_task, p_paths text[], p_reward, p_now)` 로 인자가 바뀌어 옛 함수를 지우고 새로 만들었다: **사람 · 항목마다 `pg_advisory_xact_lock`** 아래에서 이번 달 `검수 중 + 승인` 이 한도에 찼는지 보고, 찼고 검수 중이 있으면 `CM409`(결과를 기다려 달라), 없으면 `CM429`(이번 달 끝), 경로가 0개 · 4개 이상이면 `22023`. ④ guard 트리거는 검수 중에는 `storage_paths` 를 고정하고 검수가 끝난 뒤에는 `'{}'` 로 비우기만 허용한다(60일 정리). `heart_task_status`(18a 상태) · 월 한도 함수 · 승인 트리거 · `admin_review_heart_task` 는 그대로다. 배포 순서 주의: 옛 서버는 `storage_path` · `p_path` 를 쓰므로 마이그레이션 직후 서버를 바로 배포해야 하고, 서버만 이전 리비전으로 되돌리면 깨진다(`backend/DEPLOY.md` §4-14).
- **`grant_hearts` 가 음수(하트 쓰기)도 받는다**(2026-09-28 `20260928020000`, 시그니처 그대로) — 아바타 다시 만들기 10하트 차감 등(**2026-10-14 사용자 결정으로 20하트, 종전 10하트** — 금액은 서버 상수 `AVATAR_REGEN_HEARTS` 라 스키마 변경 없음. FAQ 답변 두 곳의 숫자만 `20261014120000_faq_avatar_regen_cost_20` 이 고쳤다)
- 커뮤니티 투표 하트는 자동 적립(`heart_transactions.reason = poll_vote`), 주간 상한 30하트는 원장 집계로 검사 — **2026-10-16 사용자 확정으로 개정(`20261016144525`, PR #570): 하루 첫 투표 5하트 · 주간 상한 15하트**(원장 합 + 5 ≤ 15). 에브리타임 보상은 서버 상수 40(종전 50)이 제출 행의 `reward_hearts` 로 적힌다(스키마 변경 없음)
- 추천 어뷰징 "동일 기기 차단"(설계 §2.7)을 판단할 기기 식별값의 저장처가 아직 없다 — 검토6

## 7. 커뮤니티 · 운영

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    profiles ||--o{ polls : "author_id"
    polls ||--o{ poll_votes : "투표"
    profiles ||--o{ poll_votes : "voter_id"

    polls {
        uuid id PK "커뮤니티 탭 2026-09-27 적용"
        uuid author_id FK "응답에 담지 않음 · 익명 · cascade"
        text question "1~80자 · 앞뒤 공백 없음"
        text option_a_label "기본 찬성 · 1~6자"
        text option_b_label "기본 반대 · 1~6자 · A 와 달라야 함"
        content_status status "visible blinded · 가림은 대시보드에서"
        timestamptz created_at
    }

    poll_votes {
        uuid poll_id PK, FK
        uuid voter_id PK, FK "재투표 불가"
        poll_choice choice "a b"
        timestamptz created_at
    }

    faq {
        uuid id PK "2026-09-29 적용 · 원격 수정용 · 첫 36행 씨앗"
        faq_category category "6종 · 앱은 enum 순서로 묶음"
        text question
        text answer
        smallint sort_order "묶음 안 순서 · 10 단위"
        timestamptz updated_at "기본 now() · 트리거 없음"
    }
```

- **`polls` · `poll_votes`(커뮤니티 탭, 2026-09-27 적용 — 조각 8 에서 앞당김, 검토3 개정)**: 두 표 모두 클라이언트 권한 0 · `service_role` 만. `polls` check 넷(질문 1~80자 · 라벨 각 1~6자 · 두 라벨 다름, 모두 앞뒤 공백 없음), 인덱스 `(created_at desc, id desc)`(피드 커서) · `(author_id, created_at)`(하루 10개 셈). `poll_votes` PK `(poll_id, voter_id)`(재투표 불가 → 409), 인덱스 `voter_id`, 두 FK cascade. DB 함수 넷 — `poll_feed`(작성자 id 를 내주지 않는다, 가려진 글 · active 아닌 작성자 글 제외, active 아닌 투표자 표 제외 — **2026-10-15 개정, 아래 "탭 칸"**) · `create_poll`(한국 시간 하루 10개 넘으면 `CM429`) · `poll_vote_reward_due`(하루 첫 투표 · 주 30 상한 판정 — **2026-10-16 개정 `20261016144525`: 주 15 상한 · 하트 5**) · `cast_poll_vote`(없는 글 `CM404`, 사람 단위 잠금으로 하트 10 중복 지급 방지). 차단 관계라도 글을 거르지 않는다(익명)
  - **`poll_feed` 탭 칸(2026-10-15, 마이그레이션 `20261015120000_poll_feed_tabs`, PR #540 — 저장소에만 있고 운영 미적용)**: 시그니처 **`poll_feed(p_viewer uuid, p_poll_id uuid default null, p_before timestamptz default null, p_before_id uuid default null, p_limit integer default 20, p_tab text default 'all')`**. 인자를 늘리면 `create or replace` 가 안 되고 새로 만들기만 하면 같은 이름 함수가 둘이 돼 PostgREST 가 못 고르므로(PGRST203) 옛 5인자 함수를 `drop` 하고 다시 만든다(한 트랜잭션). 반환 칸 · 가림 · 집계는 그대로(`author_id` 없음, `is_mine` 만). `security invoker` · `stable` · `search_path = ''`, 다시 만든 뒤 `public` · `anon` · `authenticated` 실행 권한을 다시 빼고 `service_role` 에만 준다. 탭: `all`(최신순 + `(created_at, id)` 커서 — 상세 · 투표 뒤 다시 읽기도 이것) · `popular`(최근 7일 글 중 active 표 1개 이상, 참여 수 → 최신 → id 순, 서버가 한 쪽 20개만 — 모자라면 그대로) · `mine`(내 글, 최신순 + 커서) · `voted`(내가 표를 둔 글, 글 올린 시각 순 + 커서) · 그 밖 값은 빈 결과(서버가 먼저 422). 옛 서버(`p_tab` 없이 부름)도 기본값 `all` 로 돌아 **이 마이그레이션을 서버 배포보다 먼저 적용한다**(`backend/DEPLOY.md` §5). 탭 조건은 `case` 한 문장이다 — 글이 수만 개가 되면 탭별 문장으로 나눠 `polls (author_id, created_at)` · `poll_votes (voter_id)` 인덱스를 타게 한다(파일 `ponytail` 주석). 시험은 `supabase/tests/community_polls_test.sql`
- **`faq`(2026-09-29 적용 — 운영 기록 `20260929054505`, 검토3 개정)**: RLS 켬 · 정책 하나(`authenticated` 전체 읽기), grant `authenticated` = `select`, `anon` 없음, `service_role` = 네 권한. 공개 여부 칸은 없다(처음부터 전부 공개, 사용자 결정). 첫 문구 36행을 **마이그레이션 안에서 insert** 했다 — `seed.sql` 은 로컬 초기화에만 돈다. 이후 문구는 대시보드에서 고치고 이 마이그레이션은 되돌려 고치지 않는다. 인덱스 없음(36행 전체 읽기)
- **관리자 웹 표(2026-10-18 운영 적용, 설계 바탕화면 `관리자_대시보드_설계_10-18.md`, PR #592 ~ #608) — 모두 RLS 켬 · 정책 0 · 클라이언트 접근 없음, 서버(`get_admin_caller`: 로그인 → 2단계 aal2 → 명단)만 쓴다.**
  - `admin_users(user_id uuid PK → auth.users on delete cascade, created_at)`: 관리자 명단. **`service_role` 은 `select` 만**(`20261018035204`) — 서버 버그로 스스로를 넣거나 지우지 못한다. 등록은 사용자 승인 뒤 대장이 SQL 한 줄. 관리자 계정은 사용자 기능에서 존재하지 않는 것으로 본다(통계 · 정지 · 하트 조정 · 탈퇴 대행 모두 제외 또는 CM404).
  - `admin_actions(id, admin_user_id(FK 없음), action(형식 check), target_type, target_id text, before/after jsonb, reason(≤500자), ip inet, created_at)`: 관리자 작업 기록. **`service_role` 도 `select` · `insert` 만** — 고치거나 지울 수 없다. 모든 관리자 쓰기는 같은 요청(같은 DB 함수 트랜잭션) 안에서 한 줄을 남기고 **기록이 실패하면 조치도 실패한다**(기록 없는 조치 금지, 종전 "표 없이 로그" 결정 §11-13 을 사용자가 10-18 에 바꿨다). 전화번호 · 카톡 원문 · 해시 · 문서번호는 `before`/`after` 에 넣지 않는다. 보관 2년. 인덱스 3개(최근 순 · 대상별 · 관리자별). **SQL 창에서 손대지 않는다.**
  - `unknown_email_domain_attempts(domain PK, attempt_count, first_seen_at, last_seen_at)`(2026-10-17): 화이트리스트에 없어 거절된 학교 메일의 **도메인과 횟수만**(앞부분 · 사용자 id · IP 없음). 5000행이 넘으면 새 도메인은 받지 않는다. 나중에 `university_email_domains` 에 옮길 후보를 보려는 표다.
  - 관리자 DB 함수(전부 `security invoker` · `service_role` 만 실행 · 조치 함수는 `admin_assert` 로 명단 재확인): `admin_review_heart_task`(인증샷 승인 · 반려) · 신고 조치 `admin_resolve_report` · `admin_suspend_profile` · `admin_unsuspend_profile` · `admin_unhide_profile` · `admin_set_content_status`(`20261018030000`, 같은 대상 함께 닫기 · 가림 해제는 운영자가 본 신고 id 목록 `p_seen` 에 든 것만 닫는다 — `20261018140000`) · 사용자 · 결제 `admin_adjust_hearts` · `admin_close_account`(탈퇴 대행) · 읽기 `admin_billing_daily` · `admin_billing_shortfall`(`20261018120000`) · `admin_billing_returned_accounts(p_limit)`(`20261019220000`, 환불된 실제 구매를 계정별로 묶는다 — 시험 결제 · 지워진 계정 제외, 서버 `GET /admin/billing/frequent-returns`) · 읽기 전용 통계 `admin_stats_overview` · `admin_stats_daily` · `admin_unknown_domains` · `admin_universities_status` · `admin_health` · `admin_matching_*`(`20261018150000`, 관리자 계정 제외) · `admin_matching_requests(p_status, p_before_at, p_before_id, p_limit)`(`20261027100000`, 2026-10-27 — 카드를 받은 사람이 **수락한** 것(`card_decisions.decision = 'accept'`)을 최근 순으로 읽어 신청한 사람 · 받은 사람 · 상대 응답 상태를 돌려준다. 상태는 앱 "보낸 신청"(`backend/app/cards/router.py` 의 `_sent_state`)과 같은 규칙: 두 사람의 `matches` 줄이 있거나 응답이 수락이면 `accepted`, 응답이 거절이면 `rejected`, 응답이 없고 신청 후 7일(`ACCEPTANCE_TTL_DAYS`)이 지나면 `expired`, 그 밖은 `waiting`. 반환 칸 10개뿐(사진 · 카톡 아이디 · 대화 · 전화 없음), 커서 `(requested_at, card_id)` · `p_limit` 1 ~ 101, **`admin_matching_*` 와 달리 관리자 계정을 따로 거르지 않는다**(SQL 에 그 조건이 없다). 서버 `GET /admin/matching/requests`, 시험 `supabase/tests/admin_matching_requests_test.sql`).
  - `profile_avatars_one_fallback`(`20261018100000`): 기본 아바타 행은 한 사람에 한 줄(부분 unique) — 5회 실패 보상 하트 10이 두 번 나가는 경쟁을 막는다. `notifications.kind` check 에 `heart_task_approved` · `heart_task_rejected` 가 더해졌다(`20261018130100`, 서버보다 먼저 적용해야 한다).
- **DB 함수 `home_stats()`**(2026-09-26, `20260926150000`): 서비스 전체 집계 네 값(누적 카드 · active 가입자 · 말풍선이 오간 매칭 · active 학교 이름순)을 한 행으로. `service_role` 만 실행(09b 홈 `/home/summary`)

## 8. 열거형

enum 값은 만든 뒤 지울 수 없다(추가·이름 변경만 된다). 그래서 **후보**라고 적힌 타입은 그 조각에서 값을 확정한 뒤 만든다.

| 타입 | 값 | 근거 |
| --- | --- | --- |
| `gender` | `male` `female` | §3 |
| `profile_status` | `pending` `active` `suspended` `withdrawn`(조각6 — 2026-09-27 적용, §11-15). **`pending` → `active` 는 가입 맨 끝(자기소개 저장 · 아바타 ready 뒤)에 서버가 바꾼다 — 2026-10-17 개정, §3 `profiles`** | §3 |
| `verification_status` | `none` `pending` `verified` `rejected` — **확정(2026-09-14 사용자 결정) · 클라우드 적용됨(2026-09-20)** | 설계 §7.3·미결3, DESIGN 화면 3b |
| `major_field` | `humanities` `social` `business` `engineering` `natural_science` `medical` `arts_sports` `education` | 조각 0 마이그레이션 `20260913054544` |
| `religion` | `none` `protestant` `catholic` `buddhist` | DESIGN §8.5 무교·기독교·천주교·불교 |
| `animal_type` | 후보 `dog` `cat` `fox` `bear` `rabbit` `deer` `wolf` `hamster` — **조각 2에서 확정** | DESIGN §5.4 `animal-face-*` 일러스트 8종 |
| `impression_type` | `arab` `tofu` `kind` `chic` `innocent` | DESIGN §8.5 아랍상·두부상·선한상·시크상·청순상 |
| `acquisition_channel` | `everytime` `instagram` `friend` `community` `other` | DESIGN §9 화면 20d |
| `avatar_status` | `pending` `ready` `failed` | 제안 |
| `card_source` | `daily` `purchased` | §4 |
| `card_decision` | `accept` `reject` | §4 |
| `paid_card_offer_status` | `offered` `purchased` `replaced` `expired` | §4 — 2026-10-10 운영 적용(`20261010020000`) |
| `trust_response` | `accept` `reject` | 설계 §2.5 |
| `device_platform` | `android` `ios` | 제안 |
| `report_target` | `profile` `message` `friend_review` `poll` | 조각6 — 2026-09-27 적용. 앱 신고 입구는 `profile` · `message` · `friend_review`(받은 사람만), `poll` 은 아직 422 |
| `report_status` | `open` `actioned` `dismissed` | 조각6 — 2026-09-27 적용 |
| `report_reason` | `abuse` `sexual` `spam` `fake` `other` | 조각6 — 2026-09-27 적용(검토10 해결). 화면: 욕설·비방·혐오 / 성적 불쾌감 / 광고·스팸 / 사칭·허위 / 기타 |
| `store_platform` | `play_store` `app_store` | §6 — 2026-10-13 운영 적용(`20261013010100`, 종전 "제안") |
| `purchase_status` | `granted` `refunded` | §6 — 2026-10-13 운영 적용(`20261013010100`). **종전 제안 `verified` 를 `granted` 로 바꿨다** — 대기(pending) 결제는 행을 만들지 않아 "확인됨" 과 "지급됨" 을 가를 일이 없다 |
| `heart_reason` | `purchase` `referral` `promo` `free_task` `poll_vote` `extra_card` `avatar_regen` `refund` `admin_adjust` `first_purchase_bonus` | 환불 회수와 운영 보정 포함. 앞의 9값은 2026-09-20 적용(`20260920043832`). **`first_purchase_bonus` 는 2026-10-13 운영 적용**(`20261013010000` — enum 값은 같은 트랜잭션에서 못 써 쓰는 마이그레이션과 파일을 나눴다). 인앱결제 지급은 `purchase`, 환불 회수는 `refund` 를 쓴다(§6) |
| `heart_task` | `everytime_post` `kakao_share` | DESIGN §8.10 — 2026-09-28 적용 |
| `submission_status` | `submitted` `approved` `rejected` | DESIGN §8.10 — 2026-09-28 적용 |
| `heart_task_reject_reason` | `date_missing` `not_verified` `reused` | 2026-09-28 적용(무료 하트 D3) — 화면: 날짜가 안 보여요 / 게시글·공유가 확인되지 않아요 / 이미 쓴 캡처예요 |
| `content_status` | `visible` `blinded` | 설계 §2.8 — 2026-09-27 적용(`polls`) · `friend_reviews` 도 씀 |
| `poll_choice` | `a` `b` | DESIGN §8.11 — 2026-09-27 적용 |
| `faq_category` | `card_matching` `heart_payment` `photo_profile` `friend_review` `safety` `account` | DESIGN §8.13 — 2026-09-29 적용. 이 순서가 화면 탭 순서다 |
| `consent_kind` | `terms` `privacy` `sensitive_religion` `overseas_transfer` | 가입 동의(02-c) 필수 항목. **`sensitive_religion` · `overseas_transfer` 안 씀(09-29 사용자 결정** — 종교는 개인정보 수집·이용 안에, OpenAI 국외 이전은 처리방침 공개로 대신. 운영에 적용된 enum 이라 값만 남음) · 마케팅(선택)은 `notification_settings.marketing` |

## 9. Storage 버킷

모든 버킷은 비공개이고 클라이언트용 Storage 정책을 두지 않는다. 업로드는 FastAPI가 발급한 서명 업로드 URL로, 조회는 FastAPI가 발급한 서명 URL로만 한다(설계 §7.4, §2 쓰기 원칙).

**2026-09-29 정정 — 실제와 다른 두 곳.** ① **업로드는 서명 업로드 URL 이 아니라 FastAPI 가 multipart 로 받아 `service_role` 로 올린다**(학생증 · 실사진 · 무료 하트 인증샷 모두 — 매직바이트를 서버가 먼저 확인한다). 조회 서명 URL 은 그대로다. ② **`avatars` 는 공개 버킷이다**(2026-09-20 사용자 결정, 마이그레이션 `20260920043723`, 검토2 해결) — 항상 노출되는 만화 아바타라 공개 URL 로 준다. 탈퇴 30일 정리 배치는 사람마다 `{profile_id}/` 폴더가 있는 **네 버킷**(`avatars` · `profile-photos` · `student-id-temp` · `heart-task-proofs`)을 비운 뒤 계정을 지운다

| 버킷 | 공개 | 조각 | 내용 |
| --- | --- | --- | --- |
| `profile-photos` | 비공개 | 0 | 실사진 2~4장. 서명 URL은 본인과, 신뢰 확인을 통과한 상대에게만 준다. 사진 주인이 탈퇴(`withdrawn`)하면 남은 상대에게도 주지 않는다(§3). 이미 발급한 서명 URL 은 만료까지 열리므로 실사진 서명 URL 만료는 짧게 둔다(조각 5). **제한: 파일 10MB · `image/jpeg` `image/png`**(2026-09-14 사용자 결정, 조각 0 파일은 두고 조각 1 마이그레이션에서 추가 · 클라우드 적용됨(2026-09-20)) — 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다. 파일 내용(매직 바이트) 검사는 FastAPI 가 한다 |
| `avatars` | **공개**(2026-09-20 결정) | 2 | 만화 아바타. 항상 노출되는 이미지라 공개 버킷으로 바꾸자는 안은 설계 §7.4 예외라서 조각 2에서 결정 — 검토2 → **공개로 확정**(위 정정 ②) |
| `heart-task-proofs` | 비공개 | 무료 하트(2026-09-28 적용) | 무료 하트 인증샷. **제한: 파일 10MB · `image/jpeg` `image/png`**. 경로 `{profile_id}/{submission_id}.jpg`(png 면 `.png`). 올리기 · 지우기 모두 FastAPI(`service_role`). 검수 끝나고 60일 뒤(하루 100장씩) · 탈퇴 정리 때 지운다 |
| `graduate-cert-temp` | 비공개 | 2026-10-19 졸업생 인증 | 졸업증명서 사진. **제한: 파일 10MB · `image/jpeg` `image/png`**(버킷 제한은 신고된 타입만 막으므로 매직바이트는 FastAPI 가 올리기 전에 본다). 경로 `{profile_id}/{request_id}.jpg`(png 면 `.png`). 올리기 · 지우기 모두 FastAPI(`service_role`), 클라이언트 정책 없음. **결정(승인 · 반려 · 취소 · 만료) 즉시 서버가 지우고, 못 지우면 매시 배치(`/batch/chat-gate`)가 지운다.** 신청 중에도 14일을 넘기지 못한다. 탈퇴 · 14일 정리 때 폴더째 비운다. 옛 `student-id-temp` 와 섞지 않는다 |
| `student-id-temp` | 비공개 | 1 | 학생증 사진. 자동 대조 실패 시 사람이 재검토해야 해서(설계 §7.3) **검증이 끝날 때까지만 임시 보관하고, 끝나면 즉시 삭제**한다. **구현(2026-09-20 정정, PR #43) — Postgres 트리거가 아니라 FastAPI 가 Storage API로 직접 지운다**: `profiles.student_verification` 을 `verified`/`rejected` 로 확정한 직후 FastAPI 가 그 사람의 최근 제출 파일을 Storage API `DELETE`로 지운다. `delete from storage.objects` 트리거(`student_verification_finalized`, 마이그레이션 `20260919181357`)는 `storage.objects` 메타 행만 지우고 실제 파일 객체는 고아로 남기기 때문에 폐기했다(클라우드에 적용된 적 없음, 파일도 삭제) — Supabase Storage 문서상 파일 삭제는 Storage API를 거쳐야 한다. 삭제 실패는 인증 결과(성공)에 영향을 주지 않고 로그와 디스코드 알림으로만 남으며, 고아 파일은 대시보드에서 손으로 지운다(SUPABASE.md §7). 보관 기간을 따로 두지 않는다. **2026-10-11 사용자 결정으로 개정(PR #463) — 종전 "대시보드 수동 확정 뒤에는 손으로 지운다 · 보관 기간을 따로 두지 않는다"**: 지우는 곳이 셋이다 — ① 자동 통과 직후 FastAPI(`router`) ② 사람이 대시보드에서 확정한 직후 검토 결과 훅(`review_hook`, 최근 제출의 `result` 가 `pending` 이 아닐 때만) ③ 매시 `chat-gate` 배치(`retention`) — 검토가 끝났는데 남은 사진을 지우고, **검토 대기 30일**을 넘긴 시도는 반려로 닫은 뒤 사진을 지운다(§3 `student_verification_attempts`). 그래서 시도 행이 있는 사진은 제출 뒤 30일(+ 배치 한 시간)을 넘겨 남지 않고, 손으로 지울 일은 없어졌다. 버킷 404(이미 없음)는 삭제 성공으로 친다. **알려진 빈틈(2026-10-12 문서 정리에서 확인)**: 배치는 버킷 경로로 시도 행을 찾아 판단하므로, 업로드는 됐는데 시도 행 기록 전에 요청이 실패한 사진(시도 행 없음)은 지우지 않는다 — 탈퇴 정리 때까지 남는다(`retention.py` "시도 행이 없으면 … ①이 30일에 맡는다" 는 행이 곧 생기는 경우만 덮는다). 검증이 끝나기 전에 탈퇴한 사람의 파일은 탈퇴 즉시(30일 보관 예외, §11-19), 가입 도중 이탈한 사람의 파일도 FastAPI 가 지운다(이탈 판단 시점은 조각 1에서 정한다). **제한: 파일 10MB · `image/jpeg` `image/png`**(2026-09-14 사용자 결정) — 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다. 버킷 제한은 업로드 쪽이 신고한 content type 과 크기로만 막으므로(413 · 400), 파일 내용(매직 바이트)은 FastAPI 가 업로드 뒤 대조 전에 검사한다(조각 1 서버) |

## 10. 조각 0 마이그레이션 범위 → `docs/ERD_DECISIONS.md` §10

2026-09-14 클라우드 적용 완료. 실제 SQL 은 `supabase/migrations/` 의 조각 0 파일 4개(`20260913054542` ~ `20260913054549`)이고, 적용 범위 기록은 `docs/ERD_DECISIONS.md` §10 에 옮겼다.

## 11. 결정 기록 → `docs/ERD_DECISIONS.md` §11

2026-09-13 ~ 09-14 사용자 결정 1~25 는 `docs/ERD_DECISIONS.md` §11 에 번호 그대로 옮겼다(2026-09-14 문서 정리). 새 결정도 그 표에 이어서 적는다.

## 12. 남은 검토

해결된 번호(1 · 4 · 15~19 · 22~33)는 `docs/ERD_DECISIONS.md` §12 에 번호 그대로 옮겼다. 새 검토는 37번부터 이 표에 잇는다.

| # | 내용 | 조각 | 근거 |
| --- | --- | --- | --- |
| 2 | 해결(2026-09-20) — `avatars` 는 공개 버킷(§9 정정 ②) | 2 | 설계 §7.4 |
| 3 | 조각 번호가 없는 기능: 지인 리뷰·커뮤니티·FAQ·프로모션 코드. (추천인은 설계 §2.7에 조각 7, 커뮤니티 도입 자체는 설계 미결14에서 확정). **2026-09-29 개정 — 조각 번호 대신 기능 탭 단위로 만들었다**: 커뮤니티 = 커뮤니티 탭(2026-09-27 앞당김) · 추천 = 2026-09-28 · 지인 리뷰 = 2026-09-28 ~ 29 · FAQ = 2026-09-29 · 무료 하트 인증 = 2026-09-28(모두 적용됨). **남은 것은 프로모션 코드(`promo_codes` · `promo_redemptions`) 하나** — 발급 규칙 미정, 표 없음 | — | 설계 §3.1 |
| 5 | **해결(2026-09-22 사용자 결정 · 2026-09-27 적용) — 유니크를 걸지 않는다**(§5 설명). 종전: "한 번호 한 계정" 규칙 여부 → `phone_hmac` 유니크 여부. 문서에는 추천 보상 한정 동일 번호 차단(§2.7)만 있다. 유니크로 정하면 탈퇴 뒤 30일 동안 `profile_private` 가 남아(§11-19) 같은 번호로 다른 메일 가입도 막힌다(메일 기준 `signup_blocks` 와 별개) | 6 | 설계 §2.7 |
| 6 | 추천 어뷰징 "동일 기기 차단"의 기기 식별값 저장처 | 7 | 설계 §2.7 |
| 7 | 해결(2026-09-28) — 지인 리뷰 태그 최소 1 · 최대 3(check `friend_reviews_tags_count`). 종전: 지인 리뷰 태그 최소 개수 (DESIGN §13-25는 최대 3개만 정함) | — | DESIGN §13-25 |
| 8 | `animal_type` 최종 값 | 2 | DESIGN §5.4·§8.5 |
| 9 | **해결(2026-09-22 결정 · 2026-09-27 적용) — 행마다 `key_version`**(`contact_blocks` · `signup_blocks` · `profile_private.phone_hmac_key_version`, 지금 1), 대조는 같은 버전끼리, 옛 키 30일 보관, 정기 교체 없음. 정리 배치가 옛 버전 행 수를 매일 센다. 종전 내용: HMAC 키 교체 절차 — `phone_hmac` · `contact_hmac` · `signup_blocks.email_hmac` 세 곳에 같이 걸린다. `signup_blocks` 는 원본 메일이 없어 새 키로 재계산할 수 없다. `contact_hmac` 도 원본을 서버에 두지 않아 같다(§5). 새 키로 다시 계산할 수 있는 것은 `profile_private` 의 번호 암호문이 있는 `phone_hmac` 뿐이다. `contact_blocks` 행이 남아 있거나 `blocked_until` 이 `infinity` 인 행이 있으면 옛 키를 계속 보관해야 한다. 안 그러면 §5 대조(`contact_hmac` = `phone_hmac`)가 오류 없이 끊겨 지인 차단이 풀린다 | 6 | 설계 미결36 |
| 10 | 해결(2026-09-27) — enum `report_reason` 5값(§8) | 6 | 설계 §2.8 |
| 11 | DESIGN 16d "내 글의 새 댓글" 토글 — 댓글 도입 전까지 컬럼 없음, 도입 때 `notification_settings` 에 추가. 이번 스코프 한정 결정이라 DESIGN 은 지금 고치지 않는다 | 4 | DESIGN §8.11 · §9 16d |
| 12 | 받은 수락함에도 "거절한 상대는 다시 나오지 않는다"를 적용할지 — B가 이미 거절한 A의 수락은 B의 수락함에 넣지 않는다(A에게는 무응답과 같다) | 4 | 설계 §2.1 |
| 13 | 내 받은 수락함에 대기 중인 상대를 카드 하드 필터에 넣을지 | 4 | 설계 §6.7 |
| 14 | 대기 중인 수락의 만료 기한 | 4 | 설계 §2.1 |
| 20 | 학교 메일로 가입한 뒤 이메일 변경(`updateUser`)으로 아무 메일로 바꾸는 우회 — 이메일 변경을 막거나 변경 때도 도메인을 검사한다 | 1 | 설계 §7.3 |
| 21 | FastAPI 가 PostgREST 가 아니라 DB 에 직접 붙을 때 쓸 DB 역할. 지금 grant 는 `service_role` 전제 | 1 | ERD §2 |
| 34 | Supabase advisor 보안 WARN 0028 · 0029 → 결정(다음 클라우드 쓰기 때 revoke, 2026-09-14 사용자 결정) — `public.rls_auto_enable()`(SECURITY DEFINER, owner `postgres`, event trigger `ensure_rls` 가 부름)을 `anon` · `authenticated` 가 RPC 로 실행할 수 있다고 뜬다. 우리 마이그레이션 파일에는 없고, 프로젝트를 만들 때 켠 자동 RLS 옵션이 만든 것으로 보인다. 반환형이 `event_trigger` 라 RPC 로 부르면 "trigger functions can only be called as triggers" 로 막히고 본문도 `pg_event_trigger_ddl_commands()` 만 써서, 실제 위험이 아니라 lint 성 경고로 판단한다. 지금은 조치하지 않고, 다음 클라우드 쓰기 승인 때 `revoke execute on function public.rls_auto_enable() from anon, authenticated, public` 을 같이 묶는다. 로컬 fresh DB 에는 이 함수가 없으니 그 마이그레이션은 함수 존재를 확인하는 guard 가 필요하다 | 1 | Supabase advisor 0028 · 0029 |
| 35 | pgTAP `supabase/tests/rls_slice0_test.sql`(21개 항목)은 작성만 하고 실행하지 않았다 — 로컬에 Docker 가 없다 | 0 후속 | 계획서 Task 8 |
| 36 | 완료(2026-09-20) — "찾는 성별" 폐지(반대 성별 자동 매칭, 2026-09-14 사용자 결정) 뒤처리. 조각 0 에 적용됐던 `profiles.looking_for` 컬럼과 `active` 전환 check 의 `looking_for is not null`(§3)을 조각 2 프로필 마이그레이션에서 삭제했다. 조각 0 마이그레이션 파일은 고치지 않았다 | 2 | DESIGN §13-113 · 설계 §6.1 · §6.8 |

## 13. 문서 갱신 대상 → `docs/ERD_DECISIONS.md` §13

2026-09-14 기준 전부 반영했고, 목록은 `docs/ERD_DECISIONS.md` §13 에 옮겼다.

---

## 갱신 이력 (2026-10-20 · 10-27 문서 정리로 맨 위에서 옮겼다 — 내용은 그대로)

<details><summary>날짜별 상태 줄 열기 (조각 0 ~ 2026-10-20)</summary>

> **상태: 초안 v3 (2026-09-13 ~ 09-14) · 2차 검수 반려 반영 · 최종 검토 반영 · 탈퇴 정책 결정 반영 · 조각 0·조각 1(1a·1b) Supabase 적용 완료(1a·1b 는 2026-09-20, MCP `apply_migration`).** 조각 0 은 `supabase/migrations/` 4개 + `seed.sql` 로 적용됐다. 조각 1(1a 이메일 인증 훅·1b 학생증 인증)은 마이그레이션 11개(학생증 사진 삭제 트리거였던 `20260919181357` 은 클라우드에 올린 적 없이 폐기·삭제, PR #43)와 `supabase/tests/rls_slice1_test.sql` 을 클라우드에 적용했다(자세한 상태는 `docs/SUPABASE.md` §1). 조각 2 이후는 파일 없음. **PR #99(`20260924163241`, 2026-09-25) 로 `profile_avatars.storage_path` not null 해제 + check 추가 적용됨** — 자세한 상태는 `docs/SUPABASE.md` §1.
> **2026-09-29 문서 정리 갱신.** 조각 6(신고 · 차단 · 지인 차단 · 탈퇴) · 커뮤니티 · 추천 · 무료 하트 인증 · 지인 리뷰 · 코호트 · 가입 동의 · FAQ 까지 저장소 `supabase/migrations/` 가 **52개**이고, 운영(Supabase)에는 마지막으로 `create_faq`(운영 기록 `20260929054505`)와 그 앞 `create_user_consents`(`20260929051356`)가 적용됐다(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 아래 각 표의 "조각N 제안" 표시는 만들 때의 기록이고, 실제로 만든 칸은 이번 정리에서 "적용됨" 으로 바꿨다.
> **2026-10-09 갱신(소셜 로그인 전환).** 저장소 `supabase/migrations/` 가 **61개**다. 마지막 네 파일 `20261008010000`(학교 없는 pending 프로필) · `20261008020000`(소셜 이름 지우기 트리거) · `20261008030000`(`school_email_claims` · 정리 · 인증 완료 함수) · `20261008040000`(이메일 해시 없는 탈퇴)이 **2026-10-09 운영에 적용됐다**(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 반영 위치: §1 조감도 · §2 표 · §3 `profiles` · `school_email_claims` · 트리거 · 함수, §5 `withdraw_account`. **데이터 이전**: 기존 사용자 25명(대장 전달 값)은 `school_email_verified_at` = 가입 시각(`created_at`, `20261008010000` 의 update)으로, `school_email_claims` 는 `provider = 'email'` 로 채웠다(`backend/scripts/backfill_school_email_claims.py` — HMAC 키가 서버에만 있어 SQL 로 못 채운다).
> **2026-10-10 갱신(카드 선정 · 유료 카드).** 저장소 `supabase/migrations/` 가 **66개**다(PR #442 merge 뒤 main 기준). 새로 생긴 다섯 파일: `20261010010000`(`match_candidates` 반환을 jsonb 배열 + `pickable` 로) · `20261010020000`(`paid_card_offers`) · `20261010030000`(`purchase_paid_card`) · `20261010040000`(`notifications`) · `20261010050000`(유료 카드 주기당 한 장을 막는 부분 유일 인덱스 교체, PR #442)는 모두 **2026-10-10 운영에 적용됐다**(대장 전달 값: 운영 마이그레이션 66개 확인 — 이 문서 담당이 클라우드를 조회하지 않았다). 반영 위치: §1 조감도 · §2 표 · §4(`daily_cards` 옆 두 표와 함수) · §8 `paid_card_offer_status`. `notifications` 의 90일 보관 정리는 서버 배치 몫이고 구현 중이다(마이그레이션에는 없다).
> **2026-10-12 갱신(실명 · 카톡 암호화 · 학생증 사진 정리).** 저장소 `supabase/migrations/` 가 **67개**다. 새 파일 `20261011010000`(실명 · 카톡 암호화 M1 — `profile_private.real_name_enc` · `kakao_id_enc` + 함수 4개)이 운영에 적용됐다(대장 전달 값: 운영 67개 — 이 문서 담당이 클라우드를 조회하지 않았다). 백필 끝(2행, 불일치 0), 옛 평문 열을 지우는 M2 는 아직이다. 학생증 사진 정리(검토 대기 30일 상한 · 사람 확정 뒤 삭제, 2026-10-11 사용자 결정)는 스키마 변경 없이 서버 코드로 했다. 반영 위치: §2 `profile_private` 행 · §3 `profile_private` · `student_verification_attempts` · §9 `student-id-temp`. (위 10-10 줄의 `notifications` 90일 정리도 그 뒤 매시 `chat-gate` 배치에 들어갔다 — `backend/DEPLOY.md` §4-1.)
> **2026-10-12 저녁 갱신(M2 — 평문 열 삭제).** 운영 마이그레이션 **68개**(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 새로 적용된 `20261012010000_drop_plaintext_real_name_and_kakao_id`(운영 기록 버전 `20261012070722`)가 `profile_private.real_name` · `kakao_id` 평문 열과 함수 `backfill_profile_private_encryption` 을 지웠다 — 실명 · 카톡 아이디는 암호문 `real_name_enc` · `kakao_id_enc` 에만 있다(ERD_DECISIONS §11-30). **파일은 DB PR #476(draft) merge 대기**라 저장소 main 은 아직 67개다. 반영 위치: §2 `profile_private` 행 · pgTAP 기대값 · §3 `profile_private` 그림 · 주석.
> **2026-10-14 갱신(인앱결제 · 채팅 실시간 · 읽음 '1').** 저장소 `supabase/migrations/` 가 **71개**다(main `455ccae7` 기준 — 위 10-12 저녁 줄의 M2 파일은 DB PR #476 merge 로 저장소에도 들어왔다). 새로 생긴 세 파일: `20261013010000_add_heart_reason_first_purchase_bonus`(`heart_reason` 에 `first_purchase_bonus`) · `20261013010100_billing_purchases`(`purchases` 표 · enum 두 개 · 함수 `grant_store_purchase` · `refund_store_purchase`, PR #498) · `20261013152736_user_channel_realtime_policy`(`realtime.messages` 받기 정책 `user_channel_read_own`, PR #512). 운영 마이그레이션도 **71개**이고 마지막은 `user_channel_realtime_policy`(원격 버전 `20261013154505` — 파일 이름 타임스탬프와 다른 것은 `docs/SUPABASE.md` §4 관례대로 정상)다(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 반영 위치: §2 표(`match_participants` · `realtime.messages`) · §4 `match_participants.last_read_at`(상대에게 보이는 읽음 '1', 2026-10-13 사용자 결정) · §6 `purchases` · §8 `store_platform` · `purchase_status` · `heart_reason`.
> **2026-10-14 밤 갱신(FAQ 문구).** 저장소 `supabase/migrations/` 가 **72개**다(main `ed644ad5` 기준). 새 파일 `20261014120000_faq_avatar_regen_cost_20` 은 **스키마를 바꾸지 않는다** — `faq` 답변 두 곳("하트는 어디에 쓰나요?" · "아바타를 다시 만들 수 있나요?")의 아바타 다시 만들기 값 숫자만 10 → 20 으로 바꾸는 데이터 갱신이다(`replace` 라 두 번 돌려도 같다, 5회 실패 보상 10하트 구절은 그대로). 운영 마이그레이션도 **72개**이고 마지막은 `faq_avatar_regen_cost_20`(원격 버전 `20261014080438` — 파일 이름 타임스탬프와 다른 것은 `docs/SUPABASE.md` §4 관례대로 정상)이다(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 반영 위치: §6 `grant_hearts` 줄. `purchases.store = app_store` 규칙은 위 10-14 줄 · §6 에 이미 있어 다시 적지 않았다.
> **2026-10-15 갱신(커뮤니티 탭 · 문의 메일).** 저장소 `supabase/migrations/` 가 **74개**다(main `854d29b7` 기준). 73번째 `20261014130000_faq_support_email`(PR #533)은 스키마를 바꾸지 않는다 — `faq` 답변의 옛 문의 메일을 새 주소로 바꾸는 `update ... replace` 다. **운영 마이그레이션은 73개이고 마지막은 `faq_support_email`** 이다(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). **74번째 `20261015120000_poll_feed_tabs`(PR #540)는 저장소에만 있고 운영 미적용**이다 — 함수 `poll_feed` 를 지우고 `p_tab` 칸을 더해 다시 만든다(표 · 인덱스 · 데이터 변경 없음, §7). 반영 위치: §7 `poll_feed`.
> **2026-10-17 갱신(무료 하트 조정 · 가입 확정 위치).** 저장소 `supabase/migrations/` 가 **76개**다(main `fccc5e2d` 기준). 새 두 파일은 **표 · 열을 바꾸지 않는다**: `20261016144525_poll_vote_reward_5_cap_15`(함수 `poll_vote_reward_due` · `cast_poll_vote` 안 숫자만 하루 첫 투표 10 → **5**, 주 상한 30 → **15** — `create or replace`, 이름 · 인자 · 반환형 · 권한 그대로) · `20261016144530_faq_free_heart_amounts`(`faq` 답 한 줄의 무료 하트 숫자 · "학교 단톡방" → "단톡방" `update … replace`, PR #570 · #573). **운영**: 10-15 줄의 `poll_feed_tabs` 는 2026-10-15 밤 운영에 적용돼 운영 74개가 됐고(`backend/DEPLOY.md` §5), 새 두 파일도 2026-10-16 운영에 적용돼 **운영 76개 = 저장소 76개**다(대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 스키마 변경 없이 바뀐 것: 서버가 `profiles.status` 를 `pending` → `active` 로 바꾸는 자리가 하나 늘었다(§3 `profiles` 2026-10-17, 서버 PR #574 — 2026-10-17 배포, 리비전 `00083-pwx`). 반영 위치: §3 `profiles` · §6 하트 · §7 `poll_vote_reward_due` · §8 열거형 `profile_status`.
> **2026-10-19 갱신(관리자 웹 · 졸업생 인증 · 인증샷 여러 장 · 저녁 알림 — 10-17 줄 이후 17개를 한꺼번에 적는다).** 저장소 `supabase/migrations/` 가 **93개**이고 운영도 **93개**다(main `fc430713`, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다. 10-18 밤 11개로 89개, 10-19 네 파일로 93개. 원격 버전은 적용 시각이라 파일 이름과 다르다 — 10-19 의 네 개는 `20261019055736` · `055756` · `055818` · `055824`, `docs/SUPABASE.md` §4). 76번째 뒤 17개: **새 표 4개** — `unknown_email_domain_attempts`(`20261017120000`) · `admin_users`(`20261018002858`) · `admin_actions`(`20261018002902`) · **`graduate_verification_requests`**(`20261019200000`, 졸업생 인증) + 버킷 `graduate-cert-temp`. **칸 변경** — `profiles.verification_method` · `graduate_verified_at`(`20261019200000`), `heart_task_submissions.storage_path` → **`storage_paths text[]`**(`20261019100000`), `notification_settings.quiet_hours` 기본값 `false`(`20261019210000`). **함수·제약만** — `20261018002907`(`list_unverified_accounts` 에 관리자 제외) · `20261018011200`/`030000`/`035204`/`120000`/`140000`/`150000`(관리자 조치 · 통계 함수, 전부 읽기 또는 `admin_actions` 한 줄과 한 트랜잭션) · `20261018100000`(`profile_avatars_one_fallback` 유일 인덱스 — 기본 아바타 보상 하트가 두 번 나가는 경쟁 차단) · `20261018130100`(`notifications.kind` check 에 `heart_task_approved` · `heart_task_rejected`) · `20261019200100`(졸업생 승인 · 반려 함수 + `list_unverified_accounts` 교체) · `20261017130000`(FAQ 5문항 문구, 데이터만). 반영 위치: §1 조감도 · §2 접근 표 · §3 `profiles` · `graduate_verification_requests` · §4 `notification_settings` · §6 `heart_task_submissions` · §7 관리자 표 · §9 버킷 `graduate-cert-temp`. 결정 배경은 `docs/decisions/2026-10-19-graduate-verification-decision.md` 와 `ERD_DECISIONS.md` §11-31 ~ 33.
> **2026-10-20 갱신(문서 정리 때의 현재 상태 — 2026-10-27 문서 정리로 이력에 옮겼다, 내용 그대로).** 저장소 `supabase/migrations/` **96개 = 운영 96개, 모두 적용**이다(마지막 `20261020110000_close_seoul_schools_until_cohort_open`, 대장 전달 값 — 이 문서 담당이 클라우드를 조회하지 않았다). 조각 0 ~ 7, 소셜 로그인 전환, 인앱결제, 관리자 웹, 졸업생 인증까지 표 · 열 · 함수가 모두 이 문서에 들어 있다. 학생증 · 실명 사진 인증은 2026-10-17 에 폐지했고 졸업생 길(졸업증명서 + 관리자 검수)이 2026-10-19 에 들어왔다. **10-19 이후 새 마이그레이션 3개는 표 · 열을 바꾸지 않는다**: `20261019220000_admin_billing_returned_accounts`(읽기 함수 `admin_billing_returned_accounts(p_limit)` — 관리자 결제 화면 "환불이 잦은 계정", §7) · `20261020100000_faq_support_email_change`(`faq` 답변의 문의 메일만 `replace`, 데이터) · `20261020110000_close_seoul_schools_until_cohort_open`(`universities.card_opens_at` 데이터 — 서울 학교 64곳을 2026-11-02(월) 07:00 KST 로, §3). 날짜별 갱신 줄(조각 0 ~ 1 적용 상태 포함)은 문서 맨 아래 "갱신 이력" 에 그대로 있다. 원격 버전은 적용 시각이라 파일 이름과 다른 경우가 있다(`docs/SUPABASE.md` §4 관례).

</details>
