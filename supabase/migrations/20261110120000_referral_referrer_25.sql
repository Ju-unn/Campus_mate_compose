-- 친구 초대 보상 변경(2026-11-10 사용자 「새 사람 50 · 코드 주인 25」): 새로 가입해 코드를 넣은 사람은 그대로 50하트,
-- 코드를 준 사람(referrer)은 50 → 25하트. 본문은 20260928010000_create_referrals.sql 의 redeem_referral 그대로고
-- referrer 에게 주는 grant_hearts 금액만 25 로 바꿨다(이 함수는 그 뒤 마이그레이션에서 다시 정의된 적이 없다).
-- security invoker · search_path '' · 권한(service_role 만 실행)도 원래와 같다. 이미 지급한 원장은 건드리지 않는다.
-- FAQ 두 답변(무료 하트 · 추천 코드 사용법)의 금액 문장도 같이 고친다. 545 "추천 코드는 어디서 보나요?" 는 금액이 없어 그대로다.
-- 시험: supabase/tests/referral_test.sql 3번 묶음(원장 50 · 25, 잔액 25), supabase/tests/faq_test.sql 18 · 22 · 23.
create or replace function public.redeem_referral(p_referee_id uuid, p_code text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_referrer uuid;
  v_referee_hmac bytea;
  v_referrer_hmac bytea;
begin
  -- 탈퇴 · 정지한 사람의 코드는 없는 코드다(ERD 267줄, D5).
  select id into v_referrer
  from public.profiles
  where referral_code = upper(btrim(p_code)) and status not in ('withdrawn', 'suspended');
  if v_referrer is null then
    raise exception 'referral code not found' using errcode = 'CM404';
  end if;
  if v_referrer = p_referee_id then
    raise exception 'referral not allowed' using errcode = 'CM422';
  end if;

  select phone_hmac into v_referee_hmac from public.profile_private where profile_id = p_referee_id;
  select phone_hmac into v_referrer_hmac from public.profile_private where profile_id = v_referrer;

  -- 번호 해시가 빈 옛 계정(백필 전)은 비교하지 않는다(D4).
  if v_referee_hmac is not null then
    -- 같은 번호의 두 계정이 동시에 들어와도 한 번만 통과하게 번호 단위로 줄 세운다. 트랜잭션이 끝나면 풀린다.
    perform pg_advisory_xact_lock(hashtextextended(encode(v_referee_hmac, 'hex'), 0));
    if v_referee_hmac = v_referrer_hmac
       or exists (
         select 1
         from public.referrals r
         join public.profile_private pp on pp.profile_id = r.referee_id
         where pp.phone_hmac = v_referee_hmac and r.referee_id <> p_referee_id
       ) then
      raise exception 'referral not allowed' using errcode = 'CM422';
    end if;
  end if;

  -- 이미 입력한 사람은 PK 가 23505 로 막는다 — 아래 지급까지 가지 않는다.
  insert into public.referrals (referee_id, referrer_id, rewarded_at)
  values (p_referee_id, v_referrer, now());

  perform public.grant_hearts(p_referee_id, 50, 'referral', p_referee_id);
  perform public.grant_hearts(v_referrer, 25, 'referral', p_referee_id);
  return v_referrer;
end;
$$;

revoke execute on function public.redeem_referral(uuid, text) from public, anon, authenticated;
grant execute on function public.redeem_referral(uuid, text) to service_role;

-- FAQ: replace 라서 옛 구절이 없으면(대시보드에서 이미 고쳤으면) 아무것도 바뀌지 않는다 — 두 번 돌려도 같다.
update public.faq
set answer = replace(answer,
                     '친구의 추천 코드를 넣으면 나와 친구가 각각 50하트를 받고,',
                     '친구의 추천 코드를 넣으면 나는 50하트, 코드를 알려 준 친구는 25하트를 받고,'),
    updated_at = now()
where category = 'heart_payment'
  and question = '하트를 무료로 얻는 방법이 있나요?'
  and answer like '%친구의 추천 코드를 넣으면 나와 친구가 각각 50하트를 받고,%';

update public.faq
set answer = replace(answer,
                     '코드를 넣으면 나와 친구가 각각 50하트를 받아요.',
                     '코드를 넣으면 나는 50하트, 코드를 알려 준 친구는 25하트를 받아요.'),
    updated_at = now()
where category = 'account'
  and question = '추천 코드는 어떻게 쓰나요?'
  and answer like '%코드를 넣으면 나와 친구가 각각 50하트를 받아요.%';
