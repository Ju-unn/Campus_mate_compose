# SUPABASE.md — CampusMate Supabase 작업 규칙

**Supabase 작업(스키마·RLS·Storage·Auth)을 하기 전에 이 문서를 먼저 읽는다.**

`frontend/CLAUDE.md` §10.1 에서 떼어낸 문서다(2026-09-15). `frontend/CLAUDE.md` §10.1 에는 금지 규칙 요약만 남겼고, 마이그레이션 주석과 ERD 가 인용하는 "`frontend/CLAUDE.md` §10.1" 의 세부 규칙은 이 문서에 있다.

## 1. 현재 상태

- Supabase **MCP 플러그인(`supabase`)이 설치·인증돼 있다.** 클라우드 프로젝트는 `campus_mate`(조직 CampusMate, Seoul) 하나뿐이다.
- 운영 적용 상태의 기준은 **`docs/ERD.md` 상태줄**이다: 저장소 `supabase/migrations/` 103개 = 운영 103개, 모두 적용(마지막 `20261108090000_faq_graduate_certificate`). 이 숫자는 대장 전달 값이라 확인은 MCP `list_migrations` 로 한다. 원격 버전은 파일 이름이 아니라 적용 시각이므로 대조는 `name` 으로 한다(§4).
- 클라우드 쓰기(적용)는 항상 클라우드 프로젝트에 MCP `apply_migration` 으로만, 사용자 원문 승인을 인용한 뒤에 한다(§4). 적용은 **ERD 그림 → 사용자 검토 → 사용자 승인** 뒤에만 한다.
- 로컬 스택(Docker)에서 `supabase db reset` · `supabase test db`(pgTAP)로 먼저 검증한다. 모든 작업 폴더가 같은 로컬 DB 를 쓰므로 한 번에 한 작업만 돌린다(`frontend/CLAUDE.md` §10 · `.claude/team/COMMON.md` §4).
- 적용 순서가 서버 배포와 얽힌 기능의 순서는 `backend/DEPLOY.md` §4 가 기준이다(보통 DB → 서버 → 관리자 웹 → 앱).
- **마이그레이션 파일이 없는 운영 데이터 변경 두 가지가 남아 있다.**
  - 서울 학교 64곳의 `universities.card_opens_at` 을 2026-11-02 07:00 에서 null(열림)로 바꿨다(`execute_sql`, 사용자 승인). 저장소 `20261020110000` 은 그대로라 새 DB 는 11-02 로 닫힌 채 만들어진다. 스토어 심사 통과 뒤 날짜를 정해 다시 막는다(`backend/DEPLOY.md` §4-17).
  - 구글 심사용 시험 데이터(가상 계정 20 · 카드 1 · 채팅방 3)가 일회성 스크립트로 들어 있다. 심사 통과를 확인한 뒤 사용자에게 먼저 묻고 제거하며, 그 전에는 하네스 전체 cleanup 을 돌리지 않는다(`backend/DEPLOY.md` §4-16).
- 마이그레이션별 적용 날짜 · 원격 버전 · 승인 원문 · 적용 뒤 확인(advisor 등)은 `docs/history/erd-log-2026.md` 에 있다.

## 2. 시작할 때

- 스키마·RLS·Storage·Auth 를 건드리기 전에 `supabase:supabase` 스킬(보안 체크리스트)과 `supabase:supabase-postgres-best-practices` 스킬을 로드한다
- 현재 상태는 추측하지 않고 MCP `list_tables` · `list_extensions` · `list_migrations` 로 확인한다

## 3. 키·식별자 취급

- 프로젝트 URL · project ref · anon/publishable 키 · `service_role` 키 · DB 비밀번호는 **문서·코드·커밋·PR 에 쓰지 않는다.** 필요할 때 MCP `get_project_url` · `get_publishable_keys` 로 조회하고, 앱에는 `--dart-define` 으로 주입한다 (`frontend/CLAUDE.md` §11)
- `service_role` 키는 FastAPI 서버 전용이다. Flutter 쪽 코드·설정에는 절대 두지 않는다

## 4. 스키마 변경 = 마이그레이션 파일

- **`supabase/` 는 저장소 루트에 있다, `frontend/` 안이 아니다**(2026-09-13 사용자 결정). 모든 스키마 변경은 `supabase/migrations/<timestamp>_<name>.sql` 로 저장소에 남긴다 (설계 문서 §5.4). 대시보드·`execute_sql` 로 DDL 을 손으로 실행하지 않는다
- 파일 이름은 `supabase migration new <name>` 으로 만든다(저장소 루트에서 실행). 직접 지어내지 않는다
- 클라우드 적용은 MCP `apply_migration` 에 **그 파일 내용을 그대로** 넘긴다(2026-09-14 사용자 결정, ERD §12-33). `apply_migration` 은 원격 버전을 적용 시각으로 찍어 파일명과 다르므로 `supabase db push`·`migration list` 는 `migration repair` 없이는 쓸 수 없고, repair 도 클라우드 쓰기라 사용자 승인이 필요하다. 클라우드 쓰기는 매번 사용자가 직접 승인한 뒤에만 한다.
- **클라우드 마이그레이션 적용 절차 (2026-09-20 정책으로 고정).** 클라우드 마이그레이션은 MCP `apply_migration` 으로만 적용한다(사용자 승인 후). `supabase db push` · `migration repair` · `db pull` 은 쓰지 않는다 — 원격 `version` 이 적용 시각으로 기록돼 로컬 파일명과 다르기 때문이다(`name` 은 1:1 일치). 적용 전에는 `list_migrations` 의 `name` 과 로컬 파일 `name` 을 대조해 아직 적용되지 않은 파일만 적용한다. 로컬 검증은 `supabase db reset` + `supabase test db` 로 한다
- 적용 직후 MCP `get_advisors`(security · performance)를 돌려 경고를 0 으로 만든다
- 프로덕션 DB 에서 `execute_sql` 은 **읽기 전용 조회**에만 쓴다

## 5. RLS 체크리스트 (정책 SQL 을 쓸 때마다)

테이블별 실제 접근 표는 `docs/ERD.md` §2 가 기준이다.

- `public` 스키마의 모든 테이블은 RLS 를 켠다
- 정책은 `to authenticated` + `using ((select auth.uid()) = user_id)` 꼴. `auth.uid()` 는 항상 `(select …)` 로 감싼다
- `auth.role()` 은 쓰지 않는다(deprecated). `to authenticated` 만으로는 인가가 아니다 — **소유자 조건을 반드시 붙인다.** 예외는 공개 참조 테이블 4개뿐이다: `universities`·`university_email_domains`·`region_group_settings`·`faq`. 이 중 `anon` 까지 여는 건 앞의 2개(`universities`·`university_email_domains`)뿐이고, 나머지 둘은 `authenticated` 전체까지만 연다(ERD.md §2)
- UPDATE 정책은 `using` + `with check` 둘 다 쓴다. UPDATE 는 SELECT 정책이 있어야 동작한다
- `user_metadata` 로 권한을 판단하지 않는다(사용자가 수정 가능). 권한 데이터는 `app_metadata`
- `security definer` 함수는 쓰지 않는다(권한 오류 우회용 금지). 뷰는 `with (security_invoker = true)`
- **클라이언트 쓰기 정책은 두지 않는다.** 쓰기는 전부 FastAPI가 `service_role`로 한다(2026-09-13 확정, ERD.md §11-8). `anon`·`authenticated`에는 INSERT·UPDATE·DELETE 권한 자체를 주지 않는다(42501로 끝난다)
- **grant는 RLS와 같은 마이그레이션에 둔다.** 새 테이블에 `anon`·`authenticated` 권한이 자동으로 붙는지는 프로젝트 설정마다 달라 믿지 않는다 — 테이블마다 `revoke all ... from anon, authenticated, service_role` 뒤에 ERD.md §2 표대로 `anon`·`authenticated`에는 필요한 `select`만 주고, `service_role`에는 `select`·`insert`·`update`·`delete`를 모두 준다. `service_role`까지 revoke하는 이유는 자동 grant 여부(프로젝트 설정·적용 시점)와 상관없이 결과를 같게 만들기 위해서다
- **클라이언트 Storage 정책은 두지 않는다.** 업로드·조회는 FastAPI가 발급하는 서명 업로드 URL·서명 URL로만 한다(2026-09-13 확정, ERD.md §9·§11-8)
- RLS 테스트는 pgTAP (`supabase/tests/*.sql`) — 다른 사용자로 조회 시 0행뿐 아니라, `anon`·`authenticated`·`service_role`·`PUBLIC`의 테이블·컬럼 권한(ACL), Storage 버킷·정책, 탈퇴 cascade까지 표대로 맞는지 검사한다. 기대값 기준은 ERD.md §2 (`frontend/CLAUDE.md` §8)
- **`realtime.messages`(Supabase 내장 Realtime 표)에 정책을 둘 때(2026-10-13, `20261013152736`)** — 위 "`public` 스키마" 규칙의 바깥이다
  - 정책은 마이그레이션(`postgres` 역할)으로 만들 수 있다. 표 · publication · grant 는 Supabase 가 관리하므로 건드리지 않는다
  - 토픽은 행의 `topic` 칸이 아니라 **`(select realtime.topic())`** 로 본다(Realtime 이 입장 때 세션에 건다). `auth.uid()` 처럼 `(select …)` 로 감싼다. 받기(`for select`)만 두고 **보내기(`for insert`) 정책은 만들지 않는다**(쏘는 쪽은 서버 `service_role` 뿐 — RLS 를 거치지 않는다)
  - 정책은 **입장 때 한 번 계산돼 연결 동안 캐시된다** — 방을 나간 사람처럼 "입장 뒤 바뀌는 권한" 을 정책으로 막을 수 없다. 서버가 쏘지 않는 것으로 막는다
  - **pgTAP**: `realtime.messages` 는 `inserted_at` **하루 단위 파티션 표**이고 기본 파티션이 없다(맞는 파티션이 없으면 넣기가 실패). 파티션은 Realtime 서비스가 며칠 앞까지 만들고 `postgres` 는 `realtime` 스키마에 표를 만들 권한이 없어 시험이 만들 수 없다 — 그래서 시험 행은 오늘 날짜가 아니라 **이미 있는 파티션 가운데 가장 늦은 날짜**로 넣는다(`supabase/tests/user_channel_realtime_policy_test.sql`, 파티션이 하나도 없으면 오류로 멈춘다). 받기 판정은 Realtime 과 같은 설정(`role` · `request.jwt.claim.sub` · `realtime.topic`)을 세션에 걸고 시험 행이 보이는지로 본다. 알려진 사소: 한 시험이 표 전체를 읽어 로컬에 다른 행이 있으면 거짓 FAIL 이 날 수 있다(후속으로 `where topic` 조건)

## 6. pgvector

- 조각 0 첫 마이그레이션(`20260913054542`) 맨 앞에서 `create extension if not exists vector with schema extensions;` 로 켰고, 2026-09-14 클라우드에 적용됐다. 대시보드에서 손으로 켜지 않는다. 조각 3 벡터 컬럼의 타입 주의는 `docs/ERD.md` §3

## 7. 학생증 재검토 — 대시보드 수동 확정

이 절은 더는 쓰지 않는다. 학생증 단계가 없어져(2026-10-17) 새 학생증 재검토는 생기지 않는다. 졸업생 인증의 검수는 관리자 웹 "졸업생" 화면에서 하고(결정 즉시 사진 삭제 — 손으로 지울 일이 없다), 절차는 `backend/DEPLOY.md` §4-14 · `docs/decisions/2026-10-19-graduate-verification-decision.md` 에 있다. 옛 대시보드 수동 확정 절차는 `docs/history/erd-log-2026.md` B 에 있다. 옛 `student-id-temp` 파일 삭제는 사용자 승인 대기다.

## 8. 실명 · 카카오톡 아이디 암호화

`profile_private` 의 실명 · 카카오톡 아이디를 전화번호(`phone_number`)와 같은 방식으로 암호화해 둔다. 적용 · 운영 기록은 `backend/DEPLOY.md` §4-4, 결정은 `docs/ERD_DECISIONS.md` §11-29 · §11-30 이다.

**지금 상태**: 평문 열 `real_name` · `kakao_id` 는 없다 — 실명 · 카톡 아이디는 암호문 `real_name_enc` · `kakao_id_enc` 에만 있다. 남은 함수는 `set_real_name` · `set_kakao_id` · `decrypt_profile_private` **셋**(`service_role` 전용)이다. `authenticated` 의 컬럼 grant 는 `profile_id` 하나뿐이다.

- **열**: `real_name_enc` · `kakao_id_enc` — `bytea`, `extensions.pgp_sym_encrypt(평문, 키)` 암호문. 키는 전화번호와 **같은** `PHONE_ENCRYPTION_KEY`(FastAPI Secret Manager 전용, DB 에 두지 않는다). `authenticated` 에는 grant 하지 않는다(이후 조각에서 컬럼을 추가해도 `authenticated` 에는 grant 하지 않는다는 `20260914055617` 의 규칙). 빈 문자열은 암호화하지 않고 null 로 둔다
- **함수 3개** — 모두 security invoker · `search_path = ''` · `public` · `anon` · `authenticated` 실행 회수 · **`service_role` 만 실행**. 키가 null · 빈 문자열이면 22023 오류(pgcrypto 는 null 키에 조용히 null 을 돌려줘 암호문이 덮이거나 복호화가 전부 null 로 보이기 때문)
  - `set_real_name(p_profile uuid, p_real_name text, p_key text) returns void` — upsert(행이 없으면 만든다. 가입 뒤 첫 쓰기가 실명이다)
  - `set_kakao_id(p_profile uuid, p_kakao_id text, p_key text) returns void` — update 전용(행이 없으면 0행. 서버가 `ensure_private_row` 로 먼저 보장한다)
  - `decrypt_profile_private(p_profile uuid, p_key text) returns table (real_name text, kakao_id text)` — 행이 없으면 0행, 암호문이 null 이면 그 값만 null. 틀린 키는 39000 오류. 본인 · 관리자 조회에만 쓴다
- **키는 RPC 의 JSON 바디로만 넘긴다** — URL 쿼리스트링에 넣으면 웹서버 접근 로그에 남는다(`app/profile_onboarding/encryption.py`)
- **읽기 · 쓰기 규칙**: **복호화 전용, 실패는 오류다.** 쓰기는 암호화 RPC(`set_real_name` · `set_kakao_id`) 하나뿐이고 실패하면 요청이 실패한다(삼키지 않는다). 읽기는 `core/postgrest.py` `_read_private` 한 곳이 `decrypt_profile_private` 로만 하고, 온보딩 진행 판단(`kakao_id_set`)도 같은 복호화 값을 본다. **복호화가 실패하면 None 으로 삼키지 않고 예외로 올린다** — None 이면 "아직 안 냈다" 로 보여 이미 낸 사람을 입력 화면으로 되돌리거나 상대에게 아이디가 없는 것처럼 보이기 때문이다. 복호화 실패 로그에는 `profile_id` · 상태 코드만 남긴다(예외 문구에 주소가 들어 있어 쓰지 않는다)
- **키 로그 노출 점검**: `pg_stat_statements` · Postgres 로그에 `pgp_sym_encrypt` / `pgp_sym_decrypt` 의 키 인자가 `$1` 같은 자리표시자로만 보이는지, `log_statement` · `auto_explain` 이 인자 값을 남기지 않는지 본다. 운영 점검 결과: RPC 문장은 본문이 파라미터라 키가 평문으로 남지 않았고, 운영 `log_statement` 는 `ddl` 이다
- **대시보드에서 손으로 복호화해야 할 때**: `select * from public.decrypt_profile_private('<profile_id>', '<키>');` — 키를 SQL 창에 붙여넣는 일 자체가 감사 대상이라 실행 전후로 사유를 운영 기록에 남긴다. 평소 원칙은 "운영자는 `profile_private` 를 FastAPI 관리 기능으로만 본다"(ERD_DECISIONS §11-18)
- M2(평문 열 · 백필 함수 삭제)는 되돌릴 수 없다. 실행 기록 · 롤백 주의는 `backend/DEPLOY.md` §4-4 "M2 실행 기록"
