-- 관리자 웹 매칭 현황(A9) — "누가 누구에게 대화를 신청했나". 지금 A9 은 서로 수락해 성립한 매칭 쌍만 보여 줘서 한쪽만 신청하고 끝난 신청이
-- 안 보인다. 새 표 없이 있는 표만 읽는다(읽기 전용 · admin_matching_pairs 와 같은 모양: security invoker · search_path '' · service_role 만 execute).
-- 신청 = 카드를 받은 사람(daily_cards.owner_id)이 수락한 것(card_decisions.decision = 'accept', 시각 decided_at). 받는 사람 = daily_cards.target_id.
-- 상태(상대 응답) — 받은 수락함 · 보낸 신청(backend/app/cards/router.py 의 _sent_state)과 같은 순서로 본다:
--   accepted = 두 사람의 matches 줄이 있음(상대 카드로 먼저 성립했어도 친다) 또는 응답이 accept /
--   rejected = 응답이 reject(매칭 없음) / expired = 응답이 없고 신청 후 7일이 지남 / waiting = 그 밖.
-- 만료 기한 7일 = router.py 의 ACCEPTANCE_TTL_DAYS. 7일이 "딱" 지난 순간부터 만료다(받는 쪽이 410 을 받는 경계 decided_at <= now - 7일과 같다).
-- 신청 즉시 매칭이 되는 길은 없다 — 매칭은 받은 사람이 수락에 답할 때만 만들어진다(respond_to_acceptance). 그래서 신청한 순간은 늘 waiting 이다.
-- 반환 칸이 **전부**다 — 사진 · 카톡 아이디 · 대화 · 전화는 싣지 않는다(카톡 아이디는 사용자 상세의 "열람"(사유 필수 · 기록)으로만).
-- 시험: supabase/tests/admin_matching_requests_test.sql

-- 커서는 (requested_at, card_id) 둘 다 있거나 둘 다 없어야 한다. p_limit 1~101(부르는 쪽이 한 줄 더 달라고 해 다음 쪽 여부를 안다).
-- 응답 시각: accepted 는 응답이 accept 면 그 시각, 아니면(상대 카드로 먼저 매칭) 매칭이 생긴 시각 / rejected 는 응답 시각 / 그 밖은 null.
-- shortcut: 수락(card_decisions.decision = 'accept') 전체를 훑고 정렬한다 — 수락이 수십만 건을 넘으면 카드 결정 (decided_at desc, card_id desc) 인덱스를 더한다.
create function public.admin_matching_requests(p_status text, p_before_at timestamptz, p_before_id uuid, p_limit integer)
returns table (
  card_id uuid, requested_at timestamptz, status text, responded_at timestamptz,
  requester_id uuid, requester_nickname text, requester_university text,
  target_id uuid, target_nickname text, target_university text
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_status is not null and p_status not in ('waiting', 'accepted', 'rejected', 'expired') then
    raise exception 'unknown status' using errcode = '22023';
  end if;
  if (p_before_at is null) <> (p_before_id is null) then
    raise exception 'cursor needs both parts' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 101 then
    raise exception 'p_limit must be between 1 and 101' using errcode = '22023';
  end if;

  return query
  with listed as (
    select cd.card_id as cid, cd.decided_at as req, dc.owner_id as oid, dc.target_id as tid,
           ar.decision as rdec, ar.decided_at as rat, m.created_at as mat
      from public.card_decisions cd
      join public.daily_cards dc on dc.id = cd.card_id
      left join public.acceptance_responses ar on ar.card_id = cd.card_id
      left join public.matches m
        on m.profile_a = least(dc.owner_id, dc.target_id) and m.profile_b = greatest(dc.owner_id, dc.target_id)
     where cd.decision = 'accept'
       and (p_before_at is null or (cd.decided_at, cd.card_id) < (p_before_at, p_before_id))
  ), staged as (
    select l.*,
           case when l.mat is not null or l.rdec = 'accept' then 'accepted'
                when l.rdec = 'reject' then 'rejected'
                when l.req <= now() - interval '7 days' then 'expired'
                else 'waiting' end as st
      from listed l
  )
  select s.cid, s.req, s.st,
         case s.st when 'accepted' then coalesce(case when s.rdec = 'accept' then s.rat end, s.mat)
                   when 'rejected' then s.rat end,
         r.id, r.nickname, ur.name, t.id, t.nickname, ut.name
    from staged s
    join public.profiles r on r.id = s.oid
    join public.profiles t on t.id = s.tid
    left join public.universities ur on ur.id = r.university_id
    left join public.universities ut on ut.id = t.university_id
   where p_status is null or s.st = p_status
   order by s.req desc, s.cid desc
   limit p_limit;
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_matching_requests(text, timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function public.admin_matching_requests(text, timestamptz, uuid, integer) to service_role;
