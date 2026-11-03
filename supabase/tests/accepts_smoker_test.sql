-- 흡연 "상관없어요" 칸(2026-11-04 사용자 승인): profiles.accepts_smoker 가 값 없음을 허용하고 기본값이 없는지 본다.
-- 값 없음 = 내 흡연 여부를 따른다(비흡연이면 싫어요) → 이 칸을 모르는 옛 앱(1.0.0 · 1.0.1)도 지금과 같은 결과다.
-- 로컬 스택에서 `supabase test db` 로 돌린다. 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

select has_column('public', 'profiles', 'accepts_smoker', '흡연 상관없음 칸이 있다');
select col_type_is('public', 'profiles', 'accepts_smoker', 'boolean', '참 / 거짓 / 값 없음 세 가지다');
select col_is_null('public', 'profiles', 'accepts_smoker', '값 없음을 허용한다(옛 앱은 이 값을 보내지 않는다)');
select col_hasnt_default('public', 'profiles', 'accepts_smoker', '기본값이 없다 — 기존 회원은 값 없음 그대로 내 흡연 여부를 따른다');
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'accepts_smoker', 'SELECT'),
  '로그인한 사람은 읽을 수 있다(행은 RLS 로 본인 것만)'
);
select ok(
  not has_column_privilege('anon', 'public.profiles', 'accepts_smoker', 'SELECT'),
  '로그인 안 한 사람은 읽을 수 없다'
);

select * from finish();
rollback;
