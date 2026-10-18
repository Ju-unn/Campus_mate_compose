-- 관리자 웹 대시보드 D0(설계 바탕화면 관리자_대시보드_설계_10-18.md §7 · §8 머리): 관리자 작업 기록.
-- 관리자 쓰기 경로는 모두 같은 요청 안에서 한 줄을 남기고, 기록이 실패하면 요청도 실패한다
-- (backend/app/admin/repository.py record_action). 기존 "표 없이 로그" 결정(ERD §11-13)을 사용자가 10-18 에 바꿨다.
-- 보관 2년(접속기록 요건 1~2년 중 긴 쪽). 지우는 배치는 1판에 없다.
-- 시험: supabase/tests/admin_foundation_test.sql · rls_slice0_test.sql(권한 목록)

create table public.admin_actions (
  id uuid primary key default gen_random_uuid(),
  -- FK 를 두지 않는다 — 관리자 auth 계정이 지워져도 누가 무엇을 했는지는 남아야 한다.
  admin_user_id uuid not null,
  -- 값 목록 대신 형식만 본다 — 동작이 늘 때마다 마이그레이션을 하지 않게(예: heart_task_approve, report_dismiss).
  action text not null,
  -- 대상 종류(예: heart_task_submission · report · profile)와 그 id. id 는 uuid 가 아닌 대상도 받게 글자로 둔다.
  target_type text,
  target_id text,
  -- 바뀌기 전 · 뒤 값. 전화번호 · 카카오톡 아이디 원문 같은 민감값은 넣지 않는다 — 열람은 "열람했다" 만 남긴다.
  before jsonb,
  after jsonb,
  -- 관리자가 적은 사유(정지 · 하트 조정 · 열람은 필수 — 서버가 본다).
  reason text,
  ip inet,
  created_at timestamptz not null default now(),

  constraint admin_actions_action_format check (action ~ '^[a-z][a-z0-9_]{2,63}$'),
  constraint admin_actions_reason_length check (reason is null or char_length(reason) <= 500)
);

comment on table public.admin_actions is
  '관리자 작업 기록(누가 · 언제 · 무엇을 · 왜). FastAPI 전용 — 쓰기는 record_action 한 곳, 클라이언트 접근 없음. '
  'service_role 도 select · insert 만 — 고치거나 지울 수 없다. 민감값(전화 · 카톡 원문)은 before · after 에 없다. 보관 2년.';

-- 조회용: 최근 순 전체 · 대상별 · 관리자별(GET /admin/actions?admin=&target=). 둘째 · 셋째는 최근 순 정렬까지 인덱스로 끝낸다.
create index admin_actions_created_at_index on public.admin_actions (created_at desc);
create index admin_actions_target_created_at_index on public.admin_actions (target_type, target_id, created_at desc);
create index admin_actions_admin_user_id_created_at_index on public.admin_actions (admin_user_id, created_at desc);

-- RLS: 정책 없음 = 앱 · 브라우저는 읽지도 쓰지도 못한다.
alter table public.admin_actions enable row level security;

-- 관례(SUPABASE.md §5 — service_role 에 넷 다)와 일부러 다르다: select · insert 만 준다. 기록은 고쳐지거나 지워지면 안 된다
-- (설계 §2 "실패로 볼 것"). 2년 정리 배치를 만들 때 그 배치용 delete 권한을 따로 더한다.
revoke all on table public.admin_actions from anon, authenticated, service_role;
grant select, insert on table public.admin_actions to service_role;

-- 권한만으로는 표 주인 postgres(대시보드 SQL 창 · 표 편집기)를 막지 못한다 — 손으로 고치거나 지우는 실수까지 트리거로 막는다
-- (사용자 결정 10-18 B). 문장 단위라 맞는 행이 0개여도 막고, truncate 도 막는다. 오류 코드는 "고정된 행" 관례 CM409
-- (heart_task_submissions_guard 와 같다). service_role 은 이 트리거보다 먼저 권한 검사(42501)에서 막힌다.
-- 2년 보관 정리 배치를 만들 때 이 트리거를 함께 다룬다.
create function public.admin_actions_append_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'admin_actions is append-only' using errcode = 'CM409';
end;
$$;

create trigger admin_actions_append_only
  before update or delete or truncate on public.admin_actions
  for each statement execute function public.admin_actions_append_only();

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.admin_actions_append_only() from public, anon, authenticated;
