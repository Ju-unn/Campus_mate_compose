# CampusMate ERD 결정 기록

> `docs/ERD.md` 에서 옮긴 결정 기록과 끝난 항목이다(2026-09-14 문서 정리). 절 번호와 행 번호는 ERD.md 와 같다 — 마이그레이션 주석 · 설계 문서 · DESIGN.md 가 "ERD §11-N" 처럼 번호로 인용하기 때문이다.
> 이 문서 안에서 §1~§9 와 열린 §12 는 `docs/ERD.md` 의 절이고, §10 · §11 · 해결된 §12 · §13 은 이 문서에 있다.

## 10. 조각 0 마이그레이션 범위 (2026-09-14 클라우드 적용 완료 · 실제 SQL 은 `supabase/migrations/` 4개 파일)

- 첫 마이그레이션 맨 앞에서 `create extension if not exists vector with schema extensions;` (frontend/CLAUDE.md §10.1). 조각 3에서 벡터 컬럼을 만들 때는 타입을 `extensions.vector` 로 쓰거나 `search_path` 에 `extensions` 가 있는지 확인한다
- `universities` — 코호트 컬럼 제외. `university_email_domains` 함께 생성(학교당 도메인 여러 개)
- `profiles` — ERD.md §3 표의 `조각0` 컬럼. 계획서 Task 7 SQL 대비 **`hide_same_major` 삭제, `admission_year` 추가, `email_domain` 은 `university_email_domains` 로 이동, `not null` 은 `university_id` · `status` 만 두고 온보딩 컬럼은 `active` 전환 check 로**(§3 주석)
- `profile_photos` — `position` 0~3, `unique (profile_id, position) deferrable initially deferred`. `is_avatar_source` 는 조각 2
- RLS — 전 테이블 enable. 클라이언트 정책은 §2 표의 SELECT 뿐. **계획서의 INSERT·UPDATE 정책은 넣지 않는다.** `auth.uid()` 는 항상 `(select auth.uid())`
- grant — RLS 와 같은 마이그레이션에서 §2 원칙대로. 조각 0 기준 `anon` 은 `universities` · `university_email_domains` select, `authenticated` 는 여기에 `profiles` · `profile_photos` select 추가, `service_role` 은 전 테이블 select · insert · update · delete
- `profile-photos` 비공개 버킷 — 클라이언트 Storage 정책 없음. **서명 업로드 URL은 정책 없이 동작한다**(Supabase 문서: "Signed upload URLs can be used to upload files to the bucket without further authentication", 발급하는 service key 는 RLS 를 우회. Dart `createSignedUploadUrl` 에 upsert 옵션 있음)
- 계정 삭제(탈퇴 30일 뒤) cascade 가 Storage 파일을 지우지 않는다는 주석
- 시드 — 서울권 학교 + 메일 도메인

## 11. 결정 기록 (2026-09-13 ~ 09-14 사용자 결정)

문서 최신화 담당이 오른쪽 열의 문서를 고친다.

| # | 결정 | ERD 반영 | 고칠 문서 |
| --- | --- | --- | --- |
| 1 | **가입 나이는 연 나이 기준** — 만 19세가 되는 해 1월 1일부터(청소년보호법 방식) | `birth_year` 유지 | frontend/CLAUDE.md §2 "만 19세 이상" 문구, 설계 §13 미결2 |
| 2 | **실명은 저장하되 별도 비공개 테이블에** — 3b 입력, 학생증 이름 대조, 본인만 16e 조회, 서버 응답에 담지 않음 | `profile_private.real_name` | 설계 §7 서두·§7.3 "실명은 추출·저장하지 않는다"(같은 절 끝 "학교명(+3b의 실명)"과 자기모순), DESIGN §8.7·16e·CLAUDE.md §7 이 인용하는 "설계 §7 예외 2"(설계에 없는 참조), 설계 §7.3 "검증 결과(boolean)만 `profiles.student_id_verified`" → `student_verification` 상태값(조각 1 확정) · `student-id-temp` 임시 보관 |
| 3 | **성향 설문은 5점 슬라이더** (−1 −0.5 0 0.5 1) | `survey_answers.value` · `shyness_score` numeric | 설계 §6.1·§6.2·§13 미결6 "문장형 버튼 3개". 최대가능거리는 척도와 무관하다(축당 최대 차 2, 가중치 전 2√8). 설계 §6.3 `shyness_score` "정수 −1~1" → 5점(낯가림 공식 \|A−B\|÷2 는 0.5 단위에서도 0~1 이라 그대로) |
| 4 | **무응답으로 만료된 무상 카드의 상대만 재노출** — 수락·거절한 상대, 매칭 이력 상대는 영구 제외 | §4 하드 필터 정의, `daily_cards` 일반 인덱스 | 설계 §6.7 하드 필터 정의, 설계 §2.4 표·DESIGN §8.9 가 인용하는 "§13 미결31"(실제 미결31은 지인 리뷰 목록이라 없는 참조) |
| 5 | **아바타 원본 사진도 신뢰 확인 후 함께 공개** | §3 주석 | DESIGN §5.2 "아바타 원본 자체는 어디에도 노출되지 않는다" → 어느 사진이 원본인지 드러내지 않는다 |
| 6 | **게이트 48시간 기한은 매칭 시점부터** | `trust_deadline_at` 컬럼 삭제(계산값) | 설계 §2.5 |
| 7 | **지급 주기·성비 판단은 지역그룹 단위** — 지역그룹이 곧 매칭 풀. 새 학교는 모집 14일 뒤 그 지역의 현재 주기에 합류 | `region_group_settings` 유지, 학교별 주기 컬럼 없음 | 설계 §2.9 "성비 미달이면 주 1회로 시작" → 지역그룹 첫 오픈 기준 |
| 8 | **클라이언트는 본인 데이터 읽기만, 쓰기는 전부 FastAPI** | §2 접근 표 · grant, 클라이언트 쓰기 정책 없음 | 설계 §7.1 "RPC 함수로만" → FastAPI 경유. 설계 §7.2 표(`daily_cards`·`card_decisions` 본인 조회, `reports` 신고자 쓰기) → ERD §2 표. 계획서 머리말 "FastAPI 서버 자체는 … (매칭·결제)에서 시작" → 조각 1(이메일 인증 직후 `profiles` 생성 · 3b OCR)부터 필요, "처음 필요해지는 조각에서 시작" 원칙은 그대로. 계획서 Task 7 정책 SQL. frontend/CLAUDE.md §10.1 RLS 체크리스트: "소유자 조건을 반드시 붙인다"에 공개 참조 테이블 4개(`universities` · `university_email_domains` · `region_group_settings` · `faq`) 예외와 `anon` 은 2개만임을 명시, "Storage upsert는 정책 3개" → 클라이언트 Storage 정책 없음 · 서명 업로드 URL, grant 를 RLS 와 같은 마이그레이션에 |
| 9 | **지인 연락처는 HMAC 으로만 저장 유지**(2026-09-13 §7.6b 결정 재확인). 16b에 보일 이름·끝 4자리는 기기 안에만 저장 | `contact_blocks.id` 추가(기기와 짝짓는 키), §5 주석 | DESIGN §8.12 16b "이름 + 마스킹 번호"의 출처(기기 저장)와 기기 변경 시 표시. 8a 문구는 그대로 |
| 10 | **메일 도메인 1개는 대학 1개에만 속한다** — 서울 밖 캠퍼스도 따로 나누지 않는다(첫 출시는 서울권뿐) | `university_email_domains.domain` PK 유지, §3 주석, §12-15 해결 | 설계 §7.3 학생인증 서술에 캠퍼스 미구분 한 줄 |
| 11 | **탈퇴하면 그 사람이 쓴 지인 리뷰·투표 글도 지운다**(설계 §2.6 "전부 영구 삭제"). 받은 사람의 리뷰도 작성자가 탈퇴하면 사라지고, 투표 글이 지워지면 달린 표도 지워진다. `profiles` 를 가리키는 FK 와 탈퇴 경로의 하위 FK 5개(§2)는 `on delete cascade`, 예외는 `reports.reporter_id`(신고 근거 보존) · `profile_avatars.source_photo_id` · `purchases.profile_id`(§11-14) set null | §2 FK 규칙, §12-16 해결. 결제 내역 예외는 §11-14, 이 결정이 남긴 부작용은 §11-15~19 | 설계 §2.6 탈퇴 절차에 FK 규칙 한 줄. 설계 §2.6 확인 화면과 DESIGN `account-delete-sheet` 의 삭제 항목 안내("프로필·매칭 기록·채팅")에 쓴·받은 지인 리뷰 · 투표 글과 표 · 남은 하트 추가 |
| 12 | **재가입 제한(`signup_blocks`)은 FastAPI 가 HTTP Auth Hook 에서 메일 도메인 화이트리스트와 함께 검사한다** — HMAC 키가 FastAPI 에만 있다 | §5 주석, §12-17 해결. 훅이 DB 함수가 아니므로 §12-19 해당 없음 | 설계 §2.6 재가입 제한 · §7.3 Auth Hook 서술 |
| 13 | **`profile_private` 접근 감사 로그는 테이블 없이 FastAPI 구조화 로그로 남긴다** | §3 주석, §12-18 해결 | 설계 §7.6b "접근 통제·감사 로그" |
| 14 | **결제 내역(`purchases`)은 탈퇴해도 지우지 않는다** — 구매자 칸만 비우고 5년 보관 뒤 파기한다. 하트 원장(`heart_transactions`)은 탈퇴와 함께 지운다. 5년 근거(전자상거래법 시행령 대금결제 기록)가 스토어 인앱결제에 적용되는지는 조각 7 전에 확인 | `purchases.profile_id` set null · §2 FK 규칙 예외 · §6 주석, §12-23 해결 | 설계 §2.6 FK 규칙 문단 "결제 기록(`purchases`·`heart_transactions`)을 이 예외에 넣을지는 §12-23 미결" → 예외에 `purchases.profile_id` set null 추가, `heart_transactions` 는 함께 삭제. 설계 §2.6 확인 화면과 DESIGN `account-delete-sheet` 에 "결제 내역은 법에 따라 보관". 개인정보처리방침(설계 §7.7 · 미결21, 노션)의 처리·보유 기간에 5년과 근거 법령, 가입 동의 문구의 보유 기간 |
| 15 | **탈퇴하면 30일 뒤 계정 전체를 지운다** — 탈퇴 즉시 숨김·로그인 차단, 탈퇴자의 카카오톡 아이디·실사진은 더 주지 않는다. 남은 상대는 게이트를 통과한 매칭이면 30일 동안 채팅을 읽고 신고할 수 있고(메시지는 못 보냄), 통과 전 매칭은 기존대로 48시간 기한에 닫힌다. 30일 뒤 FastAPI 가 Storage 파일과 `auth.users` 를 지운다. 보관 목적은 신고·분쟁 대응 | `profiles.status` 에 `withdrawn`, `withdrawn_at` 추가(조각6 제안) · §2 · §3 주석, §12-24 해결 | 설계 §2.6 "→ 즉시 처리. `phone_number` 를 포함한 개인정보는 즉시 파기한다(§13 미결27과 연결)" → 30일 뒤 삭제·보관 목적·학생증 사진 예외(§11-19). "미결27"은 `hide_same_major` 라 없는 참조. 설계 §2.6 확인 화면 "전부 영구 삭제"와 DESIGN `account-delete-sheet` 에 "30일 뒤 완전 삭제". 설계 §2.5 게이트에 "상대가 탈퇴하면 통과시키지 않는다". DESIGN 채팅에 "상대가 탈퇴한 채팅" 상태. 개인정보처리방침(설계 §7.7 · 미결21, 노션)의 보유 기간과 가입 동의 문구에 30일 보관과 목적 |
| 16 | **상대 탈퇴로 남은 사람이 잃는 하트는 돌려주지 않는다**(알려진 한계) — 탈퇴한 사람을 대상으로 산 추가 카드는 더 쓸 수 없고 50하트는 환불하지 않는다. 피추천인 보상은 추천인이 탈퇴해도 30일 안에 학생증을 통과하면 지급되고, 탈퇴한 추천인 몫은 주지 않는다 | §3 탈퇴 주석, §12-25 해결 | 설계 §2.7 추천인 보상에 "추천인이 탈퇴하면 추천인 몫은 없음 · 탈퇴자 코드는 받지 않음(없는 코드로 처리) · 월간 랭킹 보상에서 제외" |
| 17 | **재가입하면 기록이 풀리는 것은 2개월 재가입 제한만으로 둔다**(알려진 한계) — 새 계정에는 차단(`blocks`)·영구 제외(§11-4)·추천 1회 제한·프로모션 코드 1코드 1계정(`promo_redemptions`)이 적용되지 않는다. 남이 건 연락처 차단은 새 계정의 `phone_hmac` 으로 다시 대조돼 유지되지만, 본인이 건 `contact_blocks` 는 30일 뒤 `owner_id` cascade 로 사라진다. 2개월은 탈퇴 요청 시각부터 센다 | `signup_blocks.blocked_until` 주석, §12-26 해결 | 설계 §2.5 "매칭 기록은 남긴다(재노출 악용 방지)"에 재가입한 계정에는 적용되지 않는다는 한 줄, 설계 §2.6 재가입 제한 기준 시각 |
| 18 | **운영자는 `profile_private` 를 FastAPI 관리 기능으로만 본다** — Supabase 대시보드·SQL 직접 조회 금지. 접속 기록 보관 기간은 개인정보 안전성 확보조치 기준을 확인해 조각 2 전에 정한다 | §3 주석, §12-27 해결 | 설계 §7.6b 운영자 조회 방법 |
| 19 | **탈퇴 30일 보관에서 학생증 사진만 뺀다** — `student-id-temp` 파일은 탈퇴 즉시 지운다(탈퇴로 검증 목적이 끝났고 신고·분쟁 대응에 쓰지 않는다). `profile_private`(실명·전화번호·`phone_hmac`·카카오톡 아이디)는 신고·수사 요청 때 신원 확인에 쓰도록 30일 보관한다 | §3 탈퇴 주석 · §9 `student-id-temp`, §12-29 해결 | 설계 §2.6 "`phone_number` 를 포함한 개인정보는 즉시 파기한다" → 학생증 사진은 즉시, 나머지는 30일 뒤. 개인정보처리방침(미결21)·가입 동의 문구의 30일 보관 항목에 실명·전화번호·카카오톡 아이디 |
| 20 | **본인 카카오톡 아이디는 FastAPI 가 내려준다**(2026-09-14) — `profile_private` 컬럼 grant 는 `profile_id` · `real_name` 그대로 두고, 16e · 14f · 16e-1 은 본인 `kakao_id` 를 FastAPI 로 읽는다. 카카오톡 아이디가 클라이언트로 나가는 길은 읽기·수정 모두 FastAPI 하나이고, 조회는 §11-13 구조화 로그에 남는다 | §2 접근 표 비고, §2 grant 테스트 기대값에 본인 `select kakao_id` 42501 추가(컬럼 grant 는 그대로), §12-32 해결 | DESIGN §13-104 해결 처리(16e `irepB` · 14f · 16e-1 `bWrnD` 의 조회 출처 FastAPI) |
| 21 | **탈퇴는 되돌릴 수 없다**(2026-09-14) — 30일 보관은 신고·분쟁 대응용이지 본인 복구용이 아니다. 탈퇴 즉시 걸린 로그인 차단은 30일 동안 풀지 않는다 | §3 탈퇴 주석, §12-28 해결 | 설계 §2.6 "되돌리기" 항목 → 되돌릴 수 없음. 설계 §2.6 확인 화면과 DESIGN `account-delete-sheet` 에 되돌릴 수 없다는 안내(이미 있으면 그대로) |
| 22 | **정지(`suspended`) 중에 탈퇴한 계정은 같은 학교 메일로 다시 가입할 수 없다**(2026-09-14) — FastAPI 가 탈퇴 처리에서 `status` 를 `withdrawn` 으로 덮기 전에 `suspended` 인지 보고, 그렇다면 `signup_blocks.blocked_until` 을 탈퇴 요청 시각 + 2개월 대신 `infinity` 로 쓴다(스키마 변경 없음). 다른 메일로 가입하는 우회는 막지 못한다(알려진 한계, "한 번호 한 계정"은 §12-5) | §5 `signup_blocks.blocked_until` 주석, §12-31 해결 | 설계 §2.6 재가입 제한에 "정지 중 탈퇴는 기간 없이 제한" 한 줄. 개인정보처리방침(설계 §7.7 · 미결21)에 이 경우 `email_hmac` 을 기간 없이 보관한다는 항목 |
| 23 | **신고는 처리가 끝나고 1년 뒤 사본(`target_snapshot`)과 함께 지운다**(2026-09-14) — 조치·기각하면 FastAPI 가 `reports.resolved_at` 을 쓰고, 1년 지난 `reports` 행을 FastAPI 가 지운다(사본만이 아니라 행째 삭제, 2026-09-14 사용자 확인). 열린(`open`) 신고는 지우지 않는다. 최종 기간은 출시 전 법무 검토(설계 미결21)에서 확인 | §5 `reports.resolved_at` 추가 · 주석, §12-30 해결 | 개인정보처리방침(설계 §7.7 · 미결21)의 보유 기간에 "신고 기록: 처리 후 1년" |
| 24 | **학생증 인증 상태값은 `none` `pending` `verified` `rejected` 4개로 확정하고, 재시도 횟수는 시도 기록 테이블의 행 수로 센다**(2026-09-14) — 제출 한 번에 `student_verification_attempts` 한 행, 반려 사유 · 재검토 시각도 여기 남는다. 클라이언트는 이 테이블을 읽지 않고 본인 반려 사유는 FastAPI 응답으로 받는다. 재시도 상한 값과 고객 지원 경로는 정하지 않았다(설계 미결3, 조각 1 서버) | §8 `verification_status` 확정, §3 `student_verification_attempts` · §2 접근 표, §12-4 해결 | 설계 §7.3 학생인증 상태값 서술에 시도 기록 테이블, 설계 미결3 에서 저장 방식은 해결 · 상한 값과 고객 지원 경로는 남김 |
| 25 | **`profile-photos` · `student-id-temp` 버킷은 파일 10MB · `image/jpeg` `image/png` 로 제한한다**(2026-09-14) — 클라이언트가 업로드 전에 압축하고 JPEG 로 다시 인코딩한다. 버킷 제한은 업로드 쪽이 신고한 content type 과 크기만 보므로(413 · 400) 파일 내용(매직 바이트)은 FastAPI 가 검사한다 | §9 두 버킷 제한, §2 pgTAP 기대값 | 설계 §7.4 Storage 서술에 제한값과 매직 바이트 검사 주체, DESIGN 사진 업로드 안내(앱이 압축 · JPEG 재인코딩) |
| 26 | **`profiles` pending 행은 FastAPI가 아니라 `auth.users` INSERT 후 Postgres 트리거(`handle_new_user_profile`)가 만든다**(2026-09-18, FK 순서 문제로 정정) — Before User Created 훅은 `auth.users` 행이 커밋되기 전에 불려서 그 안에서 `profiles.id → auth.users.id` FK를 참조하는 insert를 하면 위반이 난다. 훅은 승인/거부만 결정하고, `auth.users` INSERT 직후에 도는 `AFTER INSERT` 트리거가 pending 행을 만든다 | §3 `profiles` 행 생성 주체 서술 정정 | 설계 §7.3 "FastAPI가 이메일 인증 직후 만든다" → 트리거가 만든다, 설계 §13 새 항목(40) |

## 12. 남은 검토 — 해결된 행

열린 행은 `docs/ERD.md` §12 에 있다.

| # | 내용 | 조각 | 근거 |
| --- | --- | --- | --- |
| 1 | ~~지인 연락처 저장 방식과 16b 표시~~ → 해결(§11-9) | 6 | 설계 §7.6b, DESIGN §8.12 |
| 4 | ~~학생증 인증 상태값과 재시도 횟수 저장 방식~~ → 해결(§11-24): 상태값 4개 확정(§8), 재시도 횟수는 시도 기록 테이블 `student_verification_attempts` 행 수(§3). 재시도 상한 값 · 고객 지원 경로는 설계 미결3 에 남음(조각 1 서버) | 1 | 설계 §7.3·미결3 |
| 15 | ~~메일 도메인 1개 = 대학 1개로 둘지(캠퍼스 구분)~~ → 해결(§11-10) | 0 | 설계 §2.9 · ERD §11-7 |
| 16 | ~~탈퇴 cascade 가 상대 데이터에 미치는 범위~~ → 해결(§11-11, §2 탈퇴 삭제 규칙) | 4~7 | 설계 §2.6 |
| 17 | ~~`signup_blocks` 재가입 제한을 검사할 곳~~ → 해결(§11-12) | 1 · 6 | 설계 §2.6 · §7.6b |
| 18 | ~~`profile_private` 접근 감사 로그를 테이블로 둘지~~ → 해결(§11-13) | 2 | 설계 §7.6b |
| 19 | ~~Auth Hook DB 함수용 `supabase_auth_admin` grant~~ → 해당 없음(§11-12, 훅은 FastAPI HTTP 훅) | 1 | frontend/CLAUDE.md §10.1 |
| 22 | ~~`supabase/config.toml` 의 `major_version = 17` 이 클라우드 Postgres 버전과 같은지 적용 전에 읽기로 확인~~ → 해결(클라우드 Postgres 17.6 읽기 확인, 2026-09-14) | 0 | config.toml 주석 |
| 23 | ~~결제 기록을 탈퇴 cascade 의 예외로 남길지~~ → 해결(§11-14) | 7 | §11-11 |
| 24 | ~~상대가 탈퇴하면 남은 사람의 채팅과 신고 근거가 바로 사라짐~~ → 해결(§11-15) | 5 · 6 | 설계 §2.6 · §11-11 |
| 25 | ~~상대가 탈퇴하면 남은 사람이 잃는 하트·보상~~ → 해결(§11-16, 알려진 한계) | 4 · 7 | §11-11 · §8 `heart_reason` |
| 26 | ~~2개월 뒤 재가입하면 profile id 에 걸린 기록이 풀림~~ → 해결(§11-17, 알려진 한계) | 4 · 6 · 7 | 설계 §2.5 · §2.6 |
| 27 | ~~대시보드·SQL 로 `profile_private` 를 보면 감사 로그에 남지 않음~~ → 해결(§11-18) | 2 | 설계 §7.6b |
| 28 | ~~탈퇴 뒤 30일 안에 되돌릴 수 있게 할지~~ → 해결(§11-21, 되돌리기 없음) | 6 | §11-15 |
| 29 | ~~30일 보관에서 뺄 민감 항목~~ → 해결(§11-19) | 6 | §11-15 · 설계 §2.6 |
| 30 | ~~`reports.target_snapshot` 보관 기간~~ → 해결(§11-23, 처리 후 1년) | 6 | §5 · 설계 미결21 |
| 31 | ~~정지(`suspended`) 계정이 탈퇴 2개월 뒤 재가입해 정지를 벗어남~~ → 해결(§11-22, 기간 없는 재가입 제한) | 6 | §11-17 · 설계 §2.6 |
| 32 | ~~본인 카카오톡 아이디 조회 경로~~ → 해결(§11-20, FastAPI 가 내려줌) | 2 | §2 · DESIGN §13-104 |
| 33 | ~~원격 마이그레이션 버전이 로컬 파일명과 다름~~ → 결정(기록만, 2026-09-14 사용자 결정) — 원격 `20260914045614` · `045656` · `045723` · `045746`, 로컬 파일 `20260913054542` · `054544` · `054547` · `054549`. MCP `apply_migration` 은 버전 인자가 없어 적용 시각으로 찍혔다. CLI `db push` · `migration list` 로 보면 로컬 4개는 미적용, 원격 4개는 로컬에 없는 이력으로 보인다. `migration repair` 는 하지 않고, 이후 조각도 MCP 플러그인 `apply_migration` 으로 적용해 일관되게 간다 | 1 | 계획서 Task 7 실제 적용 기록 · frontend/CLAUDE.md §10.1 |

## 13. 문서 갱신 대상 (결정과 무관한 오래된 서술) — 2026-09-14 기준 전부 반영

- 설계 §5.1 조망도 `profiles ──< profile_vectors`(1:N) → 1:1
- 설계 §5.2 `profile_vectors` "벡터 4종" → `self_survey` · `self_text` 2종 + `shyness_score`
- 설계 §5.2 `entitlements` "등록비 납부 여부·부스트" → 하트 잔액
- 설계 §5.2 `universities.email_domain` → `university_email_domains` 로 분리
- 설계 §7.3 Auth Hook 설명의 `universities.email_domain` → `university_email_domains`
- 설계 §7.5 · §7.6 "Edge Function" → FastAPI
- 설계 §3.2 커뮤니티 "조각 8 이후 후보" → 미결14에서 도입 확정
- 설계 §13 미결15·16 부스트·거절 되돌리기 → 하트 소비처는 추가 카드·아바타 재생성뿐
- 계획서 Task 7 메모의 "미결32·36" 번호 → 지금은 다른 항목을 가리킨다
