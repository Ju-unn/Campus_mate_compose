-- 조각 6: 신고. 클라이언트는 존재 자체를 몰라도 된다(default deny) — FastAPI 만 다룬다.
create type public.report_target as enum ('profile', 'message', 'friend_review', 'poll');
create type public.report_status as enum ('open', 'actioned', 'dismissed');
create type public.report_reason as enum ('abuse', 'sexual', 'spam', 'fake', 'other');

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  -- 신고자가 탈퇴해도 근거는 남는다(설계 §2.6 FK 규칙의 예외).
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type public.report_target not null,
  -- FK 를 걸지 않는다. 신고 대상 행(메시지·리뷰·글)이 지워져도 신고는 남아야 한다.
  target_id uuid not null,
  target_profile_id uuid references public.profiles (id) on delete set null,
  -- 원본이 사라져도 24시간 조치 근거가 남아야 한다(애플 1.2, ERD §5).
  target_snapshot jsonb not null,
  reason public.report_reason not null,
  reason_note text,
  status public.report_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint reports_status_pair check ((status = 'open') = (resolved_at is null)),
  constraint reports_reason_note_length
    check (reason_note is null or char_length(btrim(reason_note)) between 1 and 200),
  -- 결정 3: 같은 사람이 같은 대상을 두 번 신고하지 못한다. "3명" 을 세는 기준이기도 하다.
  constraint reports_once_per_reporter unique (reporter_id, target_type, target_id)
);

comment on table public.reports is
  '신고. FastAPI 전용, 클라이언트 접근 없음(설계 §2.6). target_id 는 FK 없이 원본이 지워져도 남는다';

-- target_profile_id: 메시지를 신고해도 "누가 신고당했는가" 를 조인 없이 세야 한다(3명 세기 · 대시보드).
create index reports_target_profile_id_index on public.reports (target_profile_id);
-- 1년 정리 배치 기준(B3). resolved_at 이 아니라 created_at 인 이유: open 신고는 resolved_at 이
-- null 이라(reports_status_pair) resolved_at 으로 세면 처리되지 않은 신고가 영원히 남는다.
create index reports_created_at_index on public.reports (created_at);
-- reporter_id 는 reports_once_per_reporter unique 제약의 앞머리라 따로 인덱스를 만들지 않는다.

alter table public.reports enable row level security;

revoke all on table public.reports from anon, authenticated, service_role;
grant select, insert, update, delete on table public.reports to service_role;
