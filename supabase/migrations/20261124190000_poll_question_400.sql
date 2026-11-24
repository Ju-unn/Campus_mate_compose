-- 1.0.7 투표 질문 상한 80 → 400자(사용자 결정 2026-11-24 「게시물 500 유지, 투표 400」). 게시물 500 · 공지 2000 은 그대로.
-- polls_question_length 의 마지막 정의(20261124090000_community_notices.sql)에서 poll 값만 바꾼다. 다른 check · 칸은 손대지 않는다.
-- 배포 순서: 이 마이그레이션 → 서버(QUESTION_MAX_LENGTH 400) → 1.0.7 앱(pollQuestionMaxLength 400).
--   DB 가 먼저 넓어져야 서버가 받은 81~400자 질문이 23514 로 떨어지지 않는다. 서버보다 DB 가 넓은 동안은 서버가 80 에서 422 로 막는다.
-- 옛 앱(1.0.6): 쓰기는 앱이 80 에서 막아 그대로다. 읽기는 400자 질문을 받는다 — 피드 카드는 2줄 말줄임, 17c 상세는 전부 보인다
--   (1.0.6 feed_poll_card.dart maxLines 2 · poll_card.dart maxLines 없음). 응답 모양은 바뀌지 않는다.
-- 되돌리기: 400 → 80 으로 다시 좁히면 81자 넘는 투표가 있을 때 check 추가가 실패한다 — 그 글을 먼저 정리해야 한다.
-- 시험: supabase/tests/community_polls_test.sql · community_posts_test.sql(400 통과 · 401 거절).

-- polls 를 잠그는 alter table 은 do 블록 하나(= 한 문장)에 두고 잠금 시간 제한을 블록 안에서 건다(20261124090000 과 같은 모양 —
-- 로컬 CLI 는 문장마다 따로 돌려 블록 밖 `set local` 은 효과가 없다). 못 잡으면 아무것도 안 바뀐 채 실패하니 다시 적용하면 된다.
-- check 를 더하면 기존 줄을 한 번 훑는다 — 넓히는 변경이라 기존 글은 모두 맞는다.
do $$
begin
  perform set_config('lock_timeout', '5s', true);

  alter table public.polls
    drop constraint polls_question_length,
    add constraint polls_question_length check (
      question = btrim(question)
      and char_length(question) between 1 and case kind when 'poll' then 400 when 'post' then 500 else 2000 end);
end;
$$;

comment on column public.polls.question is '투표의 질문(1~400자) · 게시물 본문(1~500자) · 공지 본문(1~2000자). 앞뒤 공백을 깎은 모양';
