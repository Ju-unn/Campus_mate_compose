-- 첫 출시 대상 서울권 대학과 학생인증 메일 도메인 (supabase db reset 때만 들어간다).
-- 도메인은 대표 도메인 하나씩이다. 재학생 메일이 다른 학교(예: 학생 전용 하위 도메인)는
-- 조각 1에서 실제 가입으로 확인한 뒤 university_email_domains 에 행을 추가한다.
with seed (name, domain) as (
  values
    ('서울대학교',     'snu.ac.kr'),
    ('연세대학교',     'yonsei.ac.kr'),
    ('고려대학교',     'korea.ac.kr'),
    ('성균관대학교',   'skku.edu'),
    ('한양대학교',     'hanyang.ac.kr'),
    ('중앙대학교',     'cau.ac.kr'),
    ('경희대학교',     'khu.ac.kr'),
    ('서강대학교',     'sogang.ac.kr'),
    ('이화여자대학교', 'ewha.ac.kr'),
    ('건국대학교',     'konkuk.ac.kr'),
    ('동국대학교',     'dongguk.edu'),
    ('홍익대학교',     'hongik.ac.kr'),
    ('숙명여자대학교', 'sookmyung.ac.kr'),
    ('국민대학교',     'kookmin.ac.kr'),
    ('세종대학교',     'sejong.ac.kr'),
    ('숭실대학교',     'ssu.ac.kr'),
    ('서울시립대학교', 'uos.ac.kr'),
    ('광운대학교',     'kw.ac.kr'),
    ('명지대학교',     'mju.ac.kr'),
    ('상명대학교',     'smu.ac.kr')
),
inserted as (
  insert into public.universities (name, region_group)
  select name, 'seoul' from seed
  returning id, name
)
insert into public.university_email_domains (domain, university_id)
select seed.domain, inserted.id
from seed
join inserted using (name);
