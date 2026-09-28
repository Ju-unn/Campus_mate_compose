-- 무료로 하트 모으기(18a · 18b · 18c): 인증샷 제출과 사람 검수. 기준 문서 docs/ERD.md §6 · §8 · §9, DESIGN §8.10.
-- 클라이언트는 본인 줄 읽기만 한다(ERD §2 85줄). 쓰기는 FastAPI(service_role)와 대시보드의 운영자뿐이다.
create type public.heart_task as enum ('everytime_post', 'kakao_share');
create type public.submission_status as enum ('submitted', 'approved', 'rejected');
-- 운영자는 고르기만 한다 — 자유 글이면 캡처 속 이름 같은 것이 사용자 화면으로 샐 수 있다(계획서 D3).
create type public.heart_task_reject_reason as enum ('date_missing', 'not_verified', 'reused');

create table public.heart_task_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  task public.heart_task not null,
  -- 검수가 끝나고 60일 뒤 정리 배치가 파일을 지우고 비운다(D6). 검수 중에는 반드시 있다(아래 check).
  storage_path text,
  status public.submission_status not null default 'submitted',
  -- 제출 때 약속한 하트. 승인 트리거가 이 값을 준다 — 서버 값이 바뀌는 날 검수 중이던 제출도 약속대로(D5).
  reward_hearts integer not null,
  reject_reason public.heart_task_reject_reason,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,

  constraint heart_task_submissions_reward_positive check (reward_hearts > 0),
  constraint heart_task_submissions_proof_while_reviewing check (status <> 'submitted' or storage_path is not null),
  constraint heart_task_submissions_reviewed_at check ((status = 'submitted') = (reviewed_at is null)),
  -- 반려면 사유가 반드시 있고, 반려가 아니면 없다. 대시보드에서는 "Edit row" 로 두 칸을 한 번에 저장한다.
  constraint heart_task_submissions_reject_reason check ((status = 'rejected') = (reject_reason is not null))
);

comment on table public.heart_task_submissions is
  '무료 하트 인증샷 제출. FastAPI 가 넣고 운영자가 대시보드에서 status 를 바꾼다. 승인하면 트리거가 하트를 한 번 준다';

-- 한 항목에 검수 중인 줄은 하나뿐. 거의 동시에 낸 두 번째는 23505 → 서버 409.
-- 월 한도(검수 중 + 승인)도 이 인덱스 덕에 잠금 없이 맞다 — 같은 항목의 두 번째 insert 가 여기서 막힌다.
create unique index heart_task_submissions_one_reviewing
  on public.heart_task_submissions (profile_id, task) where status = 'submitted';
-- 이번 달 세기와 탈퇴 cascade 가 profile_id 로 찾는다.
create index heart_task_submissions_profile_id_created_at_index
  on public.heart_task_submissions (profile_id, created_at);

alter table public.heart_task_submissions enable row level security;

create policy "heart task submissions are readable by owner"
  on public.heart_task_submissions for select to authenticated
  using ((select auth.uid()) = profile_id);

revoke all on table public.heart_task_submissions from anon, authenticated, service_role;
grant select on table public.heart_task_submissions to authenticated;
grant select, insert, update, delete on table public.heart_task_submissions to service_role;

-- 인증샷 버킷. 다른 버킷처럼 클라이언트용 storage.objects 정책은 없다 — FastAPI 가 service_role 로 올리고 지운다.
-- 버킷 제한은 신고된 content type · 크기로만 막으므로 파일 내용(매직 바이트)은 FastAPI 가 올리기 전에 본다.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('heart-task-proofs', 'heart-task-proofs', false, 10485760, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;
