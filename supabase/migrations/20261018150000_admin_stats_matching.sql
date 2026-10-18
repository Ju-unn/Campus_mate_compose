-- 관리자 웹 대시보드 D4(설계 바탕화면 관리자_대시보드_설계_10-18.md §8-4 · §8-4b · §8-4c): 홈 통계 · 30일 그래프 · 미등록 도메인 ·
-- 학교별 현황 · 운영 상태판 · 매칭 현황. 전부 **읽기만** 한다(쓰기 · 작업 기록 없음).
-- PostgREST 로는 날짜 묶음 · 조건부 개수 · 두 표 비교가 안 돼 읽기 전용 DB 함수로 둔다(D3 admin_billing_daily 와 같은 모양):
-- security invoker · search_path '' · service_role 만 execute. 읽기라 admin_assert 는 부르지 않는다(관문은 서버 get_admin_caller).
-- 규칙 위반은 22023(서버 422). 날짜는 한국 시간(Asia/Seoul) 하루 단위, 없는 날은 0, 오래된 순, 마지막 = 오늘.
-- 관리자 계정(admin_users)은 통계에서 뺀다(설계 §6-5): 프로필을 세는 곳과 신고자 · 제출자를 보는 곳에서 not exists.
-- 시험: supabase/tests/admin_stats_matching_test.sql

-- 1. 홈 숫자. 상태별 인원(관리자 제외) · 열린 신고 · 검수 대기 · 오늘 / 7일 가입.
-- 가입 = profiles.created_at 의 KST 날짜, 성별을 고른 프로필만(가입 중인 줄은 남/여를 모른다), 상태 불문. 7일 = 오늘 포함 7 KST 날.
-- 열린 신고 · 검수 대기는 "처리할 일의 양"이라 신고자 · 제출자가 누구든 센다.
-- shortcut: profiles 를 전부 훑는다(created_at 인덱스 없음) — 5만 줄을 넘으면 created_at 인덱스를 더한다.
create function public.admin_stats_overview()
returns table (
  pending_count integer, active_count integer, suspended_count integer, withdrawn_count integer,
  open_reports integer, pending_proofs integer, signups_today integer, signups_7d integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_start timestamptz := (v_today::timestamp at time zone 'Asia/Seoul');
  v_from timestamptz := ((v_today - 6)::timestamp at time zone 'Asia/Seoul');
begin
  return query
  select (count(*) filter (where p.status = 'pending'))::integer,
         (count(*) filter (where p.status = 'active'))::integer,
         (count(*) filter (where p.status = 'suspended'))::integer,
         (count(*) filter (where p.status = 'withdrawn'))::integer,
         (select count(*) from public.reports r where r.status = 'open')::integer,
         (select count(*) from public.heart_task_submissions s where s.status = 'submitted')::integer,
         (count(*) filter (where p.gender is not null and p.created_at >= v_start))::integer,
         (count(*) filter (where p.gender is not null and p.created_at >= v_from))::integer
    from public.profiles p
   where not exists (select 1 from public.admin_users a where a.user_id = p.id);
end;
$$;

-- 2. 일별 그래프(가입 남/여 · 신고 · 인증샷). 신고 · 인증샷은 관리자가 낸 줄을 빼고, 신고자가 탈퇴해 null 이 된 신고는 센다.
-- shortcut: reports(reports_created_at_index)는 범위를 타지만 profiles · heart_task_submissions 는 날짜 범위를 훑는다 —
-- 월 수백 건 · 수천 명 규모에서 충분하고, 5만 줄을 넘으면 created_at 인덱스를 더한다.
create function public.admin_stats_daily(p_days integer)
returns table (day date, male_signups integer, female_signups integer, report_count integer, proof_count integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from timestamptz;
begin
  if p_days is null or p_days < 1 or p_days > 90 then
    raise exception 'p_days must be between 1 and 90' using errcode = '22023';
  end if;
  v_from := ((v_today - (p_days - 1))::timestamp at time zone 'Asia/Seoul');

  return query
  with signups as (
    select (p.created_at at time zone 'Asia/Seoul')::date as d,
           (count(*) filter (where p.gender = 'male'))::integer as m,
           (count(*) filter (where p.gender = 'female'))::integer as f
      from public.profiles p
     where p.gender is not null
       and p.created_at >= v_from
       and not exists (select 1 from public.admin_users a where a.user_id = p.id)
     group by 1
  ), filed as (
    select (r.created_at at time zone 'Asia/Seoul')::date as d, count(*)::integer as n
      from public.reports r
     where r.created_at >= v_from
       and not exists (select 1 from public.admin_users a where a.user_id = r.reporter_id)
     group by 1
  ), proofs as (
    select (s.created_at at time zone 'Asia/Seoul')::date as d, count(*)::integer as n
      from public.heart_task_submissions s
     where s.created_at >= v_from
       and not exists (select 1 from public.admin_users a where a.user_id = s.profile_id)
     group by 1
  )
  select v_today - (p_days - 1) + g.i, coalesce(su.m, 0), coalesce(su.f, 0), coalesce(fi.n, 0), coalesce(pr.n, 0)
    from generate_series(0, p_days - 1) as g(i)
    left join signups su on su.d = v_today - (p_days - 1) + g.i
    left join filed fi on fi.d = v_today - (p_days - 1) + g.i
    left join proofs pr on pr.d = v_today - (p_days - 1) + g.i
   order by 1;
end;
$$;

-- 3. 미등록 학교 메일 도메인(시도 많은 순). 이미 university_email_domains 에 등록된 도메인은 뺀다 — 등록한 뒤에도 시도 기록은
-- 남아 계속 "미등록" 으로 보이면 헷갈린다(가입 쪽도 정확히 일치로 찾는다). 행 상한 5000(record_unknown_email_domain)이라 훑어도 된다.
create function public.admin_unknown_domains(p_limit integer)
returns table (domain text, attempt_count integer, first_seen_at timestamptz, last_seen_at timestamptz)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'p_limit must be between 1 and 500' using errcode = '22023';
  end if;

  return query
  select a.domain, a.attempt_count, a.first_seen_at, a.last_seen_at
    from public.unknown_email_domain_attempts a
   where not exists (select 1 from public.university_email_domains d where d.domain = a.domain)
   order by a.attempt_count desc, a.last_seen_at desc, a.domain
   limit p_limit;
end;
$$;

-- 4. 학교별 현황. 활성 = region_active_counts() 와 같은 규칙(active · 일시중지 아님 · 14일 안 접속 · 성별 있음) + 관리자 제외 —
-- 카드 주기가 적은 쪽 인원으로 정해지므로 같은 숫자여야 한다. 그 함수와 달리 아직 안 열린 학교도 센다(is_open 으로 구분).
-- p_include_empty 가 false 면 활성 0 이고 오픈 시각도 없는 학교는 뺀다(65곳 중 대부분이 0명).
create function public.admin_universities_status(p_include_empty boolean)
returns table (
  id uuid, name text, region_group text, card_opens_at timestamptz, is_open boolean,
  male_active integer, female_active integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_include_empty is null then
    raise exception 'p_include_empty is required' using errcode = '22023';
  end if;

  return query
  with counted as (
    select u.id as uid, u.name as uname, u.region_group as ugroup, u.card_opens_at as uopens,
           (count(p.id) filter (where p.gender = 'male'))::integer as m,
           (count(p.id) filter (where p.gender = 'female'))::integer as f
      from public.universities u
      left join public.profiles p
        on p.university_id = u.id
       and p.status = 'active'
       and not p.matching_paused
       and p.gender is not null
       and p.last_active_at > now() - interval '14 days'
       and not exists (select 1 from public.admin_users a where a.user_id = p.id)
     group by u.id
  )
  select c.uid, c.uname, c.ugroup, c.uopens, (c.uopens is null or c.uopens <= now()), c.m, c.f
    from counted c
   where p_include_empty or c.m + c.f > 0 or c.uopens is not null
   order by c.m + c.f desc, c.uname;
end;
$$;

-- 5. 오늘 지급분 조회(상태판 ① — Task 2)용 인덱스. daily_cards 는 가장 빨리 자라는 표이고 owner 로 시작하는 인덱스 둘뿐이라
-- issued_at 만으로는 전체를 훑는다.
create index daily_cards_issued_at_index on public.daily_cards (issued_at desc);

-- 6. 운영 상태판(설계 §8-4 E). **개수만** 돌려주고 정상 / 경고 / 위험 판단과 기준값(인자)은 서버가 정한다 — 기준을 마이그레이션 없이 바꾸려고.
--  ① cards_checked · cards_issued: 목적은 "지급 배치가 아예 안 돌았는지" 다. 지역마다 "오늘이 지급 요일(issue_weekdays)이고 지금이
--     issue_time + p_cards_grace_minutes 이후" 인 지역 중, 오늘(KST 0시~) 나간 무료(daily) 카드가 그 지역 사람에게 한 장이라도 있거나
--     (있으면 cards_issued +1) 카드를 받을 사람이 card_issue_owners() 에 있는 지역이 점검 대상이다(cards_checked +1).
--     카드를 다 받은 사람은 card_issue_owners() 에서 빠지므로 "오늘 카드가 나갔다" 를 먼저 본다 — 아니면 모두에게 지급된 날이
--     "받을 사람 없음" 으로 보인다. 받을 사람도 오늘 카드도 없으면(아직 안 열린 학교뿐인 11/2 전 · 후보가 없는 지역) 점검 대상이 아니다.
--     판정은 서버: 점검 대상이 없으면 해당 없음, cards_issued >= 1 이면 정상(후보 부족으로 일부 지역만 0장인 것은 경고하지 않는다),
--     점검 대상이 있는데 한 지역도 못 받았으면 위험.
--     issue_weekdays 는 배치가 사다리 결과로 적어 둔 값이다(cards/issuing.py) — 오늘 배치가 아예 안 돌아 사다리가 바뀐 날은 어긋날 수 있다.
--  ② stuck_rooms: 통과도 닫힘도 아닌 채 p_room_hours 시간이 지난 방. 매시 배치가 일부러 건너뛰는 방(한쪽이 나감 · 정지 · 탈퇴, chat/gate.py is_gone)은 뺀다.
--  ③ overdue_withdrawn: 탈퇴한 지 p_withdrawn_days 일이 넘었는데 아직 안 지워진 프로필(account/batch_router.py 가 30일 뒤 하루 100명씩 지운다).
--  ④ avatar_failures: 최근 p_avatar_hours 시간 안에 시작해 failed 가 된 아바타 시도 수.
--  ⑤ stuck_pushes: 조용한 시간에 보류됐는데 p_push_hours 시간이 넘도록 안 나간 푸시(정상이면 아침 08시 이후 비운다).
-- shortcut: ① 은 지역 루프(지역이 한 자리 수), matches · profile_avatars · pending_pushes 는 전체 훑기 — 방 1만 줄 · 아바타 시도 10만 줄을 넘으면 부분 인덱스를 더한다.
create function public.admin_health(
  p_cards_grace_minutes integer, p_room_hours integer, p_withdrawn_days integer, p_avatar_hours integer, p_push_hours integer
)
returns table (
  cards_checked integer, cards_issued integer, stuck_rooms integer, overdue_withdrawn integer,
  avatar_failures integer, stuck_pushes integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_start timestamptz := (v_today::timestamp at time zone 'Asia/Seoul');
  v_checked integer := 0;
  v_issued integer := 0;
  v_region_issued boolean;
  r record;
begin
  if p_cards_grace_minutes is null or p_cards_grace_minutes not between 0 and 1440
     or p_room_hours is null or p_room_hours not between 1 and 1000
     or p_withdrawn_days is null or p_withdrawn_days not between 1 and 1000
     or p_avatar_hours is null or p_avatar_hours not between 1 and 1000
     or p_push_hours is null or p_push_hours not between 1 and 1000 then
    raise exception 'health window out of range' using errcode = '22023';
  end if;

  for r in select s.region_group, s.issue_weekdays, s.issue_time from public.region_group_settings s loop
    -- date + time = timestamp. time 끼리 더하면 자정에서 감겨 틀려서 날짜에 얹는다.
    if not (extract(isodow from v_today)::smallint = any (r.issue_weekdays))
       or now() < ((v_today + r.issue_time + make_interval(mins => p_cards_grace_minutes)) at time zone 'Asia/Seoul') then
      continue;
    end if;
    -- 오늘 지급분을 먼저(materialized) 모아 daily_cards_issued_at_index 를 타게 한다. 이렇게 안 쓰면 플래너가 프로필 전체를 훑으며
    -- 사람마다 daily_cards 를 찾는다(합성 3만 명 · 30만 장에서 오늘 카드가 0장일 때 117ms → 0.9ms, 그 0장이 바로 경고가 필요한 경우다).
    v_region_issued := exists (
      with today as materialized (
        select dc.owner_id from public.daily_cards dc where dc.source = 'daily' and dc.issued_at >= v_start
      )
      select 1
        from today t
        join public.profiles p on p.id = t.owner_id
        join public.universities u on u.id = p.university_id
       where u.region_group = r.region_group
    );
    if not v_region_issued
       and not exists (select 1 from public.card_issue_owners() o where o.region_group = r.region_group) then
      continue;
    end if;
    v_checked := v_checked + 1;
    if v_region_issued then
      v_issued := v_issued + 1;
    end if;
  end loop;

  return query
  select v_checked, v_issued,
         (select count(*) from public.matches m
           where m.trust_passed_at is null and m.chat_closed_at is null
             and m.created_at < now() - make_interval(hours => p_room_hours)
             and not exists (
               select 1 from public.match_participants mp
                 join public.profiles pp on pp.id = mp.profile_id
                where mp.match_id = m.id and (mp.left_at is not null or pp.status in ('suspended', 'withdrawn'))
             ))::integer,
         (select count(*) from public.profiles w
           where w.status = 'withdrawn' and w.withdrawn_at < now() - make_interval(days => p_withdrawn_days))::integer,
         (select count(*) from public.profile_avatars av
           where av.status = 'failed' and av.created_at >= now() - make_interval(hours => p_avatar_hours))::integer,
         (select count(*) from public.pending_pushes pp2
           where pp2.created_at < now() - make_interval(hours => p_push_hours))::integer;
end;
$$;

-- 7. 매칭 현황 요약(설계 §8-4c). 수락 = card_decisions.decision='accept'(카드를 받은 사람의 결정 — 무료 · 유료 카드 모두, 날짜는 decided_at 의 KST).
-- 수락한 사람 = 수락한 카드의 owner_id 중복 없는 수. 매칭 = matches 줄, 카톡 아이디 공유 완료 = trust_passed_at 이 있는 줄(쌍방 공유 끝).
-- shortcut: accepters_total 은 accept 전체를 훑어 daily_cards pk 로 조인한다 — 수락이 수십만 건을 넘으면 요약을 캐시하거나 집계 표로 옮긴다.
create function public.admin_matching_summary()
returns table (
  accepts_today integer, accepts_yesterday integer, accepts_total bigint, accepters_total bigint,
  matches_total bigint, shared_total bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_start timestamptz := (v_today::timestamp at time zone 'Asia/Seoul');
  v_yesterday timestamptz := ((v_today - 1)::timestamp at time zone 'Asia/Seoul');
begin
  return query
  select (select count(*) from public.card_decisions cd where cd.decision = 'accept' and cd.decided_at >= v_start)::integer,
         (select count(*) from public.card_decisions cd
           where cd.decision = 'accept' and cd.decided_at >= v_yesterday and cd.decided_at < v_start)::integer,
         (select count(*) from public.card_decisions cd where cd.decision = 'accept'),
         (select count(distinct dc.owner_id) from public.card_decisions cd
            join public.daily_cards dc on dc.id = cd.card_id where cd.decision = 'accept'),
         (select count(*) from public.matches m),
         (select count(*) from public.matches m where m.trust_passed_at is not null);
end;
$$;

-- 8. 매칭 일별 그래프(수락 · 매칭 · 카톡 공유). 세 사건은 시각 칸이 서로 달라(decided_at · created_at · trust_passed_at) 같은 쌍이어도
-- 다른 날에 잡힌다 — 카톡 공유는 공유가 끝난 날에 센다.
-- shortcut: matches 는 날짜 범위를 훑는다(인덱스 없음) — 1만 줄을 넘으면 created_at · trust_passed_at 인덱스를 더한다.
create function public.admin_matching_daily(p_days integer)
returns table (day date, accept_count integer, match_count integer, share_count integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_from timestamptz;
begin
  if p_days is null or p_days < 1 or p_days > 90 then
    raise exception 'p_days must be between 1 and 90' using errcode = '22023';
  end if;
  v_from := ((v_today - (p_days - 1))::timestamp at time zone 'Asia/Seoul');

  return query
  with accepted as (
    select (cd.decided_at at time zone 'Asia/Seoul')::date as d, count(*)::integer as n
      from public.card_decisions cd
     where cd.decision = 'accept' and cd.decided_at >= v_from
     group by 1
  ), matched as (
    select (m.created_at at time zone 'Asia/Seoul')::date as d, count(*)::integer as n
      from public.matches m where m.created_at >= v_from group by 1
  ), shared as (
    select (m.trust_passed_at at time zone 'Asia/Seoul')::date as d, count(*)::integer as n
      from public.matches m where m.trust_passed_at >= v_from group by 1
  )
  select v_today - (p_days - 1) + g.i, coalesce(ac.n, 0), coalesce(ma.n, 0), coalesce(sh.n, 0)
    from generate_series(0, p_days - 1) as g(i)
    left join accepted ac on ac.d = v_today - (p_days - 1) + g.i
    left join matched ma on ma.d = v_today - (p_days - 1) + g.i
    left join shared sh on sh.d = v_today - (p_days - 1) + g.i
   order by 1;
end;
$$;

-- 9. 누가 누구랑 매칭됐나(최근 순, 커서 쪽 나누기). 반환 칸이 **전부**다 — 사진 · 카톡 아이디 · 대화 · 전화는 싣지 않는다(카톡 아이디는
-- 사용자 상세의 "열람"(사유 필수 · 기록)으로만). 필터는 타입 있는 인자(고정 글자 · uuid · timestamptz)라 PostgREST 필터 문법이 끼어들 길이 없다.
-- 상태: shared = trust_passed_at 있음(이후 누가 나가도 유지) / closed = 공유 전이고 chat_closed_at 이 있거나 참가자 중 left_at 이 있는 사람이 있음 /
-- chatting = 그 밖. 정지 · 탈퇴 중인 사람은 상태에 반영하지 않는다(닉네임은 그대로). 학교 필터는 A 또는 B 쪽 학교.
-- 커서는 (matched_at, match_id) 둘 다 있거나 둘 다 없어야 한다. p_limit 1~101(부르는 쪽이 한 줄 더 달라고 해 다음 쪽 여부를 안다).
-- shortcut: matches 전체 훑기 + 정렬 — 1만 줄을 넘으면 (created_at desc, id desc) 인덱스를 더한다.
create function public.admin_matching_pairs(
  p_status text, p_university uuid, p_before_at timestamptz, p_before_id uuid, p_limit integer
)
returns table (
  match_id uuid, matched_at timestamptz, status text, shared_at timestamptz,
  a_id uuid, a_nickname text, a_university text, b_id uuid, b_nickname text, b_university text
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_status is not null and p_status not in ('chatting', 'shared', 'closed') then
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
    select m.id as mid, m.created_at as mat, m.trust_passed_at as shared, m.profile_a as pa, m.profile_b as pb,
           case when m.trust_passed_at is not null then 'shared'
                when m.chat_closed_at is not null
                  or exists (select 1 from public.match_participants mp where mp.match_id = m.id and mp.left_at is not null)
                  then 'closed'
                else 'chatting' end as st
      from public.matches m
     where p_before_at is null or (m.created_at, m.id) < (p_before_at, p_before_id)
  )
  select l.mid, l.mat, l.st, l.shared, a.id, a.nickname, ua.name, b.id, b.nickname, ub.name
    from listed l
    join public.profiles a on a.id = l.pa
    join public.profiles b on b.id = l.pb
    left join public.universities ua on ua.id = a.university_id
    left join public.universities ub on ub.id = b.university_id
   where (p_status is null or l.st = p_status)
     and (p_university is null or a.university_id = p_university or b.university_id = p_university)
   order by l.mat desc, l.mid desc
   limit p_limit;
end;
$$;

-- Supabase 기본 권한이 새 함수에 anon · authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke all on function public.admin_matching_summary() from public, anon, authenticated;
grant execute on function public.admin_matching_summary() to service_role;

revoke all on function public.admin_matching_daily(integer) from public, anon, authenticated;
grant execute on function public.admin_matching_daily(integer) to service_role;

revoke all on function public.admin_matching_pairs(text, uuid, timestamptz, uuid, integer) from public, anon, authenticated;
grant execute on function public.admin_matching_pairs(text, uuid, timestamptz, uuid, integer) to service_role;

revoke all on function public.admin_health(integer, integer, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.admin_health(integer, integer, integer, integer, integer) to service_role;

revoke all on function public.admin_stats_overview() from public, anon, authenticated;
grant execute on function public.admin_stats_overview() to service_role;

revoke all on function public.admin_stats_daily(integer) from public, anon, authenticated;
grant execute on function public.admin_stats_daily(integer) to service_role;

revoke all on function public.admin_unknown_domains(integer) from public, anon, authenticated;
grant execute on function public.admin_unknown_domains(integer) to service_role;

revoke all on function public.admin_universities_status(boolean) from public, anon, authenticated;
grant execute on function public.admin_universities_status(boolean) to service_role;
