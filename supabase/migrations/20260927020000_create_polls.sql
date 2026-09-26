-- 커뮤니티 탭(15d · 17b · 17c): 익명 O/X 질문과 투표. 기준 문서 docs/ERD.md §7 · §8, DESIGN §8.11.
-- 클라이언트는 두 표 모두 접근하지 않는다(ERD §2 87줄) — author_id 를 열면 익명이 깨지고,
-- poll_votes 는 본인 행만 열면 집계가 안 되고 다 열면 누가 뭘 골랐는지 보인다.
create type public.content_status as enum ('visible', 'blinded');
create type public.poll_choice as enum ('a', 'b');

create table public.polls (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  question text not null,
  option_a_label text not null default '찬성',
  option_b_label text not null default '반대',
  status public.content_status not null default 'visible',
  created_at timestamptz not null default now(),
  -- 서버가 앞뒤 공백을 깎아 넣는다. 깎인 모양이 아니면 빈칸뿐인 글이 들어온 것이다.
  constraint polls_question_length check (char_length(question) between 1 and 80 and question = btrim(question)),
  constraint polls_option_a_length check (char_length(option_a_label) between 1 and 6 and option_a_label = btrim(option_a_label)),
  constraint polls_option_b_length check (char_length(option_b_label) between 1 and 6 and option_b_label = btrim(option_b_label)),
  constraint polls_options_differ check (option_a_label <> option_b_label)
);

comment on table public.polls is
  '커뮤니티 익명 질문. FastAPI 전용. author_id 는 어떤 응답에도 담지 않는다(poll_feed 가 칸을 주지 않는다)';

-- 피드: 최신순 + (created_at, id) 커서.
create index polls_created_at_id_index on public.polls (created_at desc, id desc);
-- 하루 10개 세기와 탈퇴 cascade 가 author_id 로 찾는다.
create index polls_author_id_created_at_index on public.polls (author_id, created_at);

create table public.poll_votes (
  poll_id uuid not null references public.polls (id) on delete cascade,
  voter_id uuid not null references public.profiles (id) on delete cascade,
  choice public.poll_choice not null,
  created_at timestamptz not null default now(),
  -- 재투표 불가(DESIGN §8.11). 두 번째 insert 는 23505 → 서버 409.
  primary key (poll_id, voter_id)
);

comment on table public.poll_votes is '커뮤니티 투표. FastAPI 전용. 되돌릴 수 없다';

-- PK 앞머리가 poll_id 라 집계는 PK 를 탄다. voter_id 는 탈퇴 cascade 용.
create index poll_votes_voter_id_index on public.poll_votes (voter_id);

alter table public.polls enable row level security;
alter table public.poll_votes enable row level security;

revoke all on table public.polls from anon, authenticated, service_role;
grant select, insert, update, delete on table public.polls to service_role;

revoke all on table public.poll_votes from anon, authenticated, service_role;
grant select, insert, update, delete on table public.poll_votes to service_role;
