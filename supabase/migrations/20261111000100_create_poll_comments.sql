-- O/X 글 댓글(2026-11-10) 2/3: 표 둘 + 알림 스위치 칸 + 알림 종류. 함수는 다음 파일(20261111000200).
-- 사용자 결정 원문: 「익명1 · 익명2 + 글쓴이 표시」 「둘다 좋아요 기능은 빼자」(글 · 댓글 모두 좋아요 없음)
--   「보냄 + 알림 설정에 끄기 칸」 「댓글에 신고기능 있어야해 / 게시물 작성자는 댓글 삭제기능 있어야해」 「10개씩 불러오기」
-- 클라이언트는 두 표 모두 접근하지 않는다 — polls 와 같은 틀(RLS 켜고 정책 0, service_role 만). author_id 를 열면 익명이 깨진다.
-- 탈퇴 정리: 글이 지워지면(polls cascade) 댓글 · 번호가 같이 지워지고, 계정이 지워지면(profiles cascade) 그 사람의 댓글 · 번호가
-- 지워진다. FK 를 no action 으로 두면 auth.users 삭제가 23503 으로 막힌다(docs/ERD.md 71줄). 읽을 때 active 작성자만 보이게 한다.

create table public.poll_comments (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  status public.content_status not null default 'visible',
  created_at timestamptz not null default now(),
  -- 서버가 앞뒤 공백을 깎아 넣는다. 깎인 모양이 아니면 빈칸뿐인 댓글이 들어온 것이다(polls_question_length 와 같다).
  constraint poll_comments_body_length check (char_length(body) between 1 and 200 and body = btrim(body))
);

comment on table public.poll_comments is
  'O/X 글 댓글. FastAPI 전용. author_id 는 어떤 응답에도 담지 않는다(poll_comments_page 가 칸을 주지 않는다)';

-- 목록(오래된 순 + (created_at, id) 커서)과 피드의 댓글 수 세기가 둘 다 poll_id 앞머리로 찾는다.
create index poll_comments_poll_created_id_index on public.poll_comments (poll_id, created_at, id);
-- 하루 50개 세기와 탈퇴 cascade 가 author_id 로 찾는다.
create index poll_comments_author_created_index on public.poll_comments (author_id, created_at);

-- 글 안에서만 쓰는 익명 번호. 첫 댓글을 쓸 때 다음 번호(1, 2, …)를 받고 그 글에서는 같은 번호로 남는다.
-- 글쓴이 자신은 번호를 받지 않는다("글쓴이" 로 보인다).
create table public.poll_comment_aliases (
  poll_id uuid not null references public.polls (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  alias_no integer not null check (alias_no >= 1),
  primary key (poll_id, profile_id),
  constraint poll_comment_aliases_no_unique unique (poll_id, alias_no)
);

comment on table public.poll_comment_aliases is
  'O/X 글 안의 익명 번호(익명1 · 익명2). FastAPI 전용. 글쓴이는 행이 없다';

-- 탈퇴 cascade 가 profile_id 로 찾는다(PK 앞머리는 poll_id 라 못 탄다).
create index poll_comment_aliases_profile_index on public.poll_comment_aliases (profile_id);

alter table public.poll_comments enable row level security;
alter table public.poll_comment_aliases enable row level security;

revoke all on table public.poll_comments from anon, authenticated, service_role;
grant select, insert, update, delete on table public.poll_comments to service_role;

revoke all on table public.poll_comment_aliases from anon, authenticated, service_role;
grant select, insert, update, delete on table public.poll_comment_aliases to service_role;

-- 알림 스위치: 내 글의 새 댓글(앱 16d 에 칸이 생긴다). 기본 켜짐, 이미 있는 행도 켜짐으로 채워진다.
alter table public.notification_settings
  add column poll_comment boolean not null default true;

-- 알림함(notifications)과 밤 보관함(pending_pushes)이 새 종류 poll_comment 를 받게 check 만 넓힌다.
-- 20261018130100 의 목록 그대로 + poll_comment. 한 문장(drop + add)이라 사이에 빈틈이 없다.
-- 서버가 이 마이그레이션보다 먼저 배포되면 알림함 insert 가 check 위반으로 조용히 실패하므로 서버 배포보다 먼저 적용한다.
alter table public.notifications
  drop constraint notifications_kind_check,
  add constraint notifications_kind_check check (kind in (
    'card_arrived', 'chat_request', 'match_made', 'friend_review', 'verification_result', 'night_digest',
    'heart_task_approved', 'heart_task_rejected', 'poll_comment'
  ));

alter table public.pending_pushes
  drop constraint pending_pushes_kind_check,
  add constraint pending_pushes_kind_check check (kind in (
    'acceptance_received', 'match_made', 'new_friend_review', 'verification_result',
    'heart_task_approved', 'heart_task_rejected', 'poll_comment'
  ));
