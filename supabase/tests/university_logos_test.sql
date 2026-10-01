-- 학교 로고 칸 · 버킷. 기대값: 대장 요청(2026-10-01, 카드 · 프로필 학교 이름 앞 로고).
-- 로컬 스택에서 `supabase test db`. 트랜잭션 안에서만 돌고 rollback 한다.
begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- 1~2 칸 존재 · 타입
select has_column('public', 'universities', 'logo_path', 'universities 에 logo_path 칸이 있다');
select col_type_is('public', 'universities', 'logo_path', 'text', 'logo_path 는 text 다');

-- 준비: 테스트 학교 한 행
insert into public.universities (id, name, region_group)
values ('00000000-0000-0000-0000-0000000000a1', '로고테스트대학교', 'seoul');

-- 3~4 잘못된 값은 check 로 막힌다
select throws_ok(
  $$update public.universities set logo_path = 'logo.png'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  '23514', null,
  '확장자가 webp 가 아니면 막힌다'
);

select throws_ok(
  $$update public.universities set logo_path = '../x.webp'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  '23514', null,
  '경로 기호가 섞인 이름은 막힌다'
);

-- 5~6 맞는 꼴 · null 은 통과한다
select lives_ok(
  $$update public.universities set logo_path = 'uni-75ee0c4a522d491b.webp'
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  '정해진 꼴의 파일 이름은 통과한다'
);

select lives_ok(
  $$update public.universities set logo_path = null
     where id = '00000000-0000-0000-0000-0000000000a1'$$,
  'null 은 통과한다(로고 없음)'
);

-- 7~9 버킷 설정
select is(
  (select public from storage.buckets where id = 'university-logos'),
  true,
  'university-logos 버킷은 공개다'
);

select is(
  (select file_size_limit from storage.buckets where id = 'university-logos'),
  102400::bigint,
  '파일 크기 제한은 100KB 다'
);

select is(
  (select allowed_mime_types from storage.buckets where id = 'university-logos'),
  array['image/webp'],
  '허용 형식은 webp 뿐이다'
);

-- 10 storage.objects 에는 정책이 없다 — 공개 버킷이라 주소로 읽기는 되고, 목록 조회 · 쓰기는 막힌다.
select is_empty(
  $$select policyname from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'$$,
  'storage.objects 에는 정책이 없다'
);

select * from finish();
rollback;
