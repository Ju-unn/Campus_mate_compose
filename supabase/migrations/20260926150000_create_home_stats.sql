-- 홈 09b 메인: 서비스 전체 집계 네 값을 한 번에 돌려준다. 부르는 쪽은 FastAPI(service_role) 하나다.
--
-- 단일 행 테이블로 돌려준다(json 아님) — 칸 이름과 타입이 함수 시그니처에 박혀 계약이 DB 에 보이고,
-- pgTAP 이 칸마다 바로 단정할 수 있다. PostgREST 는 한 행짜리 배열로 내려주고 서버가 [0] 을 꺼낸다.
--
-- security invoker 다 — service_role 이 네 테이블 모두 select 권한이 있고 RLS 를 우회하므로
-- definer 로 권한을 빌릴 이유가 없다. 앱 역할이 부르는 길은 아래 revoke 로 막는다.
create function public.home_stats()
returns table (
  delivered_cards bigint,
  signups bigint,
  conversations_started bigint,
  campuses text[]
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    (select count(*) from public.daily_cards),
    (select count(*) from public.profiles where status = 'active'),
    -- 카톡 공유 완료(trust_passed_at)가 아니라 "사람이 쓴 말풍선이 한 건이라도 오간 매칭"이다.
    -- exists 가 messages_match_created_index 의 match_id 앞머리를 탄다.
    (select count(*)
       from public.matches m
      where exists (
        select 1 from public.messages msg
         where msg.match_id = m.id and msg.kind = 'text'
      )),
    (select coalesce(array_agg(u.name order by u.name), '{}')
       from public.universities u
      where exists (
        select 1 from public.profiles p
         where p.university_id = u.id and p.status = 'active'
      ));
$$;

comment on function public.home_stats() is
  '홈 09b 서비스 전체 집계: 누적 카드·active 가입자·말풍선이 오간 매칭·active 학교 이름(이름순). FastAPI 전용';

-- Supabase 기본 권한이 새 함수에 anon·authenticated 실행을 주므로 public 만이 아니라 둘 다 명시해 뺀다.
revoke execute on function public.home_stats() from public, anon, authenticated;
grant execute on function public.home_stats() to service_role;
