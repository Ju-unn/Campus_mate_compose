-- 홈 배너(home_banners 표 · home-banners 버킷) 검증: 칸 · RLS · 권한(서버만 읽는다) · 기간 check · 버킷 설정.
-- 마이그레이션 20261112122138_create_home_banners. 로컬 스택에서 `supabase test db` 로 돌린다.
-- 트랜잭션 안에서만 돌고 rollback 으로 흔적을 남기지 않는다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- 1. 칸 ---------------------------------------------------------------------------
select has_table('public', 'home_banners', 'home_banners 표가 있다');                              -- 1
select columns_are('public', 'home_banners',
  array['id', 'image_path', 'alt_text', 'sort_order', 'starts_at', 'ends_at', 'created_at'],
  '칸은 일곱 개다');                                                                                -- 2
select col_is_pk('public', 'home_banners', 'id', 'id 가 기본 키다');                                -- 3
select col_type_is('public', 'home_banners', 'sort_order', 'integer', 'sort_order 는 int 다');      -- 4
select col_type_is('public', 'home_banners', 'starts_at', 'timestamp with time zone', 'starts_at 은 timestamptz 다'); -- 5
select col_is_null('public', 'home_banners', 'ends_at', 'ends_at 은 비워 둘 수 있다(끝 없음)');      -- 6
select col_not_null('public', 'home_banners', 'alt_text', 'alt_text 는 비울 수 없다(화면 읽기용)');  -- 7

-- 2. RLS · 권한 -------------------------------------------------------------------
select is(
  (select relrowsecurity from pg_class where oid = 'public.home_banners'::regclass),
  true, 'home_banners 는 RLS 가 켜져 있다'
);                                                                                                   -- 8
select is(
  (select count(*) from pg_policies where tablename = 'home_banners'),
  0::bigint, 'home_banners 에는 정책이 없다(FastAPI 전용)'
);                                                                                                   -- 9

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000b01", "role": "authenticated"}';
select throws_ok(
  $$select id from public.home_banners$$,
  '42501', null, 'authenticated 는 home_banners 를 select 할 수 없다(42501)'
);                                                                                                   -- 10

set local role anon;
select throws_ok(
  $$select id from public.home_banners$$,
  '42501', null, 'anon 은 home_banners 를 select 할 수 없다(42501)'
);                                                                                                   -- 11

reset role;
select ok(
  has_table_privilege('service_role', 'public.home_banners', 'select')
  and not has_table_privilege('authenticated', 'public.home_banners', 'select, insert, update, delete')
  and not has_table_privilege('anon', 'public.home_banners', 'select, insert, update, delete'),
  'service_role 만 home_banners 를 읽는다'
);                                                                                                   -- 12

-- 3. 기본값 · check (service_role) ------------------------------------------------
set local role service_role;
select lives_ok(
  $$insert into public.home_banners (id, image_path, alt_text)
    values ('00000000-0000-0000-0000-00000000b0f1', 'xmas-1.webp', '크리스마스에 어디 가세요?')$$,
  'service_role 은 배너를 넣을 수 있다'
);                                                                                                   -- 13
select is(
  (select sort_order::text || ':' || (ends_at is null)::text || ':' || (starts_at <= now())::text
     from public.home_banners where id = '00000000-0000-0000-0000-00000000b0f1'),
  '0:true:true', '기본값 — 순서 0, 끝 없음, 지금부터'
);                                                                                                   -- 14
select throws_ok(
  $$insert into public.home_banners (image_path, alt_text, starts_at, ends_at)
    values ('x.webp', '문구', '2026-12-01T00:00:00Z', '2026-12-01T00:00:00Z')$$,
  '23514', null, '끝이 시작과 같으면 막는다'
);                                                                                                   -- 15
select throws_ok(
  $$insert into public.home_banners (image_path, alt_text, starts_at, ends_at)
    values ('x.webp', '문구', '2026-12-01T00:00:00Z', '2026-11-30T00:00:00Z')$$,
  '23514', null, '끝이 시작보다 앞이면 막는다'
);                                                                                                   -- 16
select throws_ok(
  $$insert into public.home_banners (image_path, alt_text) values ('x.webp', '   ')$$,
  '23514', null, '공백뿐인 문구(alt_text)는 막는다 — 화면 읽기가 아무것도 못 읽는다'
);                                                                                                   -- 17
select throws_ok(
  $$insert into public.home_banners (image_path, alt_text) values ('', '문구')$$,
  '23514', null, '빈 그림 경로(image_path)는 막는다'
);                                                                                                   -- 18
reset role;

-- 4. 버킷 -------------------------------------------------------------------------
select is(
  (select public from storage.buckets where id = 'home-banners'),
  true, 'home-banners 버킷은 공개다'
);                                                                                                   -- 19
select is(
  (select file_size_limit from storage.buckets where id = 'home-banners'),
  1048576::bigint, '파일 크기 제한은 1MB 다'
);                                                                                                   -- 20
select is(
  (select allowed_mime_types from storage.buckets where id = 'home-banners'),
  array['image/webp'], '허용 형식은 webp 뿐이다'
);                                                                                                   -- 21

select * from finish();
rollback;
