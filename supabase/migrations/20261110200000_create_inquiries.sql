-- 문의하기: 앱에서 사유 + 내용 + 답장 받을 메일을 보내면 FastAPI 가 저장하고 운영 메일로 알린다.
-- 클라이언트는 존재 자체를 몰라도 된다(default deny) — FastAPI 만 다룬다. reports(20260927010200)와 같은 틀.
create type public.inquiry_reason as enum ('account', 'payment', 'matching', 'safety', 'bug', 'other');
create type public.inquiry_status as enum ('new', 'in_progress', 'answered');

create table public.inquiries (
  id uuid primary key default gen_random_uuid(),
  -- 탈퇴해도 답변 완료 후 1년은 남긴다(보관 정리가 지울 때까지) — reports 와 같은 set null.
  profile_id uuid references public.profiles (id) on delete set null,
  reason public.inquiry_reason not null,
  body text not null,
  -- 답장 받을 메일. 학교 메일이 아니어도 되는 사용자가 적는 값이라 형식만 본다(공백 · 줄바꿈이 없는 a@b.c 꼴).
  reply_email text not null,
  status public.inquiry_status not null default 'new',
  admin_memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- 상태가 answered 일 때만 값이 있다(reports_status_pair 와 같은 꼴). 1년 보관의 기준 시각이다.
  answered_at timestamptz,
  constraint inquiries_body_length check (char_length(btrim(body)) between 1 and 1000),
  constraint inquiries_reply_email_length check (char_length(reply_email) <= 254),
  -- \s 가 줄바꿈 · 탭 · 공백을 모두 막는다 — 메일 헤더 주입(Reply-To)의 마지막 방어선.
  constraint inquiries_reply_email_format check (reply_email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  constraint inquiries_admin_memo_length check (admin_memo is null or char_length(admin_memo) <= 1000),
  constraint inquiries_status_pair check ((status = 'answered') = (answered_at is not null))
);

comment on table public.inquiries is
  '문의. FastAPI 전용, 클라이언트 접근 없음. profile_id 는 탈퇴하면 null. 답변 완료(answered_at) 후 1년 지나면 매일 04:00 배치가 지운다';

-- 관리자 목록: 최근 순 쪽 나누기 커서(created_at desc, id desc).
create index inquiries_created_at_id_index on public.inquiries (created_at desc, id desc);
-- 하루 5건 한도 세기(profile_id + 오늘 0시 이후).
create index inquiries_profile_id_created_at_index on public.inquiries (profile_id, created_at);
-- 상태 필터.
create index inquiries_status_index on public.inquiries (status);

alter table public.inquiries enable row level security;

revoke all on table public.inquiries from anon, authenticated, service_role;
grant select, insert, update, delete on table public.inquiries to service_role;
