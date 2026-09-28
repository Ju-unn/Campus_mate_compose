-- 지인 리뷰(20b · 20c · 14c · 14d). 기준 문서 docs/ERD.md §6, spec §2.8, DESIGN §8.8 · §13-25.
-- 클라이언트는 이 표에 접근하지 않는다(ERD §2 "FastAPI 전용"). 쓸 자격(referrals 양방향)과
-- 숨김(작성자 active 아님 · 차단)을 FastAPI 가 한 곳에서 본다.
create table public.friend_reviews (
  id uuid primary key default gen_random_uuid(),
  reviewer_id uuid not null references public.profiles (id) on delete cascade,
  reviewee_id uuid not null references public.profiles (id) on delete cascade,
  tags text[] not null,
  comment text,
  status public.content_status not null default 'visible',
  created_at timestamptz not null default now(),
  -- 한 사람에게 한 번. 두 번째 insert 는 23505 → 서버 409. 수정 · 삭제 화면은 없다(계획서 결정 2).
  constraint friend_reviews_once unique (reviewer_id, reviewee_id),
  constraint friend_reviews_not_self check (reviewer_id <> reviewee_id),
  -- 12종 목록 검사는 FastAPI 가 한다(profiles.interest_tags 와 같은 관례). DB 는 개수만 본다.
  constraint friend_reviews_tags_count check (cardinality(tags) between 1 and 3),
  -- 서버가 앞뒤 공백을 깎고 빈 한마디는 null 로 넣는다.
  constraint friend_reviews_comment_length
    check (comment is null or (char_length(comment) between 1 and 100 and comment = btrim(comment)))
);

comment on table public.friend_reviews is
  '지인 리뷰. FastAPI 전용. 받은 사람은 지울 수 없다(spec §2.8). 작성자가 active 가 아니면 읽을 때 숨긴다';

-- 받은 목록(20c · 14c · 14d)은 reviewee_id 로 최신순. reviewer_id 는 unique 앞머리가 탈퇴 cascade 를 받는다.
create index friend_reviews_reviewee_id_created_at_index
  on public.friend_reviews (reviewee_id, created_at desc);

alter table public.friend_reviews enable row level security;

revoke all on table public.friend_reviews from anon, authenticated, service_role;
grant select, insert, update, delete on table public.friend_reviews to service_role;
