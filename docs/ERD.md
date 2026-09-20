# CampusMate DB ERD

> **상태: 초안 v3 (2026-09-13 ~ 09-14) · 2차 검수 반려 반영 · 최종 검토 반영 · 탈퇴 정책 결정 반영 · 조각 0·조각 1(1a·1b) Supabase 적용 완료(1a·1b 는 2026-09-20, MCP `apply_migration`).** 조각 0 은 `supabase/migrations/` 4개 + `seed.sql` 로 적용됐다. 조각 1(1a 이메일 인증 훅·1b 학생증 인증)은 마이그레이션 11개(학생증 사진 삭제 트리거였던 `20260919181357` 은 클라우드에 올린 적 없이 폐기·삭제, PR #43)와 `supabase/tests/rls_slice1_test.sql` 을 클라우드에 적용했다(자세한 상태는 `docs/SUPABASE.md` §1). 조각 2 이후는 파일 없음.
> 근거: 설계 문서 `docs/superpowers/specs/2026-09-05-campusmate-foundation-design.md` (§2·§5·§6·§7·§13), `frontend/docs/DESIGN.md` (§5.2·§8·§9), 2026-09-13 ~ 09-14 사용자 결정(§11).

## 읽는 법

- 컬럼 주석 맨 앞의 **`조각N`** = 그 컬럼·테이블을 추가하는 조각. 조각을 시작할 때 추가한다(설계 §5.4)
- **`제안`** = 스펙에 없어서 이 ERD가 제안하는 것
- **`검토N`** = 아직 정해지지 않은 것. 번호는 §12 "남은 검토"
- **`민감`** = 남에게 가는 응답에 절대 담지 않는 값(설계 §7.1). 민감 값은 `profile_private` 에만 둔다
- 컬럼 없이 계산하는 값: 가입 나이 자격(Asia/Seoul 기준 올해 − `birth_year` ≥ 19, FastAPI 검사), 신뢰 확인 기한(`matches.created_at` + 48시간), 안 읽은 메시지 수(상대가 보낸 메시지 중 `created_at` > 내 `match_participants.last_read_at`), 아바타 교체 무료 여부(`profile_avatars` 성공 건수), 주기당 추가 카드 1장(`daily_cards.source`), 월간 추천 랭킹(`referrals` 집계, 탈퇴자 제외 §3. 계정 삭제 cascade 로 지난달 행이 줄 수 있어 월말에 순위를 확정해 지급한다 — 조각 7)

## 1. 조감도

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    auth_users ||--o| profiles : "id 공유 · 가입 도중 이탈하면 없음"
    universities ||--o{ university_email_domains : "메일 도메인"
    universities ||--o{ profiles : "소속"
    region_group_settings ||..o{ universities : "region_group"
    profiles ||--o| profile_private : "민감 정보"
    profiles ||--o{ student_verification_attempts : "학생증 제출"
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

관계가 없는 독립 테이블: `signup_blocks`(탈퇴 후 재가입 제한), `faq`.

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
| `profile_private` | 본인 행 (`profile_id`) · 컬럼 grant `profile_id` · `real_name` 만 | 16e 본인 실명 조회. 번호 암호문·`phone_hmac`·카카오톡 아이디는 내려가지 않는다. 앱은 `select *` 대신 컬럼을 지정한다. 본인 `kakao_id`(16e · 14f · 16e-1)는 FastAPI 가 내려준다(§11-20) |
| `student_verification_attempts` | 없음 | FastAPI 전용 — 본인 반려 사유는 FastAPI 응답으로 내려주고, 재시도 횟수는 행 수로 FastAPI 가 센다(§12-4) |
| `profile_photos` · `profile_avatars` · `survey_answers` | 본인 행 (`profile_id`) | |
| `profile_vectors` | 없음 | FastAPI 전용 |
| `daily_cards` · `card_decisions` · `acceptance_responses` | 없음 | FastAPI 전용 — 카드 화면에는 상대 정보가 섞인다 |
| `matches` | 당사자 (`profile_a` · `profile_b`) | 둘 다 알아도 되는 값만 있다 |
| `match_participants` | 본인 행 (`profile_id`) | 상대의 게이트 응답·채팅방 나가기는 보이지 않는다 |
| `messages` | 참여 중인 매칭의 메시지 | `exists (select 1 from match_participants mp where mp.match_id = messages.match_id and mp.profile_id = (select auth.uid()) and mp.left_at is null)` |
| `push_tokens` | 없음 | FastAPI 전용 |
| `notification_settings` | 본인 행 | |
| `blocks` · `reports` | 없음 | FastAPI 전용 — 차단 목록(16f)은 상대 닉네임이 필요하다 |
| `contact_blocks` | 본인 행 (`owner_id`) · 컬럼 grant `id` · `owner_id` · `created_at` 만 | 16b 목록. `contact_hmac` 은 내려가지 않는다 |
| `entitlements` · `heart_transactions` · `purchases` · `heart_task_submissions` | 본인 행 | 잔액·내역·인증 상태 |
| `referrals` · `friend_reviews` | 없음 | FastAPI 전용 |
| `polls` · `poll_votes` | 없음 | FastAPI 전용 — `author_id` 를 열면 익명이 깨지고(DESIGN §8.11), `poll_votes` 는 본인 행만 열면 집계가 안 되고 다 열면 누가 뭘 골랐는지 보인다 |
| `faq` | `authenticated` 전체 | |
| `signup_blocks` · `promo_codes` · `promo_redemptions` | 없음 | 서버 전용 |

사이클 B pgTAP 기대값의 기준:

- 읽기가 있는 테이블: 남의 행 0행. `match_participants` 는 같은 매칭 상대의 행도 0행, `messages` 는 비당사자와 `left_at` 이 찍힌 본인 모두 0행
- 읽기가 없는 테이블(FastAPI · 서버 전용): 본인 행이라도 `select` 가 42501
- 컬럼 grant 테이블: `profile_private` 에서 본인 `select real_name` 은 1행, `select *` 는 42501(조각 1). 본인 `select kakao_id` 도 42501(§11-20)
- 모든 테이블: `anon` · `authenticated` 의 INSERT · UPDATE · DELETE 가 42501
- `anon` 은 `universities` · `university_email_domains` 읽기만 된다
- `profiles` 제약: 온보딩 컬럼 없는 `pending` 행 insert 는 성공, 필수값 없이 `active` 로 바꾸면 check 위반, 대소문자만 다른 닉네임은 unique 위반(§3)
- `service_role` 은 테이블마다 `select` · `insert` · `update` · `delete` 가 모두 있다. 하나라도 빠지면 FastAPI 쓰기가 깨진다
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
    profiles ||--o{ student_verification_attempts : "학생증 제출 한 번에 한 행"
    profiles ||--o{ profile_photos : "실사진 2~4장"
    profiles ||--o{ profile_avatars : "생성 이력"
    profile_photos |o--o{ profile_avatars : "원본 사진"
    profiles ||--o{ survey_answers : "9축"
    profiles ||--o| profile_vectors : "1행"

    universities {
        uuid id PK "조각0"
        text name UK "조각0"
        text region_group "조각0 · 첫 출시 seoul"
        timestamptz recruit_starts_at "조각4 제안 · 학교별 코호트 모집 시작"
        timestamptz card_opens_at "조각4 제안 · 학교별 첫 카드 지급일"
        timestamptz created_at "조각0"
    }

    university_email_domains {
        text domain PK "조각0 · 학생인증 화이트리스트 · 소문자"
        uuid university_id FK "조각0"
    }

    region_group_settings {
        text region_group PK "조각4 · 가칭"
        smallint[] issue_weekdays "지급 요일 · 초기 월목 · 성비 미달이면 1개"
        time issue_time "07:00 · Asia/Seoul"
        timestamptz updated_at
    }

    profiles {
        uuid id PK, FK "조각0 · auth.users.id"
        uuid university_id FK "조각0 · 메일 도메인으로 서버가 정함"
        text nickname UK "조각0 · lower 유니크 · 한글영문 2~5자"
        gender gender "조각0 · 하드 필터"
        smallint birth_year "조각0 · 연 나이 19세 이상"
        smallint height_cm "조각0 · 필수 · 공개"
        smallint preferred_height_min "조각0 · null이면 상관없음"
        smallint preferred_height_max "조각0"
        text bio "조각0 · self_text 원본"
        text mbti "조각0 · null이면 모름"
        jsonb preferred_mbti_flags "조각0 · 8극 토글"
        text major "조각0 · 표시만 · 조각1b부터 department 로도 별칭 응답"
        major_field major_field "조각0 · 표시만"
        smallint admission_year "조각0 · 21 입력을 2021로 저장"
        text student_number "조각1b · 자기 입력 · 학생증 대조 없음"
        text[] interest_tags "조각0 · 45개 풀 3~5개"
        profile_status status "조각0 · 기본 pending · withdrawn 은 조각6"
        timestamptz last_active_at "조각0 · 활동성 계수"
        timestamptz created_at "조각0"
        verification_status student_verification "조각1 · 기본 none · FastAPI 만 바꿈"
        timestamptz nickname_changed_at "조각2 · 30일 1회"
        boolean is_smoker "조각2 · 감점 계수"
        religion religion "조각2 · 감점 계수"
        animal_type animal_type "조각2 · 본인 1개"
        impression_type impression_type "조각2 · 본인 1개"
        animal_type[] preferred_animal_types "조각2 · 최대 3 · 빈 배열이면 상관없음"
        impression_type[] preferred_impression_types "조각2 · 최대 3"
        text[] my_traits "조각2 · 48개 풀 3~5개"
        text[] ideal_traits "조각2 · 45개 풀 3~5개"
        smallint preferred_age_min "조각2 · null이면 상관없음"
        smallint preferred_age_max "조각2"
        acquisition_channel acquisition_channel "조각2 · 20d 유입경로 · 선택"
        text acquisition_note "조각2 · 기타 한 줄"
        text ideal_note "조각2 · 이런 사람이 좋아요 자유 글 · 선택 · 빈 문자열=미입력, 매칭 임베딩에서 없음 처리"
        text bio_draft "조각2 · AI 자기소개 초안 저장본 · bio-draft 재호출 시 재생성 대신 이 값 반환"
        timestamptz bio_draft_generated_at "조각2 · 초안 생성 시각 · 1회 제한(설계 §13-71)"
        boolean matching_paused "조각4 · 일시중지 토글"
        timestamptz withdrawn_at "조각6 제안 · 탈퇴 요청 시각 · 30일 뒤 계정 삭제"
        text referral_code UK "조각7 · 가입 시 자동 발급"
    }

    profile_private {
        uuid profile_id PK, FK "조각1"
        text real_name "조각1 · 민감 · 3b 입력 · 학생증 이름 대조 · 본인만 16e 조회"
        text phone_number "조각2 · 민감 · 04-1 · 암호화 저장"
        bytea phone_hmac "조각6 · 민감 · 지인 차단 대조 · 유니크 여부 검토5"
        text kakao_id "조각2 · 민감 · 04-1b 가입 시 필수 입력(2026-09-14 개정, 종전 조각5 신뢰 확인 시점 수집) · 신뢰 확인 통과 후 상대에게만 · 주인이 withdrawn 이면 상대에게 주지 않음(§3)"
        timestamptz updated_at
    }

    student_verification_attempts {
        bigint id PK "조각1 · identity"
        uuid profile_id FK "조각1 · cascade"
        text file_path "조각1 · student-id-temp 객체 경로"
        verification_status result "조각1 · 기본 pending · none 불가"
        text reject_reason "조각1 · rejected 일 때"
        timestamptz submitted_at "조각1"
        timestamptz reviewed_at "조각1 · 판정 전 null"
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
        text storage_path "변환 결과"
        avatar_status status "pending ready failed"
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
        vector(512) self_text "bio 임베딩 · 현재 점수 미반영"
        timestamptz updated_at
    }
```

- `profiles` 폐기 컬럼 — 만들지 않는다: `hide_same_major`(설계 미결27), `ideal_description`(설계 미결33). `looking_for`는 조각0에 만들었다가 "찾는 성별" 폐지(반대 성별 자동 매칭, 2026-09-14 사용자 결정)로 조각2 마이그레이션에서 지웠다 — 조각0 마이그레이션 파일은 고치지 않았다(§12-36 완료)
- `profiles` 행은 FastAPI가 아니라 **`auth.users` INSERT 후 Postgres 트리거(`handle_new_user_profile`)**가 만든다(2026-09-18, FK 순서 문제로 정정 — §11-26). Before User Created 훅 시점엔 `auth.users` 행이 아직 커밋 전이라 거기서 `profiles` insert 를 하면 FK 위반이 난다. 3b의 `profile_private` 가 이 행을 FK로 가리키므로 먼저 있어야 한다. 클라이언트 INSERT는 없다(§2)
- **이 시점에 정해지는 `university_id`(메일 도메인으로) · `status`(`pending`)만 `not null` 이다.** 온보딩(DESIGN 04-1 이후)에서 받는 `nickname` · `gender` · `looking_for` · `birth_year` · `height_cm` 는 null 허용이고, 아래 check 로 필수값 없는 `active` 전환을 막는다. 조각 0 계획서 초안처럼 온보딩 컬럼을 `not null` 로 두면 FastAPI insert가 실패한다
  `check (status <> 'active' or (nickname is not null and gender is not null and looking_for is not null and birth_year is not null and height_cm is not null))`
- 가입 나이의 "올해"는 Asia/Seoul 기준이다(UTC 12월 31일 15:00 경계). check 에 `now()` 를 넣지 않고 FastAPI가 검사한다. DB에는 `now()` 없는 정적 범위 check만 둔다
- `profiles` 정적 check(조각 0): `nickname` 한글·영문 2~5자, `birth_year` 1950~2020, `height_cm` 120~230, `preferred_height_min` · `max` 도 120~230 이고 min ≤ max, `admission_year` 1950~2100(두 자리 입력을 그대로 저장하는 실수 방지), `mbti` `^[EI][NS][TF][JP]$`, `preferred_mbti_flags` 는 JSON 객체(키 E I N S T F J P, 값 boolean · true 가 ok, 설계 §6.4 — 기본 `{}` 는 전부 ok 와 같은 결과), `interest_tags` 5개 이하(하한 3개는 FastAPI 온보딩 완료 검사)
- 선호 키·나이 슬라이더(DESIGN `range-slider` 프리셋)의 끝 표기 "150cm 이하" · "190cm 이상" · "35세 이상"은 그쪽 경계를 null 로 저장한다. 끝값 150 을 그대로 저장하면 145cm 상대가 빠진다
- `profiles.university_id` 는 `on delete restrict` — 프로필이 남아 있는 대학은 지울 수 없다. `university_email_domains` 는 대학을 따라 cascade 로 지워진다
- `universities.name` 은 unique 다(시드가 이름으로 도메인을 짝짓는다). `university_email_domains.domain` 은 소문자 도메인 형식 check `^[a-z0-9-]+(\.[a-z0-9-]+)+$`. 도메인 1개는 대학 1개에만 속하고, 서울 밖 캠퍼스도 따로 나누지 않는다(§11-10)
- 조각 4에서 `universities.region_group` 에 `region_group_settings` FK 를 걸 때는 같은 마이그레이션에서 `seoul` 행을 먼저 넣는다
- 민감 값(`real_name` · `phone_number` · `phone_hmac` · `kakao_id`)은 `profile_private` 로 분리했다. 서버 코드가 남의 프로필을 `select *` 로 읽어도 민감 값이 딸려 나오지 않는다. 접근 감사 로그는 테이블 없이 FastAPI 구조화 로그로 남긴다(§11-13). 운영자도 FastAPI 관리 기능으로만 조회하고 Supabase 대시보드·SQL 로 직접 보지 않는다(§11-18)
- `student_verification` 은 boolean이 아니라 상태값(`none` `pending` `verified` `rejected`, 2026-09-14 확정)이다. 3b의 "조금 더 확인이 필요해요" 대기 상태를 담아야 하기 때문이다
- `student_verification_attempts` 는 학생증 제출 한 번에 한 행이다(§12-4, 2026-09-14 사용자 결정). 재시도 횟수(설계 미결3)는 이 테이블의 행 수로 FastAPI 가 세고, 반려 사유(`reject_reason`)는 본인에게 FastAPI 응답으로 내려준다. `result` 는 제출 직후 `pending` 이고 `none` 일 수 없다(check). 클라이언트 권한은 없다(§2). **`verified` 확정 후 재제출은 FastAPI 가 막는다(409, 2026-09-20 결정)** — `rejected` 는 계속 재제출 가능
- **`profiles.department` 컬럼은 만들지 않는다(2026-09-20 결정)** — 학과는 기존 `major` 컬럼을 재사용하고, FastAPI 응답에서만 `department` 로 별칭한다. 학번은 `student_number` 컬럼을 새로 추가했다(설계 §7.3, 마이그레이션 `20260919181319`)
- **`profiles.bio_draft` · `bio_draft_generated_at`**: AI 자기소개 초안은 최초 1회만 생성한다. `bio_draft_generated_at` 이 이미 있으면 재호출 시 재생성하지 않고 저장된 `bio_draft` 값을 그대로 반환한다(설계 §13-71)
- **`profiles.ideal_note`**: 빈 문자열이면 "미입력"으로 취급한다. 매칭 임베딩("원해" 문장, 설계 §6.3) 계산에서는 빈 문자열을 "없음"으로 처리한다
- `profile_photos` 장수 2~4장: 상한은 `position` 범위로, 하한은 FastAPI 온보딩 완료 검사로 막는다
- `profile_photos` 는 `unique (profile_id, position) deferrable initially deferred` — 순서를 맞바꿀 때 중간 충돌을 피한다. `storage_path` 는 unique — 두 행이 같은 파일을 가리키면 한 행을 지울 때 남은 행의 사진도 사라진다
- `profile_photos.is_avatar_source` 는 부분 유니크 인덱스 `(profile_id) where is_avatar_source` 로 1장만 허용
- **아바타 원본으로 고른 사진도 신뢰 확인을 통과하면 다른 실사진과 함께 공개한다**(§11-5). 어느 사진이 원본인지는 상대에게 드러내지 않는다
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
        card_decision decision "B가 고른 값"
        timestamptz decided_at
    }

    matches {
        uuid id PK "조각4"
        uuid profile_a FK "profile_a 가 profile_b 보다 작다"
        uuid profile_b FK
        timestamptz created_at "게이트 시계 시작 · 기한은 +48시간"
        timestamptz trust_passed_at "조각5 · 양쪽 수락 순간 · 둘 다 아는 사실"
        timestamptz chat_closed_at "조각5 · 기한 도달 시에만 기록"
    }

    match_participants {
        uuid match_id PK, FK "조각4"
        uuid profile_id PK, FK "조각4 · 본인 행만 조회"
        trust_response trust_response "조각5 · null이면 미응답 · 상대에게 비공개"
        timestamptz responded_at "조각5"
        timestamptz left_at "조각5 · 채팅방 나가기 · 상대에게 비공개"
        timestamptz last_read_at "조각5 제안 · 방 진입·이탈 때 갱신 · 상대에게 비공개"
    }

    messages {
        uuid id PK "조각5"
        uuid match_id FK
        uuid sender_id FK
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
        boolean quiet_hours "22시~8시"
    }
```

- `matches` 는 `unique (profile_a, profile_b)` + `check (profile_a < profile_b)`
- **당사자별 값은 `match_participants` 에 둔다.** `matches` 행은 두 사람이 다 읽으므로, 게이트 응답·나가기를 거기 두면 상대의 거절·나가기가 보인다(설계 §2.5 "상대에게 알리지 않음")
- 게이트 판정(설계 §2.5): 기한(`created_at` + 48시간) 전에 양쪽이 accept → FastAPI가 `trust_passed_at` 기록 + 카카오톡 아이디 공유 + 실사진 공개. 기한까지 `trust_passed_at` 이 없으면 그때 `chat_closed_at` 을 기록하고 채팅을 닫는다
- **`chat_closed_at` 은 기한이 됐을 때만 기록한다.** 거절 즉시 찍으면 상대가 거절을 추론한다
- 채팅방의 "신뢰 확인 완료" 카드(`trust-reveal-bubble`)는 메시지 행이 아니라 `matches.trust_passed_at` 으로 그린다
- **읽음은 메시지가 아니라 `match_participants.last_read_at` 에 둔다.** `messages.read_at` 은 두 사람이 다 읽으므로, 상대가 조용히 나가면 내 메시지가 계속 안 읽힘으로 남아 나가기가 드러난다. 안 읽은 수는 상대가 보낸 메시지 중 `created_at` > 내 `last_read_at` 이고, 갱신은 메시지마다가 아니라 방에 들어올 때와 나갈 때 한 번씩이다(나갈 때도 갱신해야 방 안에서 받은 메시지가 안 읽음으로 남지 않는다). 상대에게 보이는 읽음 표시는 없다
- 수락이 겹치는 경로 두 가지: A의 카드에서 A accept → B가 받은 수락함에서 응답(`acceptance_responses`), 또는 서로의 카드에서 둘 다 accept. 어느 쪽이든 양쪽 accept 가 되면 FastAPI가 `matches` 와 `match_participants` 2행을 만든다
- **하드 필터 "이미 카드로 받은 사람"의 정의(§11-4, 설계 §6.7)**: 내가 결정한 카드의 상대(`card_decisions`) + 받은 수락함에서 응답한 상대(`acceptance_responses`) + 매칭 이력이 있는 상대(`matches`, 게이트 실패 포함) + 아직 만료되지 않은 카드의 상대. **무응답으로 만료된 무상 카드의 상대는 다시 나올 수 있다.** 그래서 `daily_cards (owner_id, target_id)` 는 unique가 아니라 일반 인덱스다
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
        uuid id PK "조각6"
        uuid reporter_id FK "계정 삭제(탈퇴 30일 뒤) 시 null"
        report_target target_type "profile message friend_review poll"
        uuid target_id "대상 행 id · FK 없음"
        jsonb target_snapshot "신고 시점 내용 사본"
        text reason "사유 목록 검토10"
        report_status status "open actioned dismissed"
        timestamptz created_at
        timestamptz resolved_at "제안 · 조치·기각 시각 · open 이면 null · 1년 뒤 행 삭제(§11-23)"
    }

    contact_blocks {
        uuid owner_id PK, FK "조각6"
        bytea contact_hmac PK "E.164 정규화 후 HMAC · 원본 저장 안 함 · 클라이언트에 주지 않음"
        uuid id UK "제안 · 기기에 저장한 이름과 짝짓는 키"
        timestamptz created_at
    }

    signup_blocks {
        bytea email_hmac PK "조각6 제안 · 탈퇴한 학교 이메일 HMAC"
        timestamptz blocked_until "탈퇴 요청 시각 + 2개월 · 정지 중 탈퇴는 infinity(§11-22)"
    }
```

- 지인 차단 대조: `contact_blocks.contact_hmac` = `profile_private.phone_hmac` (같은 서버 키, 설계 §7.6b). 나중에 가입한 지인도 가입 때 계산한 `phone_hmac` 로 소급 대조한다
- `phone_hmac` 을 미리 계산해 두는 이유: HMAC 키는 FastAPI 환경변수에만 있어서 DB 안 배치 작업(pg_cron)은 번호를 HMAC 으로 바꿀 수 없다
- **16b 목록의 이름·끝 4자리는 서버에 두지 않는다**(§11-9). 8d에서 고를 때 앱이 기기 안에만 저장하고, FastAPI가 등록 응답으로 돌려준 `contact_blocks.id` 를 키로 짝지어 보여준다. `contact_hmac` 을 키로 쓰지 않는 이유: HMAC 키를 교체하면(검토9) 값이 바뀌어 이름이 전부 끊기고, 클라이언트에 HMAC 값을 줄 필요도 없어진다. 앱을 재설치하거나 기기를 바꾸면 이름 없이 "이전에 차단한 연락처"로 보이지만 차단과 해제는 그대로 된다
- **매칭 중 차단은 `matches` 에 기록하지 않는다.** `chat_closed_at` 같은 공유 값으로 처리하면 상대가 차단을 추론한다. 차단한 사람의 `match_participants.left_at` 과 `blocks` 행으로만 처리한다(설계 §7.2 "차단당한 쪽은 알 수 없어야")
- `reports.target_snapshot` — 게이트 실패 채팅 삭제(설계 §2.5)나 탈퇴 30일 뒤 삭제(§11-15)로 신고된 원본이 사라져도 24시간 조치 근거(애플 심사 지침 1.2)가 남아야 한다. `reporter_id` 는 `on delete set null`. 처리가 끝나고(`resolved_at`) 1년 뒤 행째 지운다(§11-23). check 후보 `(status = 'open') = (resolved_at is null)`
- `signup_blocks` 는 탈퇴로 `profiles` 가 지워진 뒤에도 남아야 하므로 관계가 없다. 원본 이메일을 남기지 않으려고 HMAC 으로 제안. 가입 때 FastAPI HTTP Auth Hook 이 메일 도메인 화이트리스트와 함께 이 표를 검사한다(§11-12). 정지 중 탈퇴는 `blocked_until` 을 `infinity` 로 써서 기간 없이 막는다(§11-22). 기한(`blocked_until`)이 지난 행은 FastAPI 배치(신고 1년 삭제와 같은 배치)가 지운다. 남기면 재탈퇴 때 `email_hmac` PK 가 충돌한다

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
        uuid id PK "조각7"
        uuid profile_id FK "계정 삭제(탈퇴 30일 뒤) 시 null · 5년 보관"
        store_platform store "app_store play_store"
        text product_id "50 100 200 400 번들"
        text store_transaction_id UK "영수증 중복 방지"
        integer heart_amount
        integer price_krw
        purchase_status status "verified refunded"
        timestamptz purchased_at
    }

    heart_task_submissions {
        uuid id PK "조각7 제안 · 18b"
        uuid profile_id FK
        heart_task task "everytime_post kakao_share"
        text storage_path "heart-task-proofs 비공개 버킷"
        submission_status status "submitted approved rejected"
        timestamptz created_at
        timestamptz reviewed_at
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
        uuid referee_id PK, FK "조각7 · 신규 가입자"
        uuid referrer_id FK "코드 주인"
        timestamptz created_at
        timestamptz rewarded_at "피추천인 학생증 통과 후 양쪽 50하트"
    }

    friend_reviews {
        uuid id PK "조각 검토3"
        uuid reviewer_id FK "추천으로 연결된 지인만"
        uuid reviewee_id FK "받은 사람이 직접 삭제 불가 · 작성자 탈퇴 시 즉시 숨김 · 30일 뒤 삭제"
        text[] tags "12종 · 최대 3 · 최소 검토7"
        text comment "선택 · 100자"
        content_status status "visible blinded"
        timestamptz created_at
    }
```

- `entitlements.heart_balance` 는 `heart_transactions` 합계의 캐시다. 지급·차감은 FastAPI가 한 트랜잭션에서 둘 다 쓴다(설계 §7.6)
- `purchases` 는 탈퇴해도 지우지 않는다(§11-14). `profile_id` 는 `on delete set null` 이라 null 허용이고, 금액·상품·영수증 번호만 남는다. `store_transaction_id` unique 도 남아 재가입한 계정이 같은 영수증을 다시 쓰지 못한다. `purchased_at` 5년 뒤 FastAPI 가 지운다. 하트 원장(`heart_transactions`)은 탈퇴와 함께 지워진다. 법령에 따라 보존하는 정보는 다른 개인정보와 분리해 저장해야 하는데(개인정보보호법 제21조③), 별도 테이블에 `profile_id` 없이 남기므로 이를 충족한다고 본다
- `friend_reviews` 는 `unique (reviewer_id, reviewee_id)`. 추천 관계 확인은 FastAPI가 `referrals` 로 한다
- 커뮤니티 투표 하트는 자동 적립(`heart_transactions.reason = poll_vote`), 주간 상한 30하트는 원장 집계로 검사
- 추천 어뷰징 "동일 기기 차단"(설계 §2.7)을 판단할 기기 식별값의 저장처가 아직 없다 — 검토6

## 7. 커뮤니티 · 운영

```mermaid
%%{init: {'er': {'diagramPadding': 40, 'entityPadding': 25}}}%%
erDiagram
    profiles ||--o{ polls : "author_id"
    polls ||--o{ poll_votes : "투표"
    profiles ||--o{ poll_votes : "voter_id"

    polls {
        uuid id PK "조각 검토3"
        uuid author_id FK "응답에 담지 않음 · 익명"
        text question "80자"
        text option_a_label "기본 찬성"
        text option_b_label "기본 반대"
        content_status status "visible blinded"
        timestamptz created_at
    }

    poll_votes {
        uuid poll_id PK, FK
        uuid voter_id PK, FK "재투표 불가"
        poll_choice choice "a b"
        timestamptz created_at
    }

    faq {
        uuid id PK "조각 검토3 · 원격 수정용"
        faq_category category "6종"
        text question
        text answer
        smallint sort_order
        timestamptz updated_at
    }
```

## 8. 열거형

enum 값은 만든 뒤 지울 수 없다(추가·이름 변경만 된다). 그래서 **후보**라고 적힌 타입은 그 조각에서 값을 확정한 뒤 만든다.

| 타입 | 값 | 근거 |
| --- | --- | --- |
| `gender` | `male` `female` | §3 |
| `profile_status` | `pending` `active` `suspended` `withdrawn`(조각6 제안 · §11-15) | §3 |
| `verification_status` | `none` `pending` `verified` `rejected` — **확정(2026-09-14 사용자 결정) · 클라우드 적용됨(2026-09-20)** | 설계 §7.3·미결3, DESIGN 화면 3b |
| `major_field` | `humanities` `social` `business` `engineering` `natural_science` `medical` `arts_sports` `education` | 조각 0 마이그레이션 `20260913054544` |
| `religion` | `none` `protestant` `catholic` `buddhist` | DESIGN §8.5 무교·기독교·천주교·불교 |
| `animal_type` | 후보 `dog` `cat` `fox` `bear` `rabbit` `deer` `wolf` `hamster` — **조각 2에서 확정** | DESIGN §5.4 `animal-face-*` 일러스트 8종 |
| `impression_type` | `arab` `tofu` `kind` `chic` `innocent` | DESIGN §8.5 아랍상·두부상·선한상·시크상·청순상 |
| `acquisition_channel` | `everytime` `instagram` `friend` `community` `other` | DESIGN §9 화면 20d |
| `avatar_status` | `pending` `ready` `failed` | 제안 |
| `card_source` | `daily` `purchased` | §4 |
| `card_decision` | `accept` `reject` | §4 |
| `trust_response` | `accept` `reject` | 설계 §2.5 |
| `device_platform` | `android` `ios` | 제안 |
| `report_target` | `profile` `message` `friend_review` `poll` | 제안 |
| `report_status` | `open` `actioned` `dismissed` | 제안 |
| `store_platform` | `app_store` `play_store` | 제안 |
| `purchase_status` | `verified` `refunded` | 제안 |
| `heart_reason` | `purchase` `referral` `promo` `free_task` `poll_vote` `extra_card` `avatar_regen` `refund` `admin_adjust` | 제안 — 환불 회수와 운영 보정 포함 |
| `heart_task` | `everytime_post` `kakao_share` | DESIGN §8.10 |
| `submission_status` | `submitted` `approved` `rejected` | DESIGN §8.10 |
| `content_status` | `visible` `blinded` | 설계 §2.8 |
| `poll_choice` | `a` `b` | DESIGN §8.11 |
| `faq_category` | `card_matching` `heart_payment` `photo_profile` `friend_review` `safety` `account` | DESIGN §8.13 |

## 9. Storage 버킷

모든 버킷은 비공개이고 클라이언트용 Storage 정책을 두지 않는다. 업로드는 FastAPI가 발급한 서명 업로드 URL로, 조회는 FastAPI가 발급한 서명 URL로만 한다(설계 §7.4, §2 쓰기 원칙).

| 버킷 | 공개 | 조각 | 내용 |
| --- | --- | --- | --- |
| `profile-photos` | 비공개 | 0 | 실사진 2~4장. 서명 URL은 본인과, 신뢰 확인을 통과한 상대에게만 준다. 사진 주인이 탈퇴(`withdrawn`)하면 남은 상대에게도 주지 않는다(§3). 이미 발급한 서명 URL 은 만료까지 열리므로 실사진 서명 URL 만료는 짧게 둔다(조각 5). **제한: 파일 10MB · `image/jpeg` `image/png`**(2026-09-14 사용자 결정, 조각 0 파일은 두고 조각 1 마이그레이션에서 추가 · 클라우드 적용됨(2026-09-20)) — 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다. 파일 내용(매직 바이트) 검사는 FastAPI 가 한다 |
| `avatars` | 비공개 | 2 | 만화 아바타. 항상 노출되는 이미지라 공개 버킷으로 바꾸자는 안은 설계 §7.4 예외라서 조각 2에서 결정 — 검토2 |
| `heart-task-proofs` | 비공개 | 7 | 무료 하트 인증샷 |
| `student-id-temp` | 비공개 | 1 | 학생증 사진. 자동 대조 실패 시 사람이 재검토해야 해서(설계 §7.3) **검증이 끝날 때까지만 임시 보관하고, 끝나면 즉시 삭제**한다. **구현(2026-09-20 정정, PR #43) — Postgres 트리거가 아니라 FastAPI 가 Storage API로 직접 지운다**: `profiles.student_verification` 을 `verified`/`rejected` 로 확정한 직후 FastAPI 가 그 사람의 최근 제출 파일을 Storage API `DELETE`로 지운다. `delete from storage.objects` 트리거(`student_verification_finalized`, 마이그레이션 `20260919181357`)는 `storage.objects` 메타 행만 지우고 실제 파일 객체는 고아로 남기기 때문에 폐기했다(클라우드에 적용된 적 없음, 파일도 삭제) — Supabase Storage 문서상 파일 삭제는 Storage API를 거쳐야 한다. 삭제 실패는 인증 결과(성공)에 영향을 주지 않고 로그와 디스코드 알림으로만 남으며, 고아 파일은 대시보드에서 손으로 지운다(SUPABASE.md §7). 보관 기간을 따로 두지 않는다. 검증이 끝나기 전에 탈퇴한 사람의 파일은 탈퇴 즉시(30일 보관 예외, §11-19), 가입 도중 이탈한 사람의 파일도 FastAPI 가 지운다(이탈 판단 시점은 조각 1에서 정한다). **제한: 파일 10MB · `image/jpeg` `image/png`**(2026-09-14 사용자 결정) — 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다. 버킷 제한은 업로드 쪽이 신고한 content type 과 크기로만 막으므로(413 · 400), 파일 내용(매직 바이트)은 FastAPI 가 업로드 뒤 대조 전에 검사한다(조각 1 서버) |

## 10. 조각 0 마이그레이션 범위 → `docs/ERD_DECISIONS.md` §10

2026-09-14 클라우드 적용 완료. 실제 SQL 은 `supabase/migrations/` 의 조각 0 파일 4개(`20260913054542` ~ `20260913054549`)이고, 적용 범위 기록은 `docs/ERD_DECISIONS.md` §10 에 옮겼다.

## 11. 결정 기록 → `docs/ERD_DECISIONS.md` §11

2026-09-13 ~ 09-14 사용자 결정 1~25 는 `docs/ERD_DECISIONS.md` §11 에 번호 그대로 옮겼다(2026-09-14 문서 정리). 새 결정도 그 표에 이어서 적는다.

## 12. 남은 검토

해결된 번호(1 · 4 · 15~19 · 22~33)는 `docs/ERD_DECISIONS.md` §12 에 번호 그대로 옮겼다. 새 검토는 37번부터 이 표에 잇는다.

| # | 내용 | 조각 | 근거 |
| --- | --- | --- | --- |
| 2 | `avatars` 버킷을 공개로 바꿀지 (설계 §7.4 예외) | 2 | 설계 §7.4 |
| 3 | 조각 번호가 없는 기능: 지인 리뷰·커뮤니티·FAQ·프로모션 코드. (추천인은 설계 §2.7에 조각 7, 커뮤니티 도입 자체는 설계 미결14에서 확정) | — | 설계 §3.1 |
| 5 | "한 번호 한 계정" 규칙 여부 → `phone_hmac` 유니크 여부. 문서에는 추천 보상 한정 동일 번호 차단(§2.7)만 있다. 유니크로 정하면 탈퇴 뒤 30일 동안 `profile_private` 가 남아(§11-19) 같은 번호로 다른 메일 가입도 막힌다(메일 기준 `signup_blocks` 와 별개) | 6 | 설계 §2.7 |
| 6 | 추천 어뷰징 "동일 기기 차단"의 기기 식별값 저장처 | 7 | 설계 §2.7 |
| 7 | 지인 리뷰 태그 최소 개수 (DESIGN §13-25는 최대 3개만 정함) | — | DESIGN §13-25 |
| 8 | `animal_type` 최종 값 | 2 | DESIGN §5.4·§8.5 |
| 9 | HMAC 키 교체 절차 — `phone_hmac` · `contact_hmac` · `signup_blocks.email_hmac` 세 곳에 같이 걸린다. `signup_blocks` 는 원본 메일이 없어 새 키로 재계산할 수 없다. `contact_hmac` 도 원본을 서버에 두지 않아 같다(§5). 새 키로 다시 계산할 수 있는 것은 `profile_private` 의 번호 암호문이 있는 `phone_hmac` 뿐이다. `contact_blocks` 행이 남아 있거나 `blocked_until` 이 `infinity` 인 행이 있으면 옛 키를 계속 보관해야 한다. 안 그러면 §5 대조(`contact_hmac` = `phone_hmac`)가 오류 없이 끊겨 지인 차단이 풀린다 | 6 | 설계 미결36 |
| 10 | 신고 사유 목록 | 6 | 설계 §2.8 |
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
