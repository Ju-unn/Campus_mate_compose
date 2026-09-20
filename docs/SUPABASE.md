# SUPABASE.md — CampusMate Supabase 작업 규칙

**Supabase 작업(스키마·RLS·Storage·Auth)을 하기 전에 이 문서를 먼저 읽는다.**

`frontend/CLAUDE.md` §10.1 에서 떼어낸 문서다(2026-09-15). `frontend/CLAUDE.md` §10.1 에는 금지 규칙 요약만 남겼고, 마이그레이션 주석과 ERD 가 인용하는 "`frontend/CLAUDE.md` §10.1" 의 세부 규칙은 이 문서에 있다.

## 1. 현재 상태

Supabase **MCP 플러그인(`supabase`)이 설치·인증돼 있다.** 클라우드 프로젝트는 `campus_mate`(조직 CampusMate, Seoul) 하나뿐이다. 조각 0(테이블 4·RLS·정책 4·private 버킷 `profile-photos`·seed `universities` 20행·`university_email_domains` 20행)은 2026-09-14 사용자 승인 후 적용됐다. **조각 1(1a 이메일 인증 훅)·조각 1b(학생증 인증) 마이그레이션 클라우드 적용 완료(2026-09-20, MCP `list_migrations` 확인).** 1b 쪽 적용분: `20260914055607`(학생증 인증 컬럼)·`20260914055617`(profile_private)·`20260914055624`(student-id-temp 버킷)·`20260914061304`(student_verification_attempts)·`20260914061821`(profile-photos 버킷 제한)·`20260919181319`(student_number 컬럼) — `20260914055631`(RLS 자동 활성 execute revoke)은 이전 라운드에 이미 적용됐다. **학생증 사진 삭제 트리거 마이그레이션(`20260919181357`)은 클라우드에 올라간 적 없이 폐기·삭제됐다** — SQL 트리거로 `storage.objects` 를 지우면 메타 행만 지워지고 실제 파일은 고아로 남아, FastAPI 가 확정 직후 Storage API로 직접 지우는 방식으로 바꿨다(§7, ERD.md §9, ERD_DECISIONS.md §11-27). 조각 2 이후는 파일도 없다(세부 스키마 상태는 `docs/ERD.md` 상태줄 기준). 로컬 스택(Docker)은 없으므로 적용 대상은 항상 이 클라우드 프로젝트다.

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

## 6. pgvector

- 조각 0 첫 마이그레이션(`20260913054542`) 맨 앞에서 `create extension if not exists vector with schema extensions;` 로 켰고, 2026-09-14 클라우드에 적용됐다. 대시보드에서 손으로 켜지 않는다. 조각 3 벡터 컬럼의 타입 주의는 `docs/ERD.md` §3

## 7. 학생증 재검토 — 대시보드 수동 확정

자동 대조(OCR)가 애매하거나 실패하면 담당자가 Supabase 대시보드에서 학생증 사진을 직접 열어 육안으로 재검토한다(설계 §7.3). 자동 확정과 다르게 이 경로는 FastAPI를 거치지 않으므로, 사람이 손으로 아래 순서를 그대로 따라야 한다 — 순서를 바꾸면 안 되는 이유는 자동 경로와 같다: `student_verification_attempts` 를 먼저 확정하고 남에게 보이는 `profiles` 를 나중에 바꾼다(§11-27, 2026-09-20 결정).

1. **`student_verification_attempts`** 에서 해당 제출 행을 찾아 `result` 를 `verified` 또는 `rejected` 로 바꾸고, `reviewed_at` 을 지금 시각으로 채운다. `rejected` 면 `reject_reason` 도 채운다(본인에게 재검토 결과로 내려간다)
2. 같은 `profile_id` 의 **`profiles.student_verification`** 을 1번과 같은 값으로 바꾼다(자동 경로와 같은 순서 — attempts 먼저, profiles 나중)
3. **`student-id-temp` 버킷에서 해당 파일을 Storage UI 로 손으로 지운다.** 자동 확정은 FastAPI 가 확정 직후 Storage API로 파일을 지우지만(§1, ERD.md §9), 대시보드 수동 확정은 이 자동 삭제 경로를 타지 않으므로 지우지 않으면 파일이 그대로 남는다
