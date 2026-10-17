-- 등록되지 않은 학교 메일 도메인 기록(사용자 요청 10-17): 화이트리스트에 없어 가입하지 못한 사람들의 학교를 나중에
-- university_email_domains 에 더하려고, 거절된 도메인과 그 횟수를 센다.
-- 쓰는 곳은 FastAPI 두 곳의 미등록 도메인 분기다 — 가입 직전 훅(before-user-created)과 POST /school-email/verify.
-- 둘 다 최선만으로 부른다(실패 · 지연이 거절 응답을 바꾸지 않는다, backend/app/signup_policy.py record_unknown_domain).
-- 개인정보 최소화: 도메인과 횟수 · 시각만 둔다. 메일 앞부분 · 사용자 id · IP 는 받지도 저장하지도 않는다.
-- 시험: supabase/tests/unknown_email_domain_test.sql
-- 운영 확인(대시보드 SQL 편집기, 읽기만):
--   select domain, attempt_count, first_seen_at, last_seen_at
--   from public.unknown_email_domain_attempts order by attempt_count desc;

create table public.unknown_email_domain_attempts (
  domain text primary key,
  -- 거절된 시도 횟수다. 사람 수가 아니다 — 한 사람이 다시 시도하면 또 오른다.
  attempt_count integer not null default 1,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),

  -- university_email_domains 와 같은 형식이라 행을 그대로 화이트리스트로 옮길 수 있다. 소문자만 · '@' · 공백 불가.
  -- 길이 253 은 DNS 이름 최대 길이다.
  constraint unknown_email_domain_attempts_domain_format check (
    char_length(domain) between 3 and 253
    and domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$'
  )
);

comment on table public.unknown_email_domain_attempts is
  '화이트리스트에 없어 거절된 학교 메일 도메인과 시도 횟수(도메인만 — 메일 앞부분 · 사용자 id · IP 없음). '
  'FastAPI 전용(record_unknown_email_domain 이 쓴다), 클라이언트 접근 없음. 새 도메인은 5000행까지만 받는다. '
  '읽기: select domain, attempt_count, first_seen_at, last_seen_at '
  'from public.unknown_email_domain_attempts order by attempt_count desc;';

-- RLS: 정책 없음 = 앱은 읽지도 쓰지도 못한다(school_email_claims · signup_blocks 와 같다).
alter table public.unknown_email_domain_attempts enable row level security;

revoke all on table public.unknown_email_domain_attempts from anon, authenticated, service_role;
grant select, insert, update, delete on table public.unknown_email_domain_attempts to service_role;

-- 기록 함수. 입력을 소문자 · 앞뒤 공백 제거로 정리하고, 형식이 이상하면(빈 값 · 메일 주소 · 점 없음 · 너무 김)
-- 오류 없이 무시한다 — 서버는 거절 응답 안에서 부르므로 여기서 오류를 내도 얻는 것이 없다.
-- 남용 방어: 행이 5000개 이상이면 새 도메인은 넣지 않고 이미 있는 도메인의 횟수만 올린다. 임의 도메인을 끝없이 보내
-- 표를 부풀리는 것을 막는다(정상 사용으로는 국내 대학 수보다 훨씬 많은 값이라 닿지 않는다).
-- shortcut: 한도 검사는 잠금 없이 센다 — 동시에 들어온 새 도메인 몇 개가 5000 을 조금 넘길 수 있다. 정확한 상한이
-- 필요해지면 advisory lock 으로 줄 세운다.
-- 동시에 처음 기록되는 같은 도메인은 on conflict 가 받아 횟수를 올린다.
-- security invoker 다(SUPABASE.md §5) — 부르는 service_role 이 표 select · insert · update 권한을 가지고 RLS 를 우회한다.
create function public.record_unknown_email_domain(p_domain text)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.unknown_email_domain_attempts as a (domain)
  select d.domain
  from (select lower(btrim(p_domain)) as domain) as d
  where char_length(d.domain) between 3 and 253
    and d.domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$'
    and (exists (select 1 from public.unknown_email_domain_attempts as e where e.domain = d.domain)
         or (select count(*) from public.unknown_email_domain_attempts) < 5000)
  on conflict (domain) do update
    set attempt_count = a.attempt_count + 1,
        last_seen_at = now();
$$;

comment on function public.record_unknown_email_domain(text) is
  '거절된 학교 메일 도메인 1회 기록(FastAPI 전용, 최선만). 소문자 · 앞뒤 공백 정리, 형식이 이상하면 무시. '
  '처음이면 횟수 1, 다시 오면 +1 · last_seen_at 갱신. 행이 5000개 이상이면 새 도메인은 무시하고 기존 도메인만 올린다. '
  '읽기: select domain, attempt_count, first_seen_at, last_seen_at '
  'from public.unknown_email_domain_attempts order by attempt_count desc;';

revoke all on function public.record_unknown_email_domain(text) from public, anon, authenticated;
grant execute on function public.record_unknown_email_domain(text) to service_role;
